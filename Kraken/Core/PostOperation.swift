//
//  PostOperation.swift
//  Kraken
//
//  Created by Chall Fry on 5/24/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit
import CoreData

/*
	All:
		- Current User
		- Initial post time
		- unique ID
		
	Seamail
		- users
		- subject
		- text
		- threadID. New seamail needs users & subject. Replies need threadID. Can't have both.
		
	Twitarr
		- text
		- parent
		- photo
		- id		// for editing tweets
		
	Twitarr Reaction
		- id
		- reaction word
		- add/remove
		
	Personal Comment
		- user comment applies to
		- text
		
	Star User
		- user start applies to
		- on/off
		
	User Profile
		- display name
		- email
		- home location
		- real name 
		- pronouns
		- room number
		
	User Photo
		- photo
		- add/delete
		
	Forums Post
		- subject
		- text
		- photos
		- thread id			// for posting replies; no subject
		- edit id			// for editing posts
		- delete yes/no
	
	Forums Post React
		- forumID?
		- postID
		- react type
		- add/remove
		
	Event Favorite
		- id
		- add/remove
*/

@objc public class PostOperationDataManager: NSObject {
	static let shared = PostOperationDataManager()
	
	@objc dynamic var pendingOperationCount: Int = 0
	@objc dynamic var operationsWithErrorsCount: Int = 0

	// This controller operates in the network operation context.
	fileprivate let controller: NSFetchedResultsController<PostOperation>
	
	var nextCheckTimer: Timer?
	var insideCheckForOpsToDeliver = false
	
// MARK: Methods
	
	override init() {
		let context = LocalCoreData.shared.networkOperationContext
		let fetchRequest = NSFetchRequest<PostOperation>(entityName: "PostOperation")
		fetchRequest.sortDescriptors = [NSSortDescriptor(key: "originalPostTime", ascending: true)]
		controller = NSFetchedResultsController(fetchRequest: fetchRequest, managedObjectContext: context, 
				sectionNameKeyPath: nil, cacheName: nil)
		super.init()
		controller.delegate = self

		context.perform {
			do {
				try self.controller.performFetch()
				self.controllerDidChangeContent(self.controller as! NSFetchedResultsController<NSFetchRequestResult>)
			} catch {
				CoreDataLog.error("Failed to fetch PostOperations", ["error" : error])
			}
		}

		// Check for postOps to deliver to the server whenever any of the things that can block delivery change state.
		CurrentUser.shared.tell(self, when: "loggedInUser") { observer, observed in 
			observer.checkForOpsToDeliver()
		}
		Settings.shared.tell(self, when: "blockEmptyingPostOpsQueue") { observer, observed in 
			observer.checkForOpsToDeliver()
		}
		NetworkGovernor.shared.tell(self, when: "connectionState") { observer, observed in 
			observer.checkForOpsToDeliver()
		}
	}
		
	// Does not check whether this op is authored by the current user.
	// Can be called with an op object in the main context.
	func remove(op: PostOperation) {
		LocalCoreData.shared.performLocalCoreDataChange { context, currentUser in
			context.pushOpErrorExplanation("Couldn't save context when deleting a PostOperation.")
			let opInContext = context.object(with: op.objectID)
			context.delete(opInContext)
		}
	}
		
	// This method looks through all the ops, finds one that's ready to be sent to the server, and sends it.
	// If there's more ops to send, it sets a timer. If an op failed and needs to be re-tried, the same timer
	// is set for that retry time. Once all ops are sent the timer stops firing. This means that things that could
	// add ops or unblock the sending of ops should call checkForOpsToDeliver.
	func checkForOpsToDeliver() {
		guard CurrentUser.shared.isLoggedIn() else { 
			NetworkLog.debug("Not sending ops to server; nobody is logged in.")
			return 
		}
		guard !Settings.shared.blockEmptyingPostOpsQueue else {
			NetworkLog.debug("Not sending ops to server; blocked by user setting")
			return
		}
		guard nextCheckTimer == nil else {
			NetworkLog.debug("Not sending ops to server just now; we're on a timer.")
			return
		}
			
		LocalCoreData.shared.performLocalCoreDataChange { context, currentUser in
			guard self.insideCheckForOpsToDeliver == false else { return }
			self.insideCheckForOpsToDeliver = true
			defer {	
				self.insideCheckForOpsToDeliver = false
			}

			if let operations = self.controller.fetchedObjects {
				var earliestCallTime: Date?
				var sentOpThisCall = false

				for op in operations {
					// Test 1. Only send ops authored by the logged in user.
					if op.author.userID != currentUser.userID {
						continue
					}	
				
					// Test 2: Don't send ops that aren't ready. Ops that received server errors need to be 'resent' by user.
					// Ops in the networkError state have had too main failed connection attempts; reset them when we know
					// we have a good connection.
					if op.operationState == .networkError && NetworkGovernor.shared.connectionState == .canConnect {
						op.operationState = .readyToSend
					}
					if op.operationState != .readyToSend {
						continue
					} 
										
					// Test 3: Exponential back off. Don't run an op until its next run date.
					// Also -- if it's an op we're not running yet, determine if it's the op we'll be running *next*
					if let nextCallTime = op.nextNetworkCallTime, nextCallTime > Date() {
						if earliestCallTime == nil { 
							earliestCallTime = nextCallTime
						}
						else if let earliest = earliestCallTime, nextCallTime < earliest {
							earliestCallTime = nextCallTime
						}
						continue
					}
					
					if sentOpThisCall {
						// We *would* send this op, except we just sent one. Once we've determined that there's ops
						// that are ready to send but unsent, we can break. Our next call time is 1 sec from now.
						earliestCallTime = Date().addingTimeInterval(2.0)
						break
					}
					else {
						// Tell the op to send to server here
						NetworkLog.debug("\(Date()): Sending op to server", ["op" : op])
						op.post(context: context)
						sentOpThisCall = true
					}
				}
				
				// Start a timer that will fire whenever it's time for us to try sending the next op.
				// If earliestCallTime is nil, there's no ops in the pending state.
				if let fireTime = earliestCallTime {
					DispatchQueue.main.async {
						NetworkLog.debug("\(Date()): Setting next op post time to \(fireTime.timeIntervalSinceNow)")
						self.nextCheckTimer?.invalidate()
						self.nextCheckTimer = Timer.scheduledTimer(withTimeInterval: fireTime.timeIntervalSinceNow, 
								repeats: false) { timer in 
							NetworkLog.debug("\(Date()): Timer fired. About to check for more ops to deliver.")
							self.nextCheckTimer = nil
							self.checkForOpsToDeliver()
						}
					}
				}
				
				// TODO: Should be sure to run the check fn on app foregrounding.
			}
		}
	}
	
	fileprivate func countOpsWithErors() {
		let context = LocalCoreData.shared.networkOperationContext
		context.perform {
			var opsWithErrors = 0
			if let operations = self.controller.fetchedObjects {
				for op in operations {
					if op.errorString != nil {
						opsWithErrors += 1
					}
				}
			}
			self.operationsWithErrorsCount = opsWithErrors
		}
	}
		

}

extension PostOperationDataManager : NSFetchedResultsControllerDelegate {

	// This alerts us whenever an op gets added. We then check all the ops in the queue, to see if any can be delivered.
	public func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
		pendingOperationCount = controller.fetchedObjects?.count ?? 0
		checkForOpsToDeliver()
		countOpsWithErors()
	}
}

@objc public enum PostOperationState: Int32 {
	case notReadyToSend = 0
	case readyToSend = 1
	case sentNetworkCall = 2
	case networkError = 3
	case serverError = 4
	case callSuccess = 5
}


/* 'Post' in this context is any REST call that changes server state, where you need to be logged in.
	Usually delivered via HTTP POST.
*/
@objc(PostOperation) public class PostOperation: KrakenManagedObject {
	
		// A descriptive string explaing what this op is going to do.
		// Subclasses should set this value.
	@NSManaged public var operationDescription: String?

		// TRUE if this post can be delivered to the server
	@NSManaged public var operationState: PostOperationState
		
		// Since you must be logged in to send any content to the server, including likes/reactions,
		// every postop has an author.
	@NSManaged public var author: KrakenUser
	
		// This is the time the post was 'committed' locally. If we're offline at post time, it may not
		// post until much later. Even if we're online, the server makes its own timestamp when it receives the post.
	@NSManaged public var originalPostTime: Date
	
		// If we attempt to send a post to the server and it fails, save the error here
		// so we can display it to the user later.
	@NSManaged public var errorString: String?
	
	// NOTE: All variables NOT @NSManaged are transient, as this object could get faulted at any time.
	// They also don't update between contexts, so they are all considered NetworkOperationContext only.
			
	// For a poor-man's exponential backoff algorithm. 2s, 4s, 8s, 16s 32s.
	public var nextNetworkCallTime: Date?
	public var retryCount = 0
	
// MARK: Methods
	
	// AwakeFromInsert is called when a new PostOp is initialized. NOT called when it's fetched or faulted.
	// Since we call it from within the context.perform() where the object gets built, we can set up some boilerplate here.
	override public func awakeFromInsert() {
		super.awakeFromInsert()
		if let moc = managedObjectContext, let currentUser = CurrentUser.shared.getLoggedInUser(in: moc) {
			author = currentUser
		}
		originalPostTime = Date()
		operationState = .notReadyToSend
	}
		
	func operationStatus() -> String {
		var statusString: String
		if isDeleted {
			return "Operation Cancelled"
		}
		switch operationState {
		case .notReadyToSend: statusString = "Not ready to send to the server yet"
		case .readyToSend: statusString = "Waiting to send"
		case .sentNetworkCall: statusString = "Posting to server"
		case .networkError: statusString = "Couldn't reach the server. Will try again later."
		case .serverError: statusString = "Received error from server. Blocked until error is resolved."
		case .callSuccess: statusString = "Success"
		}
		return statusString
	}
	
	func setOperationState(_ newState: PostOperationState) {
		LocalCoreData.shared.performNetworkParsing { context in
			context.pushOpErrorExplanation("Could set operation state for a PostOp.")
			if let selfInContext = try context.existingObject(with: self.objectID) as? PostOperation {
				selfInContext.operationState = newState
			}
		}
	}
	
	func post(context: NSManagedObjectContext) {
		operationState = .serverError
		errorString = "Kraken hasn't implemented this operation yet."
	}
		
	// Ops should call this fn during post() iff the op can be sent; this fn marks the post as being sent in Core Data.
	func confirmPostBeingSent(context: NSManagedObjectContext) {
		context.pushOpErrorExplanation("A postOp got a CoreData error; couldn't store state change back into op.")
		operationState = .sentNetworkCall
		errorString = nil					// If we're retrying after error, error gets cleared.
	}
	
	// Subclasses can call this to get their URLRequest sent to the server. Handles some of the common
	// error-handling and bookeeping functions.
	fileprivate func queueNetworkPost(request: URLRequest, success: @escaping (Data) throws -> Void, 
			failure: ((ServerError) -> Void)? = nil) {
		NetworkGovernor.shared.queue(request) { (package: NetworkResponse) in
			do {
				if let err = package.serverError {
					self.recordServerErrorFailure(err)
					failure?(err)
				}
				else if package.networkError != nil {
					if self.retryCount > 4 {
						// If we network error too many times, record the error and stop trying.
						LocalCoreData.shared.performLocalCoreDataChange { context, user in 
							let opInContext = context.object(with: self.objectID) as! PostOperation
							opInContext.operationState = .networkError
						}
					}
					else {
						// Exponential backoff, but try again by moving to the ready state.
						self.retryCount += 1
						self.nextNetworkCallTime = Date().addingTimeInterval(TimeInterval(pow(2.0, Double(min(self.retryCount, 5)))))
						LocalCoreData.shared.performLocalCoreDataChange { context, user in 
							let opInContext = context.object(with: self.objectID) as! PostOperation
							opInContext.operationState = .readyToSend
						}
					}
				}
				else if let data = package.data {
					// The assumption here is that if we get a non-error response from the server, the call worked and 
					// the server has enacted the change we posted. So, even if we fail to decode and process the response
					// or save to Core Data, the call still succeeded.
					self.recordOpSuccess()
					try success(data)
					
					return
				}
				else {
					// Some operations don't return any data on success, such as DELETE /api/v2/tweet/:id.
					self.recordOpSuccess()
					try success(Data())
					return
				}
			}
			catch {
				NetworkLog.error("Failure processing network response.", ["Error" : error, "URL" : request.url as Any])
			}
		}
	}
		
	func recordOpSuccess() {
		LocalCoreData.shared.performLocalCoreDataChange { context, currentUser in
			context.pushOpErrorExplanation("Op succeeded, but we couldn't record the success in Core Data.")
			let opInContext = context.object(with: self.objectID) as! PostOperation
			opInContext.operationState = .callSuccess
		}
			
		// Wait a bit, then remove ourselves from Core Data.
		DispatchQueue.global().asyncAfter(deadline: .now() + DispatchTimeInterval.seconds(2)) {
			PostOperationDataManager.shared.remove(op: self)
		}
	}
	
	// Server Error means we got a HTTP response from the server indicating an error condition. Generally
	// for postOps this means we need to record the error in Core Data and mark the op as not ready until the 
	// user looks at it (often, they have to edit their post somehow). This is different from network errors,
	// where we can just keep resubmitting the op with no changes (but with exponential backoff--I'm not a monster).
	func recordServerErrorFailure(_ serverError: ServerError) {
		LocalCoreData.shared.performLocalCoreDataChange { context, currentUser in
			context.pushOpErrorExplanation("A postOp got a server error, which we couldn't store back in the postOp.")
			let opInContext = context.object(with: self.objectID) as! PostOperation
			opInContext.errorString = serverError.getCompleteError()
			opInContext.operationState = .serverError
		}
	}
}

// MARK: - PostOp Types

@objc(PostOpTweet) public class PostOpTweet: PostOperation {
	@NSManaged public var text: String
	
	@NSManaged public var photos: NSOrderedSet?			// PostOpPhoto_Attachment. Always matches new state.
	
		// Parent tweet, if this is a response. Can be nil.
	@NSManaged public var parent: TwitarrPost?

		// Reply Group ID, if this is a response. It's possible to reply to a tweet that has never been loaded,
		// as a 'reply' to a reply is really a reply to the tweet that started the ReplyGroup.
	@NSManaged public var replyGroup: Int64
	
		// If non-nil, this op edits the given tweet.
	@NSManaged public var tweetToEdit: TwitarrPost?
	
	func prepare(context: NSManagedObjectContext, postText: String, replyGroup: Int64? = nil, tweetToEdit: TwitarrPost? = nil) {
		text = postText
		self.replyGroup = replyGroup ?? -1
		if let replyGroup = replyGroup {
			parent = TwitarrDataManager.shared.getTweetWithID(replyGroup, inContext: context)
		}
		self.tweetToEdit = tweetToEdit
		operationState = .readyToSend
		
	}
				
	override public func willSave() {
		super.willSave()
		if operationDescription != nil { return }
		if tweetToEdit != nil {
			operationDescription = "Editing a Twitarr tweet"
		}
		else {
			operationDescription = "Posting a new Twitarr tweet"
		}
	}

	override func post(context: NSManagedObjectContext) {
		confirmPostBeingSent(context: context)
		
		var uploadImages: [TwitarrV3ImageUploadData] = []
		if let photoSet = photos {
			for photo in photoSet {
				if let photoAsThing = photo as? PostOpPhoto_Attachment {
					uploadImages.append(photoAsThing.makeV3ImageUploadData())
				}
			}
		}
		let postStruct = TwitarrV3PostContentData(text: text, images: uploadImages)
		let httpContentData = try! Settings.v3Encoder.encode(postStruct)

		var path: String
		if let editingPost = self.tweetToEdit {
			path = "/api/v3/twitarr/\(editingPost.id)/update"
		}
		else if replyGroup >= 0 {
			path = "/api/v3/twitarr/\(replyGroup)/reply"
		}
		else {
			path = "/api/v3/twitarr/create"
		}
		var request = NetworkGovernor.buildTwittarRequest(withPath: path, query: nil)				
		request.httpBody = httpContentData
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		NetworkGovernor.addUserCredential(to: &request, forUser: author)
		request.httpMethod = "POST"

		self.queueNetworkPost(request: request) { data in
			do {
				let response = try Settings.v3Decoder.decode(TwitarrV3TwarrtData.self, from: data)
				TwitarrDataManager.shared.ingestNewUserPost(post: response)
			} 
			catch {
				self.recordServerErrorFailure(ServerError("Failure parsing response to new Twitarr post request."))
				NetworkLog.error("Failure parsing response to new Twitarr post request.", 
						["Error" : error, "URL" : request.url as Any])
			}
		}
	}
}

@objc(PostOpTweetReaction) public class PostOpTweetReaction: PostOperation {
	@NSManaged public var reactionWord: String
		
		// Parent tweet, if this is a response. Can be nil.
	@NSManaged public var sourcePost: TwitarrPost?
		
	override public func awakeFromInsert() {
		super.awakeFromInsert()
		operationDescription = "Posting a reaction to a Twitarr tweet."
	}

	override func post(context: NSManagedObjectContext) {
		guard let post = sourcePost else { 
			self.recordServerErrorFailure(ServerError("The post has disappeared. Perhaps it was deleted serverside?"))
			return
		}
		confirmPostBeingSent(context: context)
		
		// POST /api/v3/twitarr/ID/<like|laugh|love|unreact>
		var encodedReactionWord: String
		if ["laugh", "like", "love"].contains(reactionWord) {
			encodedReactionWord = reactionWord
		}
		else {
			encodedReactionWord = "unreact"
		}
		var request = NetworkGovernor.buildTwittarRequest(withEscapedPath: 
				"/api/v3/twitarr/\(post.id)/\(encodedReactionWord)", query: nil)
		NetworkGovernor.addUserCredential(to: &request, forUser: author)
		request.httpMethod = "POST"
		
		self.queueNetworkPost(request: request, success: { data in
			if let response = try? Settings.v3Decoder.decode(TwitarrV3TwarrtData.self, from: data) {
				TwitarrDataManager.shared.ingestNewUserPost(post: response)
			}
		})
	}
}

@objc(PostOpTweetDelete) public class PostOpTweetDelete: PostOperation {
	@NSManaged public var tweetToDelete: TwitarrPost?

	override public func awakeFromInsert() {
		super.awakeFromInsert()
		operationDescription = "Deleting a Twitarr tweet."
	}

	override func post(context: NSManagedObjectContext) {
		guard let post = tweetToDelete else { 
			self.recordServerErrorFailure(ServerError("The post has disappeared. Perhaps it was deleted serverside?"))
			return
		}
		confirmPostBeingSent(context: context)
		
		// DELETE /api/v3/twitarr/ID
		var request = NetworkGovernor.buildTwittarRequest(withPath: "/api/v3/twitarr/\(post.id)", query: nil)
		NetworkGovernor.addUserCredential(to: &request, forUser: author)
		request.httpMethod = "DELETE"
		
		self.queueNetworkPost(request: request, success: { data in
			LocalCoreData.shared.performNetworkParsing { context in
				context.pushOpErrorExplanation("Failure saving tweet deletion back to Core Data.")
				let postInContext = try context.existingObject(with: post.objectID) as! TwitarrPost
				context.delete(postInContext)
			}
		}, failure: { error in
			// Even if the call fails we may need to delete the tweet--particularly if the call fails because the 
			// tweet is no longer there
			if let statusCode = error.httpStatus, statusCode == 404 {
				LocalCoreData.shared.performNetworkParsing { context in
					context.pushOpErrorExplanation("Failure saving tweet deletion back to Core Data.")
					let postInContext = try context.existingObject(with: post.objectID) as! TwitarrPost
					context.delete(postInContext)
				}
			}		
		})
	}
}

// Used for creating NEW forum threads, adding posts to existing threads, and editing existing posts.
@objc(PostOpForumPost) public class PostOpForumPost: PostOperation {
	@NSManaged public var subject: String?				// Non-nil iff we're making a new thread
	@NSManaged public var text: String?					// nil to not change text. Can't be "".
	
	@NSManaged public var photos: NSOrderedSet?			// PostOpPhoto_Attachment. Always matches new state.
	@NSManaged public var thread: ForumThread?			// If nil, this is a new thread (and subject must be non-nil).
	@NSManaged public var category: ForumCategory?		// Non-nil iff we're making a new thread
	@NSManaged public var editPost: ForumPost?			// If non-nil, we are editing this post.
	
	override public func willSave() {
		super.willSave()
		if operationDescription != nil { return }
		if thread != nil {
			operationDescription = "Posting a Forums post"
		}
		else {
			operationDescription = "Posting a new Forum thread"
		}
	}

	override func post(context: NSManagedObjectContext) {
		
		var path: String
		var content: Data
		var isNewThread = false
		
		var uploadImages: [TwitarrV3ImageUploadData] = []
		if let photoSet = photos {
			for photo in photoSet {
				if let photoAsThing = photo as? PostOpPhoto_Attachment {
					uploadImages.append(photoAsThing.makeV3ImageUploadData())
				}
			}
		}

		if let editPost = editPost {
			// If it's an edit, takes a TwitarrV3PostContentData, returns a TwitarrV3PostData
			path = "/api/v3/forum/post/\(editPost.id)/update"
			let newText = text ?? editPost.text
			let postData = TwitarrV3PostContentData(text: newText, images: uploadImages)
			content = try! Settings.v3Encoder.encode(postData)
		}
		else if let existingThread = thread {
			guard let text = text else {
				recordServerErrorFailure(ServerError("Forum posts must contain non-empty text."))
				return
			}
			// If it's a new post in an existing thread, takes a TwitarrV3PostContentData, returns a TwitarrV3PostData
			path = "/api/v3/forum/\(existingThread.id)/create"
			let postData = TwitarrV3PostContentData(text: text, images: uploadImages)
			content = try! Settings.v3Encoder.encode(postData)
		}
		else if let category = category {
			// New thread, takes a TwitarrV3ForumCreateData, returns a TwitarrV3ForumData
			guard let subject = subject else { 
				recordServerErrorFailure(ServerError("Forum posts must have either a subject, or a parent Forum Thread to post to."))
				return
			}
			guard let text = text else {
				recordServerErrorFailure(ServerError("Forum posts must contain non-empty text."))
				return
			}
			isNewThread = true
			path = "/api/v3/forum/categories/\(category.id)/create"
			let firstPostData = TwitarrV3PostContentData(text: text, images: uploadImages)			
			let postData = TwitarrV3ForumCreateData(title: subject, firstPost: firstPostData)
			content = try! Settings.v3Encoder.encode(postData)
		}
		else {
			recordServerErrorFailure(ServerError("Forum post operation is malformed."))
			return
		}
		confirmPostBeingSent(context: context)
		
		var request = NetworkGovernor.buildTwittarRequest(withPath: path, query: nil)
		NetworkGovernor.addUserCredential(to: &request, forUser: author)
		request.httpMethod = "POST"
		request.httpBody = content
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		self.queueNetworkPost(request: request, success: { data in
			if isNewThread {
				let response = try Settings.v3Decoder.decode(TwitarrV3ForumData.self, from: data)
				ForumPostDataManager.shared.parseThreadWithPosts(for: self.thread, inCategory: self.category, from: response)
			}
			else {
				let response = try Settings.v3Decoder.decode(TwitarrV3PostData.self, from: data)
				
				// Only build CD objects out of the response if this is an edit. For new posts, we don't know
				// whether there were intervening posts betwen the last post we know about and this new post.
				// Therefore, don't show the new post until we do a normal load on the thread.
				if let editingPost = self.editPost, editingPost.id == response.postID {
					ForumPostDataManager.shared.parsePostData(inThread: editingPost.thread, from: response)
				}
				else if let thread = self.thread {
					ForumPostDataManager.shared.loadThreadPosts(for: thread, fromOffset: thread.posts.count - 1, 
							done: { _,_ in })
				}
			}
		})
	}
}

@objc(PostOpForumFavorite) public class PostOpForumFavorite: PostOperation {
	@NSManaged public var favorite: Bool
		
		// The forum to favorite.
	@NSManaged public var sourceForum: ForumThread?
	
	override public func awakeFromInsert() {
		super.awakeFromInsert()
		operationDescription = "Favoriting a Forum Thread."
	}

	override func post(context: NSManagedObjectContext) {
		guard let forum = sourceForum else { 
			self.recordServerErrorFailure(ServerError("The forum has disappeared. Perhaps it was deleted serverside?"))
			return
		}
		let forumObjectID = forum.objectID
		confirmPostBeingSent(context: context)
		
		// POST  /api/v3/forum/ID/favorite
		var request = NetworkGovernor.buildTwittarRequest(withEscapedPath: 
				"/api/v3/forum/\(forum.id)/favorite", query: nil)
		NetworkGovernor.addUserCredential(to: &request, forUser: author)
		request.httpMethod = favorite ? "POST" : "DELETE"
		
		self.queueNetworkPost(request: request, success:  { data in
			LocalCoreData.shared.performNetworkParsing { context in
				context.pushOpErrorExplanation("Failure saving change to Forum follow state.")
				if let forumInContext = context.object(with: forumObjectID) as? ForumThread,
						let rco = forumInContext.getReadCountObject(context: context) {
					rco.isFavorite = self.favorite
				}
			}
		})
	}
}


// Photo data to be attached to a forum post, tweet, or fez post. Specifies *either* a new photo to upload 
// or an existing photo already on the server.
@objc(PostOpPhoto_Attachment) public class PostOpPhoto_Attachment: KrakenManagedObject {
	@NSManaged public var mimetype: String
	
	// Either imageData or filename must be set.
	@NSManaged public var imageData: Data?
	@NSManaged public var filename: String?				// Only set if image came from server.
	
	// One of these must be set.
	@NSManaged public var parentForumPostOp: PostOpForumPost?
	@NSManaged public var parentTweetPostOp: PostOpTweet?
	
	func setupFromPhotoData(_ from: PhotoDataType) {
		switch from {
		case .data(let data, let mimetype):
			self.imageData = data
			self.mimetype = mimetype
		case .server(let filename, let mimetype):
			self.filename = filename
			self.mimetype = mimetype
		default:
			CoreDataLog.error("Could not set up PostOpPhoto_Attachment from PhotoDataType. Enum must be .data or .server.")
		}
	}
	
	func makeV3ImageUploadData() -> TwitarrV3ImageUploadData {
		var result = TwitarrV3ImageUploadData()
		if let image = imageData {
			result.image = image
		}
		else if let fn = filename {
			result.filename = fn
		}
		else {
			CoreDataLog.error("PostOpForum_Photo malformed. Either filename or image must be non=empty.")
		}
		return result
	}
}

@objc(PostOpForumPostDelete) public class PostOpForumPostDelete: PostOperation {
	@NSManaged public var postToDelete: ForumPost?

	override public func awakeFromInsert() {
		super.awakeFromInsert()
		operationDescription = "Deleting a Forum Post."
	}

	override func post(context: NSManagedObjectContext) {
		guard let post = postToDelete else { 
			self.recordServerErrorFailure(ServerError("The post has disappeared. Perhaps it was deleted serverside?"))
			return
		}
		confirmPostBeingSent(context: context)
		
		// DELETE  /api/v2/forums/:id/:post_id
		var request = NetworkGovernor.buildTwittarRequest(withPath: "/api/v3/forum/post/\(post.id)", query: nil)
		NetworkGovernor.addUserCredential(to: &request, forUser: author)
		request.httpMethod = "DELETE"
		self.queueNetworkPost(request: request, success:  { data in
			LocalCoreData.shared.performNetworkParsing { context in
				context.pushOpErrorExplanation("Failure saving forum post deletion back to Core Data.")
				if let postInContext = try context.existingObject(with: post.objectID) as? ForumPost {
					context.delete(postInContext)
				}
			}
		})
	}
	
}


@objc(PostOpForumPostReaction) public class PostOpForumPostReaction: PostOperation {
	@NSManaged public var reactionWord: String
		
		// The post to apply the reaction to.
	@NSManaged public var sourcePost: ForumPost?
	
	override public func awakeFromInsert() {
		super.awakeFromInsert()
		operationDescription = "Posting a reaction to a Forums post."
	}

	override func post(context: NSManagedObjectContext) {
		guard let post = sourcePost else { 
			self.recordServerErrorFailure(ServerError("The post has disappeared. Perhaps it was deleted serverside?"))
			return
		}
		confirmPostBeingSent(context: context)
		
		// POST /api/v3/forum/post/ID/laugh
		var encodedReactionWord: String = "unreact"
		if ["laugh", "like", "love"].contains(reactionWord) {
			encodedReactionWord = reactionWord
		}
		var request = NetworkGovernor.buildTwittarRequest(withEscapedPath: 
				"/api/v3/forum/post/\(post.id)/\(encodedReactionWord)", query: nil)
		NetworkGovernor.addUserCredential(to: &request, forUser: author)
		request.httpMethod = "POST"
		
		self.queueNetworkPost(request: request, success:  { data in
			LocalCoreData.shared.performNetworkParsing { context in
				context.pushOpErrorExplanation("Failure saving change to Forum Post reaction.")
				
				let response = try Settings.v3Decoder.decode(TwitarrV3PostData.self, from: data)
				ForumPostDataManager.shared.parsePostData(inThread: post.thread, from: response)
			}
		})
	}
}


@objc(PostOpSeamailThread) public class PostOpSeamailThread: PostOperation {
	@NSManaged public var subject: String
	@NSManaged public var text: String
	@NSManaged public var recipients: Set<PotentialUser>?
	@NSManaged public var makeOpen: Bool

	override public func awakeFromInsert() {
		super.awakeFromInsert()
		operationDescription = "Creating a new Seamail thread."
	}

	override func post(context: NSManagedObjectContext) {
		confirmPostBeingSent(context: context)
				
		while let unknownUser = recipients?.first(where: { $0.actualUser == nil }) {
			UserManager.shared.loadUser(unknownUser.username, inContext: context) { actualUser in
				LocalCoreData.shared.performLocalCoreDataChange { context, currentUser in
					if let foundUser = actualUser {
						unknownUser.actualUser = foundUser
					}
					else {
						self.recipients?.remove(unknownUser)
					}
				}
			}
		}
		
		// POST /api/v3/fez/create
		var request = NetworkGovernor.buildTwittarRequest(withPath: "/api/v3/fez/create", query: nil)
		NetworkGovernor.addUserCredential(to: &request, forUser: author)
		request.httpMethod = "POST"
		let userIDs = recipients?.compactMap { $0.actualUser?.userID } ?? []
		let newThreadStruct = TwitarrV3FezContentData(fezType: makeOpen ? .open : .closed, title: subject, info: "", 
				startTime: nil, endTime: nil, location: nil, minCapacity: 0, maxCapacity: 0, initialUsers: userIDs)
		let newThreadData = try! Settings.v3Encoder.encode(newThreadStruct)
		request.httpBody = newThreadData
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		
		self.queueNetworkPost(request: request, success: { data in
			let response = try Settings.v3Decoder.decode(TwitarrV3FezData.self, from: data)
			SeamailDataManager.shared.ingestSeamailThread(from: response) { thread in
				SeamailDataManager.shared.queueNewSeamailMessageOp(existingOp: nil, message: self.text, 
						thread: thread, done: { msg in return})
			}
		})
	}
}

@objc(PostOpLFGCreate) public class PostOpLFGCreate: PostOperation {
	@NSManaged public var editingLFG: SeamailThread?
	@NSManaged public var lfgType: String			// Much match a .raw from TwitarrV3FezType
	@NSManaged public var title: String
	@NSManaged public var info: String
	@NSManaged public var location: String
	@NSManaged public var startTime: Date
	@NSManaged public var endTime: Date
	@NSManaged public var minCapacity: Int32
	@NSManaged public var maxCapacity: Int32

	override public func awakeFromInsert() {
		super.awakeFromInsert()
		operationDescription = nil
	}

	override public func willSave() {
		super.willSave()
		// willSave gets called repeatedly until we don't set any values!
		if editingLFG != nil && operationDescription != "Updating your LFG" {
			operationDescription = "Updating your LFG"
		}
		else if editingLFG == nil && operationDescription != "Creating a new LFG" {
			operationDescription = "Creating a new LFG"
		}
	}
	
	override func post(context: NSManagedObjectContext) {
		guard let lfgtype = TwitarrV3FezType(rawValue: lfgType) else {
			self.recordServerErrorFailure(ServerError("Invalid LFG type. Cannot complete creating this LFG."))
			return
		}
		confirmPostBeingSent(context: context)
		
		var path: String
		if let lfgBeingEdited = editingLFG { 
			// POST /api/v3/fez/ID/update -- updating an existing LFG
			path = "/api/v3/fez/\(lfgBeingEdited.id)/update"
		}
		else {
			// POST /api/v3/fez/create -- creating a new LFG
			path = "/api/v3/fez/create"
		}
		var request = NetworkGovernor.buildTwittarRequest(withPath: path, query: nil)
		NetworkGovernor.addUserCredential(to: &request, forUser: author)
		request.httpMethod = "POST"
		let newLFGStruct = TwitarrV3FezContentData(fezType: lfgtype, title: title, info: info,  startTime: startTime, endTime: endTime, 
				location: location, minCapacity: minCapacity, maxCapacity: maxCapacity, initialUsers: [])
		let newThreadData = try! Settings.v3Encoder.encode(newLFGStruct)
		request.httpBody = newThreadData
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		
		self.queueNetworkPost(request: request, success: { data in
			let response = try Settings.v3Decoder.decode(TwitarrV3FezData.self, from: data)
			SeamailDataManager.shared.ingestSeamailThread(from: response) { thread in
				
			}
		})
	}
}

// Used for both LFG and seamail messages
@objc(PostOpSeamailMessage) public class PostOpSeamailMessage: PostOperation {
	@NSManaged public var thread: SeamailThread?
	@NSManaged public var text: String

	override public func awakeFromInsert() {
		super.awakeFromInsert()
		operationDescription = "Post a new Seamail message."
	}

	override func post(context: NSManagedObjectContext) {
		guard let seamailThread = thread else { 
			self.recordServerErrorFailure(ServerError("The Seamail thread has disappeared. Perhaps it was deleted on the server?"))
			return
		}
		confirmPostBeingSent(context: context)
		
		// POST /api/v3/fez/ID/post
		var request = NetworkGovernor.buildTwittarRequest(withPath: "/api/v3/fez/\(seamailThread.id)/post", query: nil)
		NetworkGovernor.addUserCredential(to: &request, forUser: author)
		request.httpMethod = "POST"
		let newMessageStruct = TwitarrV3PostContentData(text: text, images: [])
		let newMessageData = try! Settings.v3Encoder.encode(newMessageStruct)
		request.httpBody = newMessageData
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		
		self.queueNetworkPost(request: request, success:  { data in
			LocalCoreData.shared.performNetworkParsing { context in
				context.pushOpErrorExplanation("Failure saving new Seamail message to Core Data.")
				let response = try Settings.v3Decoder.decode(TwitarrV3FezPostData.self, from: data)
				let threadInContext = context.object(with: seamailThread.objectID) as! SeamailThread
				try SeamailDataManager.shared.ingestSeamailPost(from: response, toThread: threadInContext, inContext: context)
			}
		})
	}
}

@objc(PostOpEventFollow) public class PostOpEventFollow: PostOperation {
	@NSManaged public var event: Event?
	@NSManaged public var newState: Bool

	override public func awakeFromInsert() {
		super.awakeFromInsert()
		operationDescription = newState ? "Follow an Event." : "Unfollow an Event."
	}

	override func post(context: NSManagedObjectContext) {
		guard let event = event else { 
			self.recordServerErrorFailure(ServerError("The Schedule Event we were going to follow has disappeared. Perhaps it was deleted on the server?"))
			return
		}
		confirmPostBeingSent(context: context)
		
		// POST/DELETE /api/v3/events/ID/favorite
		let path = "/api/v3/events/\(event.id)/favorite"
		var request = NetworkGovernor.buildTwittarRequest(withEscapedPath: path, query: nil)
		NetworkGovernor.addUserCredential(to: &request, forUser: author)
		request.httpMethod = newState ? "POST" : "DELETE"
		
		queueNetworkPost(request: request, success:  { data in
			EventsDataManager.shared.setEventFavorite(event, to: self.newState, for: self.author)
		})
	}
}

@objc(PostOpUserComment) public class PostOpUserComment: PostOperation {
	@NSManaged public var comment: String
	@NSManaged public var userCommentedOn: KrakenUser?

	override public func awakeFromInsert() {
		super.awakeFromInsert()
		operationDescription = "Post a private comment about another user."
	}

	override func post(context: NSManagedObjectContext) {
		guard let userCommentedOn = userCommentedOn else { return }
		confirmPostBeingSent(context: context)
		
		// POST /api/v3/user/profile`
		var request = NetworkGovernor.buildTwittarRequest(withEscapedPath: "/api/v3/users/\(userCommentedOn.userID)/note", query: nil)
		NetworkGovernor.addUserCredential(to: &request, forUser: author)
		if comment.isEmpty {
			request.httpMethod = "DELETE"
		}
		else {
			let postContent = TwitarrV3NoteCreateData(note: comment)
			let postData = try! Settings.v3Encoder.encode(postContent)
			request.httpMethod = "POST"
			request.httpBody = postData
			request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		}
		
		queueNetworkPost(request: request, success:  { data in
			if let response = try? Settings.v3Decoder.decode(TwitarrV3NoteData.self, from: data) {
				if let loggedInAuthoor = self.author as? LoggedInKrakenUser {
					loggedInAuthoor.ingestUserComment(from: response)
				}
			}
		})
	}
}

@objc(PostOpUserRelation) public class PostOpUserRelation: PostOperation {
	@NSManaged public var relationType: UserRelationType			// favorite, mute, block
	@NSManaged public var isActive: Bool
	@NSManaged public var targetUser: KrakenUser?

	override public func willSave() {
		super.willSave()
		guard operationDescription == nil else { return }
		operationDescription = isActive ? "Pending: \(relationType) another user." : "Pending: un \(relationType) another user."
	}

	override func post(context: NSManagedObjectContext) {
		guard let currentUser = CurrentUser.shared.loggedInUser, currentUser.userID == author.userID else { return }
		guard let targetUser = targetUser else { return }
		confirmPostBeingSent(context: context)
		
		// POST /api/v3/users/:user_ID/favorite
		var path: String
		switch (relationType, isActive) {
			case (.favorite, true):  path = "/api/v3/users/\(targetUser.userID)/favorite"
			case (.favorite, false): path = "/api/v3/users/\(targetUser.userID)/unfavorite"
			case (.mute, true):  path = "/api/v3/users/\(targetUser.userID)/mute"
			case (.mute, false): path = "/api/v3/users/\(targetUser.userID)/unmute"
			case (.block, true):  path = "/api/v3/users/\(targetUser.userID)/block"
			case (.block, false): path = "/api/v3/users/\(targetUser.userID)/unblock"
		}
		var request = NetworkGovernor.buildTwittarRequest(withEscapedPath: path, query: nil)
		NetworkGovernor.addUserCredential(to: &request, forUser: author)
		request.httpMethod = "POST"
		queueNetworkPost(request: request) { [self] data in
			CurrentUser.shared.updatedUserRelation(type: relationType, actingUser: author, targetUser: targetUser, newState: isActive)
		}		
	}
}

@objc(PostOpUserProfileEdit) public class PostOpUserProfileEdit: PostOperation {
	@NSManaged public var displayName: String?
	@NSManaged public var realName: String?
	@NSManaged public var pronouns: String?
	@NSManaged public var email: String?
	@NSManaged public var homeLocation: String?
	@NSManaged public var roomNumber: String?

	override public func awakeFromInsert() {
		super.awakeFromInsert()
		operationDescription = "Pending update to your user profile"
	}

	override func post(context: NSManagedObjectContext) {
		confirmPostBeingSent(context: context)
		
		let postContent = UserProfileUploadData(header: nil, displayName: displayName, realName: realName, 
				preferredPronoun: pronouns, homeLocation: homeLocation, roomNumber: roomNumber, email: email, message: "", about: "")
		let postData = try! Settings.v3Encoder.encode(postContent)
		
		// POST /api/v3/user/profile`
		var request = NetworkGovernor.buildTwittarRequest(withEscapedPath: "/api/v3/user/profile", query: nil)
		NetworkGovernor.addUserCredential(to: &request, forUser: author)
		request.httpMethod = "POST"
		request.httpBody = postData
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		
		queueNetworkPost(request: request, success:  { data in
			if let response = try? Settings.v3Decoder.decode(TwitarrV3ProfilePublicData.self, from: data) {
				UserManager.shared.updateV3Profile(for: self.author, from: response)
			}
		})
	}
}

@objc(PostOpUserPhoto) public class PostOpUserPhoto: PostOperation {
	@NSManaged @objc dynamic public var image: NSData?
	@NSManaged @objc dynamic public var imageMimetype: String
	
	override public func awakeFromInsert() {
		super.awakeFromInsert()
		operationDescription = "Pending update to your avatar image"
	}

	// /api/v3/user/image
	override func post(context: NSManagedObjectContext) {
		confirmPostBeingSent(context: context)
		
		// POST api/v3/user/image
		var request = NetworkGovernor.buildTwittarRequest(withPath: "/api/v3/user/image", query: nil)
		NetworkGovernor.addUserCredential(to: &request, forUser: author)
		if let imageData = image {
			let uploadData = TwitarrV3ImageUploadData(filename: "userAvatar", image: imageData as Data)
			let postData = try! Settings.v3Encoder.encode(uploadData)
			request.httpBody = postData
			request.httpMethod = "POST"
			request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		}
		else {
			request.httpMethod = "DELETE"
		}
		
		queueNetworkPost(request: request, success: { data in
			if let response = try? Settings.v3Decoder.decode(TwitarrV3UserHeader.self, from: data) {
				UserManager.shared.updateUserHeader(for: self.author, from: response)
			}
		})
	}
}


// MARK: - V3 JSON Structs

struct TwitarrV3PostContentData: Codable {
    /// The new text of the post.
    var text: String
    /// An array of up to 4 images (1 when used in a Fez post). Each image can specify either new image data or an existing image filename. 
	/// For new posts, images will generally contain all new image data. When editing existing posts, images may contain a mix of new and existing images. 
	/// Reorder ImageUploadDatas to change presentation order. Set images to [] to remove images attached to post when editing.
    var images: [TwitarrV3ImageUploadData]
    /// If the poster has moderator privileges and this field is TRUE, this post will be authored by 'moderator' instead of the author.
	/// Set this to FALSE unless the user is a moderator who specifically chooses this option.
	var postAsModerator: Bool = false
    /// If the poster has moderator privileges and this field is TRUE, this post will be authored by 'TwitarrTeam' instead of the author.
	/// Set this to FALSE unless the user is a moderator who specifically chooses this option.
	var postAsTwitarrTeam: Bool = false
}

struct TwitarrV3ImageUploadData: Codable {
    /// The filename of an existing image previously uploaded to the server. Ignored if image is set.
    var filename: String?
    /// The image in `Data` format. 
    var image: Data?
}

struct TwitarrV3ForumCreateData: Codable {
    /// The forum's title.
    var title: String
    /// The first post in the forum. 
	var firstPost: TwitarrV3PostContentData
}

struct TwitarrV3NoteCreateData: Codable {
    /// The text of the note.
    var note: String
}

public struct TwitarrV3FezContentData: Codable {
	/// The `FezType` .label of the fez.
	var fezType: TwitarrV3FezType
	/// The title for the FriendlyFez.
	var title: String
	/// A description of the fez.
	var info: String
	/// The starting time for the fez.
	var startTime: Date?
	/// The ending time for the fez.
	var endTime: Date?
	/// The location for the fez.
	var location: String?
	/// The minimum number of seamonkeys needed for the fez.
	var minCapacity: Int32
	/// The maximum number of seamonkeys for the fez.
	var maxCapacity: Int32
	/// Users to add to the fez upon creation. The creator is always added as the first user.
	var initialUsers: [UUID]
	/// If TRUE, the Fez will be created by user @moderator instead of the current user. Current user must be a mod.
	var createdByModerator: Bool?
	/// If TRUE, the Fez will be created by user @moderator instead of the current user. Current user must be a mod.
	var createdByTwitarrTeam: Bool?
}
struct TwitakrrV3FezContentData: Codable {
    /// The `FezType` .label of the fez.
    var fezType: TwitarrV3FezType
    /// The title for the FriendlyFez.
    var title: String
    /// A description of the fez.
    var info: String
    /// The starting time for the fez.
    var startTime: Date?
    /// The ending time for the fez.
    var endTime: Date?
    /// The location for the fez.
    var location: String?
    /// The minimum number of seamonkeys needed for the fez.
    var minCapacity: Int
    /// The maximum number of seamonkeys for the fez.
    var maxCapacity: Int
    /// Users to add to the fez upon creation. The creator is always added as the first user.
    var initialUsers: [UUID]
}

public struct UserProfileUploadData: Codable {
    /// Basic info about the user--their ID, username, displayname, and avatar image. May be nil on POST.
    var header: TwitarrV3UserHeader?
    /// The displayName, again. Will be equal to header.displayName in results. When POSTing, set this field to update displayName.
    var displayName: String?
    /// An optional real name of the user.
    var realName: String?
    /// An optional preferred form of address.
    var preferredPronoun: String?
    /// An optional home location (e.g. city).
    var homeLocation: String?
    /// An optional ship cabin number.
    var roomNumber: String?
    /// An optional email address.
    var email: String?
     /// An optional short greeting/message to visitors of the profile.
    var message: String?
   /// An optional blurb about the user.
    var about: String?
}
