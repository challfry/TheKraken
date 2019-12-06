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
	let controller: NSFetchedResultsController<PostOperation>
	var viewDelegates: [NSObject & NSFetchedResultsControllerDelegate] = []
	
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

	}
		
	func remove(op: PostOperation) {
		let context = LocalCoreData.shared.networkOperationContext
		context.perform {
			do {
				let opInContext = context.object(with: op.objectID)
				context.delete(opInContext)
				try context.save()
			}
			catch {
				CoreDataLog.error("Couldn't save context when deleting a PostOperation.", ["error" : error])
			}
		}
	}
		
	func checkForOpsToDeliver() {
		
		guard let currentUser = CurrentUser.shared.loggedInUser else { 
			NetworkLog.debug("Not sending ops to server; nobody is logged in.")
			return 
		}
		guard !Settings.shared.blockEmptyingPostOpsQueue else {
			NetworkLog.debug("Not sending ops to server; blocked by user setting")
			return
		}
			
		let context = LocalCoreData.shared.networkOperationContext
		context.perform {
			if let operations = self.controller.fetchedObjects {
				var earliestCallTime: Date?
				for op in operations {
					// Test 1. Only send ops authored by the logged in user.
					if op.author.username != currentUser.username {
						continue
					}	
				
					// Test 2: Don't send ops that aren't ready. Ops that received server errors get their RTS set FALSE.
					if !op.readyToSend {
						continue
					} 
					
					// Test 3: Don't send ops that are currently being sent (have active network calls)
					if op.sentNetworkCall {
						continue
					}
					
					// Test 4: Exponential back off. Don't run an op until its next run date.
					if let nextCallTime = op.nextNetworkCallTime, nextCallTime > Date() {
						if earliestCallTime == nil { 
							earliestCallTime = nextCallTime
						}
						else if let earliest = earliestCallTime, nextCallTime < earliest {
							earliestCallTime = nextCallTime
						}
						continue
					}
					
					// Tell the op to send to server here
					NetworkLog.debug("Sending op to server", ["op" : op])
					op.post()
					op.retryCount += 1
					op.nextNetworkCallTime = Date().addingTimeInterval(TimeInterval(pow(2.0, Double(min(op.retryCount, 5)))))
					
					// Throttling: After we send one op, wait 1 second before trying again
					if let earliest = earliestCallTime {
						earliestCallTime = min(Date().addingTimeInterval(1.0), earliest)
					}
					else {
						earliestCallTime = Date().addingTimeInterval(1.0)
					}
				}
				
				// Start a timer that will fire whenever it's time for us to try sending the next op.
				if let fireTime = earliestCallTime {
					Timer.scheduledTimer(withTimeInterval: fireTime.timeIntervalSinceNow, repeats: false) { timer in 
						self.checkForOpsToDeliver()
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

// The data manager can have multiple delegates, all of which are watching the same results set.
extension PostOperationDataManager : NSFetchedResultsControllerDelegate {

	public func controllerWillChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
		viewDelegates.forEach( { $0.controllerWillChangeContent?(controller) } )
	}

	public func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange anObject: Any,
			at indexPath: IndexPath?, for type: NSFetchedResultsChangeType, newIndexPath: IndexPath?) {
		viewDelegates.forEach( { $0.controller?(controller, didChange: anObject, at: indexPath, for: type, newIndexPath: newIndexPath) } )
	}

    public func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange sectionInfo: NSFetchedResultsSectionInfo, 
    		atSectionIndex sectionIndex: Int, for type: NSFetchedResultsChangeType) {
    	viewDelegates.forEach( { $0.controller?(controller, didChange: sectionInfo, atSectionIndex: sectionIndex, for: type) } )		
	}

	// We can't actually implement this in a multi-delegate model. Also, wth is NSFetchedResultsController doing having a 
	// delegate method that does this?
 //   func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, sectionIndexTitleForSectionName sectionName: String) -> String?
    
	public func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
		pendingOperationCount = controller.fetchedObjects?.count ?? 0
		checkForOpsToDeliver()
		countOpsWithErors()
		viewDelegates.forEach( { $0.controllerDidChangeContent?(controller) } )
	}
	
	func addDelegate(_ newDelegate: NSObject & NSFetchedResultsControllerDelegate) {
		if !viewDelegates.contains(where: { $0 === newDelegate } ) {
			viewDelegates.insert(newDelegate, at: 0)
		}
	}
	
	func removeDelegate(_ oldDelegate: NSObject & NSFetchedResultsControllerDelegate) {
		viewDelegates.removeAll(where: { $0 === oldDelegate } )
	}
}


/* 'Post' in this context is any REST call that changes server state, where you need to be logged in.
	Usually delivered via HTTP POST.
*/
@objc(PostOperation) public class PostOperation: KrakenManagedObject {
		// A descriptive string explaing what this op is going to do. Not saved to CD.
		// Subclasses should set this value.
	@objc dynamic var operationDescription: String?

		// A descriptive string explaining what state the op is in. Not saved to CD, deduced from other fields.
		// Subclasses should set this value.
	@objc dynamic var operationStatus: String?
	
		// TRUE if this post can be delivered to the server
	@NSManaged public var readyToSend: Bool
	
		// TRUE if we've sent this op to the server. Can no longer cancel.
		// Note: We don't actually care about this value getting stored; but we do want it propagated to all MOCs.
	@NSManaged public var sentNetworkCall: Bool
	
		// Since you must be logged in to send any content to the server, including likes/reactions,
		// every postop has an author.
	@NSManaged public var author: KrakenUser
	
		// This is the time the post was 'committed' locally. If we're offline at post time, it may not
		// post until much later. Even if we're online, the server makes its own timestamp when it receives the post.
	@NSManaged public var originalPostTime: Date
	
		// If we attempt to send a post to the server and it fails, save the error here
		// so we can display it to the user later.
	@NSManaged public var errorString: String?
		
	// For a poor-man's exponential backoff algorithm. 2s, 4s, 8s, 16s 32s.
	public var nextNetworkCallTime: Date?
	public var retryCount = 0
	
		// TODO: We'll need a policy for attempting to send content that fails. We can:
			// - Resend X times, then delete?
			// - Allow user to resend manually from the list of deferred posts in Settings
			// - Tell the user immediately, then go to an editor screen?


// MARK: Methods
	
	// AwakeFromInsert is called when a new PostOp is initialized. NOT called when it's fetched or faulted.
	// Since we call it from within the context.perform() where the object gets built, we can set up some boilerplate here.
	override public func awakeFromInsert() {
		super.awakeFromInsert()
		if let moc = managedObjectContext, let currentUser = CurrentUser.shared.getLoggedInUser(in: moc) {
			author = currentUser
		}
		originalPostTime = Date()
		readyToSend = false
		sentNetworkCall = false
	}
	
	// AwakeFromFetch is called every time we fetch or fault this object. 
	// This is where we set up non-@NSManaged properties.
	override public func awakeFromFetch() {
		super.awakeFromFetch()
		
		// Set the op status
		if errorString != nil {
			operationStatus = "Received error from server. Blocked until error is resolved."
		}
		else if sentNetworkCall {
			operationStatus = "Posting to server"
		}
		else if nextNetworkCallTime != nil {
			operationStatus = "Couldn't reach server; will try again soon."
		}
		else if !readyToSend {
			operationStatus = "Not ready to send to the server yet."
		}
		else {
			operationStatus = "Waiting to send"
		}
	}
	
	// Subclasses override this to send this post to the server. Subclass should call super iff the post can be
	// sent; this fn marks the post as being sent in Core Data.
	func post() {
		let context = LocalCoreData.shared.networkOperationContext
		context.perform {
			do {
				let opInContext = context.object(with: self.objectID) as! PostOperation
				opInContext.sentNetworkCall = true
				try context.save()

				let opInMainContext = LocalCoreData.shared.mainThreadContext.object(with: self.objectID) as! PostOperation
				opInMainContext.operationStatus = "Posting to server"
			}
			catch {
				// Not an error that needs to be saved into the op
				CoreDataLog.error("A postOp got a CoreData error; couldn't store state change back into op.", 
						["Error" : error])
			}
		}
	}
	
	// Subclasses can call this to get their URLRequest sent to the server. Handles some of the common
	// error-handling and bookeeping functions.
	fileprivate func queueNetworkPost(request: URLRequest, success: @escaping (Data) -> Void) {
		NetworkGovernor.shared.queue(request) { (package: NetworkResponse) in
			if let err = NetworkGovernor.shared.parseServerError(package) {
				self.recordServerErrorFailure(err)
			}
			else if let data = package.data {
				// The assumption here is that if we get a non-error response from the server, the call worked and 
				// the server has enacted the change we posted. So, even if we fail to decode and process the response
				// or save to Core Data, the call still succeeded.
				PostOperationDataManager.shared.remove(op: self)
				success(data)
				return
			}
			
			// Network error or server error
			let context = LocalCoreData.shared.networkOperationContext
			context.perform {
				do {
					let opInContext = context.object(with: self.objectID) as! PostOperation
					opInContext.sentNetworkCall = false
					try context.save()
				}
				catch {
					// Not an error that needs to be saved into the op
					CoreDataLog.error("A postOp got a server error, which we couldn't store back in the postOp.", 
							["Error" : error])
				}
			}
		}
	}
	
	func uploadPhoto(photoData: NSData, mimeType: String, isUserPhoto: Bool, done: @escaping (String?, ServerError?) -> Void) {
		let filename = "photo.jpg"
		let path = isUserPhoto ? "/api/v2/user/photo" : "/api/v2/photo"
		var request = NetworkGovernor.buildTwittarV2Request(withPath: path, query: nil)
		NetworkGovernor.addUserCredential(to: &request)
		request.httpMethod = "POST"
		
		// Choose a multipart boundary that isn't contained in the picture data
		// This bit of code brings up questions of the Halting Problem; in the real world if count hits 3
		// I'd be amazed.
		let baseBoundary = "2Yt08jU534c0pgc0p4Jq0M"
		var boundary = baseBoundary
		var count = 0
		while (photoData as Data).range(of: boundary.data(using: .utf8)!) != nil {
			boundary = baseBoundary + "\(count)"
			count += 1
		}
		
		// rfc1521, plus a bit of rfc1867.
		request.setValue("multipart/form-data; boundary=\"\(boundary)\"", forHTTPHeaderField: "Content-Type")
		var httpBodyString = "--\(boundary)\r\n"
		httpBodyString.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n")
		httpBodyString.append("Content-Type: \(mimeType)\r\n\r\n")
		let httpTrailerString = "\r\n--\(boundary)--\r\n"
		var httpBodyData = httpBodyString.data(using: .utf8)!
		httpBodyData.append(photoData as Data)
		httpBodyData.append(httpTrailerString.data(using: .utf8)!)
		request.httpBody = httpBodyData

		NetworkGovernor.shared.queue(request) { (package: NetworkResponse) in
			var photoID: String?
			var serverError: ServerError?
			if let err = NetworkGovernor.shared.parseServerError(package) {
				serverError = err
			}
			else if let data = package.data {
				let decoder = JSONDecoder()
				do {
					if isUserPhoto {
						let _ = try decoder.decode(TwitarrV2UpdateUserPhotoResponse.self, from: data)
					}
					else {
						let response = try decoder.decode(TwitarrV2PostPhotoResponse.self, from: data)
						photoID = response.photo.id
					}
				} catch 
				{
					serverError = ServerError("Failure parsing image upload response: \(error)")
					NetworkLog.error("Failure parsing image upload response.", ["Error" : error, "URL" : request.url as Any])
				} 
			} 
			done(photoID, serverError)
		}
	}
	
	// Server Error means we got a HTTP response from the server indicating an error condition. Generally
	// for postOps this means we need to record the error in Core Data and mark the op as not ready until the 
	// user looks at it (often, they have to edit their post somehow). This is different from network errors,
	// where we can just keep resubmitting the op with no changes (but with exponential backoff--I'm not a monster).
	func recordServerErrorFailure(_ serverError: ServerError) {
		let context = LocalCoreData.shared.networkOperationContext
		
		context.perform {
			do {
				let opInContext = context.object(with: self.objectID) as! PostOperation
				opInContext.errorString = serverError.getErrorString()
				opInContext.sentNetworkCall = false
				opInContext.readyToSend = false
				try context.save()
			}
			catch {
				CoreDataLog.error("A postOp got a server error, which we couldn't store back in the postOp.", 
						["Error" : error, "ServerError" : serverError])
			}
		}
	}
}

// MARK: - PostOp Types

@objc(PostOpTweet) public class PostOpTweet: PostOperation {
	@NSManaged public var text: String
	
		// Photo needs to be uploaded as a separate POST, then the id is sent.
	@NSManaged @objc dynamic public var image: NSData?
	@NSManaged @objc dynamic public var imageMimetype: String?
	
		// Parent tweet, if this is a response. Can be nil.
	@NSManaged public var parent: TwitarrPost?
	
		// If non-nil, this op edits the given tweet.
	@NSManaged public var tweetToEdit: TwitarrPost?
			
	override public func awakeFromFetch() {
		super.awakeFromFetch()
		operationDescription = "Posting a new Twitarr tweet."
	}

	override func post() {
		super.post()
		
		let twittarrPostBlock = { (photoID: String?) in
		
			// Test code
//			let err = ServerError("Text can\'t be blank.")
//			self.recordServerErrorFailure(err)
//			return
			
			// Build the request and the body JSON
			var request: URLRequest
			if let editingPost = self.tweetToEdit {
				// POST /api/v2/tweet/:id
				request = NetworkGovernor.buildTwittarV2Request(withPath: "/api/v2/tweet/\(editingPost.id)", query: nil)
				let editPostStruct = TwitarrV2EditTweetRequest(text: self.text, photo: photoID)
				let editPostData = try! JSONEncoder().encode(editPostStruct)
				request.httpBody = editPostData
			}
			else {
				// POST /api/v2/stream
				request = NetworkGovernor.buildTwittarV2Request(withPath: "/api/v2/stream", query: nil)				
				let newPostStruct = TwitarrV2NewTweetRequest(text: self.text, photo: photoID, parent: self.parent?.id, 
						as_mod: nil, as_admin: nil)
				let newPostData = try! JSONEncoder().encode(newPostStruct)
				request.httpBody = newPostData
			}
			
			request.setValue("application/json", forHTTPHeaderField: "Content-Type")
			NetworkGovernor.addUserCredential(to: &request)
			request.httpMethod = "POST"
			
			self.queueNetworkPost(request: request) { data in
				let decoder = JSONDecoder()
				do {
					let response = try decoder.decode(TwitarrV2NewTweetResponse.self, from: data)
					TwitarrDataManager.shared.addNewPostToStream(post: response.stream_post)
				} catch 
				{
					self.recordServerErrorFailure(ServerError("Failure parsing response to new Twitarr post request."))
					NetworkLog.error("Failure parsing response to new Twitarr post request.", 
							["Error" : error, "URL" : request.url as Any])
				} 
			}

		}
		
		// If we have a photo to upload, do that first, then chain the tweet post.
		if let image = image, let mimetype = imageMimetype {
			uploadPhoto(photoData: image, mimeType: mimetype, isUserPhoto: false) { photoID, error in
				if let err = error {
					self.recordServerErrorFailure(err)
				}
				else {
					twittarrPostBlock(photoID)
				}
			}
		}
		else {
			twittarrPostBlock(nil)
		}

	}
}

@objc(PostOpTweetReaction) public class PostOpTweetReaction: PostOperation {
	@NSManaged public var reactionWord: String
		
		// Parent tweet, if this is a response. Can be nil.
	@NSManaged public var sourcePost: TwitarrPost?
	
		// True to add this reaction to this post, false to delete it.
	@NSManaged public var isAdd: Bool
	
	override public func awakeFromFetch() {
		super.awakeFromFetch()
		operationDescription = "Posting a reaction to a Twitarr tweet."
	}

	override func post() {
		guard let post = sourcePost else { 
			self.recordServerErrorFailure(ServerError("The post has disappeared. Perhaps it was deleted serverside?"))
			return
		}
		super.post()
		
		// POST/DELETE /api/v2/tweet/:id/react/:type
		var request = NetworkGovernor.buildTwittarV2Request(withPath: 
				"/api/v2/tweet/\(post.id)/react/\(reactionWord)", query: nil)
		NetworkGovernor.addUserCredential(to: &request)
		request.httpMethod = isAdd ? "POST" : "DELETE"
		
		self.queueNetworkPost(request: request) { data in
			LocalCoreData.shared.performNetworkParsing { context in
				context.pushOpErrorExplanation("Failure saving change to tweet reaction.")
				
				let response = try JSONDecoder().decode(TwitarrV2TweetReactionResponse.self, from: data)
				let postInContext = try context.existingObject(with: post.objectID) as! TwitarrPost
				postInContext.buildReactionsFromV2(context: context, v2Object: response.reactions)
			}
		}
	}
}

@objc(PostOpTweetDelete) public class PostOpTweetDelete: PostOperation {
	@NSManaged public var tweetToDelete: TwitarrPost?

	override public func awakeFromFetch() {
		super.awakeFromFetch()
		operationDescription = "Deleting a Twitarr tweet."
	}

	override func post() {
		guard let post = tweetToDelete else { 
			self.recordServerErrorFailure(ServerError("The post has disappeared. Perhaps it was deleted serverside?"))
			return
		}
		super.post()
		
		// DELETE /api/v2/tweet/:id
		var request = NetworkGovernor.buildTwittarV2Request(withPath: "/api/v2/tweet/\(post.id)", query: nil)
		NetworkGovernor.addUserCredential(to: &request)
		request.httpMethod = "DELETE"
		
		self.queueNetworkPost(request: request) { data in
			LocalCoreData.shared.performNetworkParsing { context in
				context.pushOpErrorExplanation("Failure saving tweet deletion back to Core Data.")
				let postInContext = try context.existingObject(with: post.objectID) as! TwitarrPost
				context.delete(postInContext)
			}
		}
	}
}

@objc(PostOpSeamailThread) public class PostOpSeamailThread: PostOperation {
	@NSManaged public var subject: String
	@NSManaged public var text: String
	@NSManaged public var recipients: Set<PotentialUser>?

	override public func awakeFromFetch() {
		super.awakeFromFetch()
		operationDescription = "Creating a new Seamail thread."
	}

	override func post() {
		super.post()
		
		// POST /api/v2/seamail
		var request = NetworkGovernor.buildTwittarV2Request(withPath: "/api/v2/seamail", query: nil)
		NetworkGovernor.addUserCredential(to: &request)
		request.httpMethod = "POST"
		let usernames = recipients?.map { $0.username } ?? []
		let newThreadStruct = TwitarrV2NewSeamailThreadRequest(users: usernames, subject: subject, text: text)
		let newThreadData = try! JSONEncoder().encode(newThreadStruct)
		request.httpBody = newThreadData
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		
		self.queueNetworkPost(request: request) { data in
			LocalCoreData.shared.performNetworkParsing { context in
				context.pushOpErrorExplanation("Failure saving new Seamail thread to Core Data.")
				let response = try JSONDecoder().decode(TwitarrV2NewSeamailThreadResponse.self, from: data)
				SeamailDataManager.shared.loadNetworkSeamails(from: [response.seamail])
			}
		}
	}
}

@objc(PostOpSeamailMessage) public class PostOpSeamailMessage: PostOperation {
	@NSManaged public var thread: SeamailThread?
	@NSManaged public var text: String

	override public func awakeFromFetch() {
		super.awakeFromFetch()
		operationDescription = "Post a new Seamail message."
	}

	override func post() {
		guard let seamailThread = thread else { 
			self.recordServerErrorFailure(ServerError("The Seamail thread has disappeared. Perhaps it was deleted on the server?"))
			return
		}
		super.post()
		
		// POST /api/v2/seamail/:id
		var request = NetworkGovernor.buildTwittarV2Request(withPath: "/api/v2/seamail/\(seamailThread.id)", query: nil)
		NetworkGovernor.addUserCredential(to: &request)
		request.httpMethod = "POST"
		let newMessageStruct = TwitarrV2NewSeamailMessageRequest(text: text)
		let newMessageData = try! JSONEncoder().encode(newMessageStruct)
		request.httpBody = newMessageData
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		
		self.queueNetworkPost(request: request) { data in
			LocalCoreData.shared.performNetworkParsing { context in
				context.pushOpErrorExplanation("Failure saving new Seamail message to Core Data.")
				let response = try JSONDecoder().decode(TwitarrV2NewSeamailMessageResponse.self, from: data)
				SeamailDataManager.shared.addNewSeamailMessage(context: context, 
						threadID: seamailThread.id, v2Object: response.seamail_message)
			}
		}
	}
}

@objc(PostOpEventFollow) public class PostOpEventFollow: PostOperation {
	@NSManaged public var event: Event?
	@NSManaged public var newState: Bool

	override public func awakeFromFetch() {
		super.awakeFromFetch()
		operationDescription = newState ? "Follow an Event." : "Unfollow an Event."
	}

	override func post() {
		guard let event = event else { 
			self.recordServerErrorFailure(ServerError("The Schedule Event we were going to follow has disappeared. Perhaps it was deleted on the server?"))
			return
		}
		guard CurrentUser.shared.loggedInUser?.username == author.username else { return }
		super.post()
		
		// POST or DELETE /api/v2/event/:id/favorite
		var request = NetworkGovernor.buildTwittarV2Request(withPath: "/api/v2/event/\(event.id)/favorite", query: nil)
		NetworkGovernor.addUserCredential(to: &request)
		request.httpMethod =  newState ? "POST" : "DELETE"		
		queueNetworkPost(request: request) { data in
			LocalCoreData.shared.performNetworkParsing { context in
				context.pushOpErrorExplanation("Failure saving new Schedule Event to Core Data. Was setting follow state on event.")
				let response = try JSONDecoder().decode(TwitarrV2EventFavoriteResponse.self, from: data)
				EventsDataManager.shared.parseEvents([response.event], isFullList: false)
			}
		}
	}
}

@objc(PostOpUserComment) public class PostOpUserComment: PostOperation {
	@NSManaged public var comment: String
	@NSManaged public var userCommentedOn: KrakenUser?

	override public func awakeFromFetch() {
		super.awakeFromFetch()
		operationDescription = "Post a private comment about another user."
	}

	override func post() {
		guard let currentUser = CurrentUser.shared.loggedInUser, currentUser.username == author.username else { return }
		guard let userCommentedOn = userCommentedOn else { return }
		super.post()

		let userCommentStruct = TwitarrV2ChangeUserCommentRequest(comment: comment)
		let encoder = JSONEncoder()
		let requestData = try! encoder.encode(userCommentStruct)
				
		// POST /api/v2/user/profile/:user/personal_comment
		var request = NetworkGovernor.buildTwittarV2Request(withPath:"/api/v2/user/profile/\(userCommentedOn.username)/personal_comment", query: nil)
		NetworkGovernor.addUserCredential(to: &request)
		request.httpMethod = "POST"
		request.httpBody = requestData
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		queueNetworkPost(request: request) { data in
			LocalCoreData.shared.performNetworkParsing { context in
				context.pushOpErrorExplanation("Failure saving User Comment change to Core Data. (the PostOp succeeded, but we couldn't save the change).")
				let decoder = JSONDecoder()
				let response = try decoder.decode(TwitarrV2ChangeUserCommentResponse.self, from: data)
				if response.status == "ok" {
					UserManager.shared.updateProfile(for: userCommentedOn.objectID, from: response.user)
				}
			}
		}
	}
}

@objc(PostOpUserFavorite) public class PostOpUserFavorite: PostOperation {
	@NSManaged public var isFavorite: Bool
	@NSManaged public var userBeingFavorited: KrakenUser?

	override public func awakeFromFetch() {
		super.awakeFromFetch()
		operationDescription = isFavorite ? "Pending: favorite another user." : "Pending: unfavorite another user."
	}

	override func post() {
		guard let currentUser = CurrentUser.shared.loggedInUser, currentUser.username == author.username else { return }
		guard let userFavorited = userBeingFavorited else { return }
		super.post()
				
		// POST /api/v2/user/profile/:username/star
		var request = NetworkGovernor.buildTwittarV2Request(withPath:"/api/v2/user/profile/\(userFavorited.username)/star", query: nil)
		NetworkGovernor.addUserCredential(to: &request)
		request.httpMethod = "POST"
		queueNetworkPost(request: request) { data in
			LocalCoreData.shared.performNetworkParsing { context in
				context.pushOpErrorExplanation("Failure saving User Favorite change to Core Data. (the network call succeeded, but we couldn't save the change).")
				let decoder = JSONDecoder()
				let response = try decoder.decode(TwitarrV2ToggleUserStarResponse.self, from: data)
				if response.status == "ok" {
					currentUser.updateUserStar(context: context, targetUser: userFavorited, newState: response.starred)
				}
			}
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

	override public func awakeFromFetch() {
		super.awakeFromFetch()
		operationDescription = "Pending update to your user profile"
	}

	override func post() {
		guard let currentUser = CurrentUser.shared.loggedInUser, currentUser.username == author.username else { return }
		super.post()
		
		let profileUpdateStruct = TwitarrV2UpdateProfileRequest(displayName: displayName, email: email, 
				homeLocation: homeLocation, pronouns: pronouns, realName: realName, roomNumber: roomNumber)
		let encoder = JSONEncoder()
		let requestData = try! encoder.encode(profileUpdateStruct)

		var request = NetworkGovernor.buildTwittarV2Request(withPath:"/api/v2/user/profile", query: nil)
		NetworkGovernor.addUserCredential(to: &request)
		request.httpMethod = "POST"
		request.httpBody = requestData
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		queueNetworkPost(request: request) { data in
			do {
				let decoder = JSONDecoder()
				let response = try decoder.decode(TwitarrV2UpdateProfileResponse.self, from: data)
				
				if response.status == "ok" {
					UserManager.shared.updateLoggedInUserInfo(from: response.user)
				}
			}
			catch {
				CoreDataLog.error("Failure parsing User Profile Edit response. (the network call succeeded, but we couldn't save the change locally).", 
						["Error" : error])
			}
		}
	}
}

@objc(PostOpUserPhoto) public class PostOpUserPhoto: PostOperation {
	@NSManaged @objc dynamic public var image: NSData?
	@NSManaged @objc dynamic public var imageMimetype: String
	
	override public func awakeFromFetch() {
		super.awakeFromFetch()
		operationDescription = "Pending update to your avatar image"
	}

	override func post() {
		super.post()

//		self.recordServerErrorFailure(ServerError("This is a test error, for testing."))
		
		if let opImage = image {
			uploadPhoto(photoData: opImage, mimeType: imageMimetype, isUserPhoto: true) { photoID, error in
				if let err = error {
					self.recordServerErrorFailure(err)
				}
				else {
					self.author.invalidateUserPhoto(nil)
					PostOperationDataManager.shared.remove(op: self)
				}
			}
		}
		else {
			// We're deleting the image
			var request = NetworkGovernor.buildTwittarV2Request(withPath:"/api/v2/user/photo", query: nil)
			NetworkGovernor.addUserCredential(to: &request)
			request.httpMethod = "DELETE"
			queueNetworkPost(request: request) { data in
				do {
					let decoder = JSONDecoder()
					let _ = try decoder.decode(TwitarrV2UpdateUserPhotoResponse.self, from: data)
					
					self.author.invalidateUserPhoto(nil)
				}
				catch {
					CoreDataLog.error("Failure saving User Photo change to Core Data. (the op succeeded, but we couldn't save the change).", 
							["Error" : error])
				}
			}
		}
	}
	
}


// MARK: - V2 JSON Structs

// POST /api/v2/stream, POST /api/v2/tweet/:id
struct TwitarrV2NewTweetRequest: Codable {
	let text: String
	let photo: String?
	let parent: String?
	let as_mod: Bool?
	let as_admin: Bool?
}
struct TwitarrV2EditTweetRequest: Codable {
	let text: String?
	let photo: String?
}
struct TwitarrV2NewTweetResponse: Codable {		// Both new and edits use this response
	let status: String
	let stream_post: TwitarrV2Post
}

// POST /api/v2/tweet/:id/react/:type -- request has no body
struct TwitarrV2TweetReactionResponse: Codable {
	let status: String
	let reactions: TwitarrV2ReactionsSummary
}

// POST /api/v2/seamail
struct TwitarrV2NewSeamailThreadRequest: Codable {
	let users: [String]
	let subject: String
	let text: String
}
struct TwitarrV2NewSeamailThreadResponse: Codable {
	let status: String
	let seamail: TwitarrV2SeamailThread
}

// POST /api/v2/seamail/:id
struct TwitarrV2NewSeamailMessageRequest: Codable {
	let text: String
}
struct TwitarrV2NewSeamailMessageResponse: Codable {
	let status: String
	let seamail_message: TwitarrV2SeamailMessage
}	

struct TwitarrV2PostPhotoResponse: Codable {
	let status: String
	let photo: TwitarrV2PhotoMeta
}

struct TwitarrV2PhotoMeta: Codable {
	let id: String
	let animated: Bool
	let store_filename: String
	let md5_hash: String
	let content_type: String
	let uploader: String
	let upload_time: Int64
	let sizes: [String: String]
}

// POST or DELETE /api/v2/event/:id/favorite
struct TwitarrV2EventFavoriteResponse: Codable {
	let status: String
	let event: TwitarrV2Event
}

// POST /api/v2/user/profile/:username/personal_comment
struct TwitarrV2ChangeUserCommentRequest: Codable {
	let comment: String
}

struct TwitarrV2ChangeUserCommentResponse: Codable {
	let status: String
	let user: TwitarrV2UserProfile
}

// POST /api/v2/user/profile/:username/star 
struct TwitarrV2ToggleUserStarResponse: Codable {
	let status: String
	let starred: Bool
}

// POST /api/v2/user/profile
struct TwitarrV2UpdateProfileRequest: Codable {
	let displayName: String?
	let email: String?
	let homeLocation: String?
	let pronouns: String?
	let realName: String?
	let roomNumber: String?
	
	enum CodingKeys: String, CodingKey {
		case displayName = "display_name"
		case email = "email"
		case homeLocation = "home_location"
		case pronouns = "pronouns"
		case realName = "real_name"
		case roomNumber = "room_number"
	}
}

struct TwitarrV2UpdateProfileResponse: Codable {
	let status: String
	let user: TwitarrV2UserAccount
}

struct TwitarrV2UpdateUserPhotoResponse: Codable {
	let status: String
	let md5Hash: String

	enum CodingKeys: String, CodingKey {
		case status = "status"
		case md5Hash = "md5_hash"
	}
}
