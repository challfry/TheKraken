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

struct PhotoUploadPackage {
	var iamgeData: Data
	var mimetype: String
}

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
	
	func post(context: NSManagedObjectContext) {
		if Settings.apiV3 {
			postV3(context: context)
		}
		else {
			postV2(context: context)
		}
	}
	
	func postV2(context: NSManagedObjectContext) {
		operationState = .serverError
		errorString = "Kraken hasn't implemented this operation yet."
	}
	func postV3(context: NSManagedObjectContext) {
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
				if let err = NetworkGovernor.shared.parseServerError(package) {
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
	
	func uploadPhoto(photoData: NSData, mimeType: String, isUserPhoto: Bool, done: @escaping (String?, ServerError?) -> Void) {
		let filename = "photo.jpg"
		let path = isUserPhoto ? "/api/v2/user/photo" : "/api/v2/photo"
		var request = NetworkGovernor.buildTwittarRequest(withPath: path, query: nil)
		NetworkGovernor.addUserCredential(to: &request, forUser: author)
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
	
		// Photo needs to be uploaded as a separate POST, then the id is sent.
	@NSManaged @objc dynamic public var image: NSData?
	@NSManaged @objc dynamic public var imageMimetype: String?
	
		// Parent tweet, if this is a response. Can be nil.
	@NSManaged public var parent: TwitarrPost?
	
		// If non-nil, this op edits the given tweet.
	@NSManaged public var tweetToEdit: TwitarrPost?
	
		// If editing a post, TRUE will delete existing image. FALSE and no image data will keep the existing image unchanged.
		// False and new image data will replace.
	@NSManaged public var deleteExistingImage: Bool
			
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

	override func postV3(context: NSManagedObjectContext) {
		confirmPostBeingSent(context: context)
		
		var httpContentData: Data
		var path: String
		if let editingPost = self.tweetToEdit {
			path = "/api/v3/twitarr/\(editingPost.id)/update"
			var newImageFilename: String? = nil
			var uploadData: TwitarrV3ImageUploadData? = nil
			if deleteExistingImage == false {
				if let imageData = image {
					uploadData = TwitarrV3ImageUploadData(filename: "1", image: (imageData as Data))
					newImageFilename = "1"
				}
				else {
					newImageFilename = editingPost.image		// "" also works
				}				
			}
			let editingPostStruct = TwitarrV3PostContentData(text: text, imageFilename: newImageFilename, newImage: uploadData)
			httpContentData = try! JSONEncoder().encode(editingPostStruct)
		}
		else {
			// POST /api/v3/twitarr/create
			path = "/api/v3/twitarr/create"
			if let replyTo = parent {
				path = "/api/v3/twitarr/\(replyTo.id)/reply"
			}
			
			let newPostStruct = TwitarrV3PostCreateData(text: self.text, imageData: (image as Data?))
			httpContentData = try! JSONEncoder().encode(newPostStruct)
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

	override func postV2(context: NSManagedObjectContext) {
		confirmPostBeingSent(context: context)
		
		let twittarrPostBlock = { (photoID: String?) in
			
			// Build the request and the body JSON
			var request: URLRequest
			if let editingPost = self.tweetToEdit {
				// POST /api/v2/tweet/:id
				request = NetworkGovernor.buildTwittarRequest(withPath: "/api/v2/tweet/\(editingPost.id)", query: nil)
				let editPostStruct = TwitarrV2EditTweetRequest(text: self.text, photo: photoID)
				let editPostData = try! JSONEncoder().encode(editPostStruct)
				request.httpBody = editPostData
			}
			else {
				// POST /api/v2/stream
				request = NetworkGovernor.buildTwittarRequest(withPath: "/api/v2/stream", query: nil)				
				let newPostStruct = TwitarrV2NewTweetRequest(text: self.text, photo: photoID, parent: self.parent?.id, 
						as_mod: nil, as_admin: nil)
				let newPostData = try! JSONEncoder().encode(newPostStruct)
				request.httpBody = newPostData
			}
			
			request.setValue("application/json", forHTTPHeaderField: "Content-Type")
			NetworkGovernor.addUserCredential(to: &request, forUser: self.author)
			request.httpMethod = "POST"
			
			self.queueNetworkPost(request: request, success: { data in
				let decoder = JSONDecoder()
				do {
					let response = try decoder.decode(TwitarrV2NewTweetResponse.self, from: data)
					TwitarrDataManager.shared.ingestNewUserPost(post: response.stream_post)
				} catch 
				{
					self.recordServerErrorFailure(ServerError("Failure parsing response to new Twitarr post request."))
					NetworkLog.error("Failure parsing response to new Twitarr post request.", 
							["Error" : error, "URL" : request.url as Any])
				} 
			})

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
	
	override public func awakeFromInsert() {
		super.awakeFromInsert()
		operationDescription = "Posting a reaction to a Twitarr tweet."
	}

	override func postV3(context: NSManagedObjectContext) {
		guard let post = sourcePost else { 
			self.recordServerErrorFailure(ServerError("The post has disappeared. Perhaps it was deleted serverside?"))
			return
		}
		confirmPostBeingSent(context: context)
		
		// POST/DELETE /api/v3/twitarr/ID/<like|laugh|love>
		let encodedReationWord = reactionWord.addingPathComponentPercentEncoding() ?? "like"
		var request = NetworkGovernor.buildTwittarRequest(withEscapedPath: 
				"/api/v3/twitarr/\(post.id)/\(encodedReationWord)", query: nil)
		NetworkGovernor.addUserCredential(to: &request, forUser: author)
		request.httpMethod = isAdd ? "POST" : "DELETE"
		
		self.queueNetworkPost(request: request, success:  { data in
			if let response = try? Settings.v3Decoder.decode(TwitarrV3TwarrtData.self, from: data) {
				TwitarrDataManager.shared.ingestNewUserPost(post: response)
			}
		})
	}

	override func postV2(context: NSManagedObjectContext) {
		guard let post = sourcePost else { 
			self.recordServerErrorFailure(ServerError("The post has disappeared. Perhaps it was deleted serverside?"))
			return
		}
		confirmPostBeingSent(context: context)
		
		// POST/DELETE /api/v2/tweet/:id/react/:type
		let encodedReationWord = reactionWord.addingPathComponentPercentEncoding() ?? ""
		var request = NetworkGovernor.buildTwittarRequest(withEscapedPath: 
				"/api/v2/tweet/\(post.id)/react/\(encodedReationWord)", query: nil)
		NetworkGovernor.addUserCredential(to: &request, forUser: author)
		request.httpMethod = isAdd ? "POST" : "DELETE"
		
		self.queueNetworkPost(request: request, success:  { data in
			LocalCoreData.shared.performNetworkParsing { context in
				context.pushOpErrorExplanation("Failure saving change to tweet reaction.")
				
				let response = try JSONDecoder().decode(TwitarrV2TweetReactionResponse.self, from: data)
				let postInContext = try context.existingObject(with: post.objectID) as! TwitarrPost
				postInContext.buildReactionsFromV2(context: context, v2Object: response.reactions)
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

	override func postV3(context: NSManagedObjectContext) {
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

	override func postV2(context: NSManagedObjectContext) {
		guard let post = tweetToDelete else { 
			self.recordServerErrorFailure(ServerError("The post has disappeared. Perhaps it was deleted serverside?"))
			return
		}
		confirmPostBeingSent(context: context)
		
		// DELETE /api/v2/tweet/:id
		var request = NetworkGovernor.buildTwittarRequest(withPath: "/api/v2/tweet/\(post.id)", query: nil)
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
	
	@NSManaged public var photos: NSOrderedSet?			// PostOpForum_Photo. Always matches new state.
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

	override func postV3(context: NSManagedObjectContext) {
		
		var path: String
		var content: Data
		var isNewThread = false
		if let editPost = editPost {
			// If it's an edit, takes a TwitarrV3PostContentData, returns a TwitarrV3PostData
			path = "/api/v3/forum/post/\(editPost.id)/update"
			let newText = text ?? editPost.text
			var imageData: TwitarrV3ImageUploadData? = nil
			var filename = (editPost.photos.firstObject as? PhotoDetails)?.id
			if let photo = photos?.firstObject as? PostOpForum_Photo {
				filename = UUID().uuidString
				imageData = TwitarrV3ImageUploadData(filename: filename!, image: photo.image)
			}
			let postData = TwitarrV3PostContentData(text: newText, imageFilename: filename, newImage: imageData)
			content = try! JSONEncoder().encode(postData)
		}
		else if let existingThread = thread {
			guard let text = text else {
				recordServerErrorFailure(ServerError("Forum posts must contain non-empty text."))
				return
			}
			// If it's a new post in an existing thread, takes a TwitarrV3PostCreateData, returns a TwitarrV3PostData
			path = "/api/v3/forum/\(existingThread.id)/create"
			var imageData: Data? = nil
			if let photo = photos?.firstObject as? PostOpForum_Photo {
				imageData = photo.image
			}
			let postData = TwitarrV3PostCreateData(text: text, imageData: imageData)
			content = try! JSONEncoder().encode(postData)
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
			var imageData: Data? = nil
			if let photo = photos?.firstObject as? PostOpForum_Photo {
				imageData = photo.image
			}
			let postData = TwitarrV3ForumCreateData(title: subject, text: text, image: imageData)
			content = try! JSONEncoder().encode(postData)
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
	
	override func postV2(context: NSManagedObjectContext) {
		guard let postText = text else { return }
		guard subject != nil || thread != nil else { return }
		confirmPostBeingSent(context: context)

		// Upload any photos first, then chain the post call.
		// Declared as a placeholder closure, then redefined immediately as it references itself.
		var postingBlock: ([String]) -> Void = { _ in return }
		postingBlock = { (inputPhotoIDs: [String]) in
			var photoIDs: [String] = inputPhotoIDs
			if let photoSet = self.photos, photoSet.count > photoIDs.count {
				let photoUpload = photoSet[photoIDs.count] as! PostOpForum_Photo
				self.uploadPhoto(photoData: photoUpload.image as NSData, mimeType: photoUpload.mimetype, 
						isUserPhoto: false) { photoID, error in
					if let err = error {
						self.recordServerErrorFailure(err)
					}
					else if let id = photoID {
						photoIDs.append(id)
						postingBlock(photoIDs)
					}
				}
			
				// If we're uploading a photo we can't send the forum post yet. The photo completion handler
				// will chain this block again.
				return
			}

			// POST /api/v2/forums							For new thread, or
			// POST /api/v2/forums/:thread_id				For new post in existing thread, or 
			// POST /api/v2/vorums/:thread_id/:post_id		To edit existing post.
			var path = "/api/v2/forums"
			var isNewThread = true
			if let editingPost = self.editPost {
				// Request/Response contents for post edits are almost exactly the same as new posts, except
				// there's no as_admin or as_mod fields. Luckily, we don't use them.
				path.append("/\(editingPost.thread.id)/\(editingPost.id)")
				isNewThread = false
			}
			else if let parentThread = self.thread {
				// If thread is set, this is a post in an existing thread.
				path.append("/\(parentThread.id)")
				isNewThread = false
			}
			var request = NetworkGovernor.buildTwittarRequest(withPath: path, query: nil)
			NetworkGovernor.addUserCredential(to: &request, forUser: self.author)
			request.httpMethod = "POST"
			
			let postRequestStruct = TwitarrV2ForumNewPostRequest(subject: self.subject, text: postText,
					photos: photoIDs, as_mod: nil, as_admin: nil)
			
			let newThreadData = try! JSONEncoder().encode(postRequestStruct)
			request.httpBody = newThreadData
			request.setValue("application/json", forHTTPHeaderField: "Content-Type")

// rcf removing until more V3 code is built
//			self.queueNetworkPost(request: request, success: { data in
//				LocalCoreData.shared.performNetworkParsing { context in 
//					if isNewThread {
//						context.pushOpErrorExplanation("Failure saving result of call creating a new Forum Thread.")
//						let response = try JSONDecoder().decode(TwitarrV2ForumNewThreadResponse.self, from: data)
//						try ForumPostDataManager.shared.internalParseNewThreadPosts(context: context, from: response.forum_thread)
//					}
//					else {
//						context.pushOpErrorExplanation("Failure saving result of call creating a new Forum Post.")
//						let response = try JSONDecoder().decode(TwitarrV2ForumNewPostResponse.self, from: data)
//						
//						// Only build CD objects out of the response if this is an edit. For new posts, we don't know
//						// whether there were intervening posts betwen the last post we know about and this new post.
//						// Therefore, don't show the new post until we do a normal load on the thread.
//						if let editingPost = self.editPost, editingPost.id == response.forum_post.id {
//							editingPost.buildFromV2(context: context, v2Object: response.forum_post, thread: editingPost.thread)
//						}
//					}
//				}
//			})
		}
		
		// Call the posting block to start things off. This block uploads photos until they're all uploaded, then
		// does the forum POST, passing in the ids of any photos uploaded.
		postingBlock([])
		
	}
}

// Photo data attached to a forum post. 
@objc(PostOpForum_Photo) public class PostOpForum_Photo: KrakenManagedObject {
	@NSManaged public var image: Data
	@NSManaged public var mimetype: String
	@NSManaged public var parentOp: PostOpForumPost
	@NSManaged public var filename: String?				// Only set if image came from server.
	
	func setupFromPackage(_ from: PhotoUploadPackage) {
		image = from.iamgeData
		mimetype = from.mimetype
	}
}

@objc(PostOpForumPostDelete) public class PostOpForumPostDelete: PostOperation {
	@NSManaged public var postToDelete: ForumPost?

	override public func awakeFromInsert() {
		super.awakeFromInsert()
		operationDescription = "Deleting a Forum Post."
	}

	override func postV3(context: NSManagedObjectContext) {
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
	
	override func postV2(context: NSManagedObjectContext) {
		guard let post = postToDelete else { 
			self.recordServerErrorFailure(ServerError("The post has disappeared. Perhaps it was deleted serverside?"))
			return
		}
		confirmPostBeingSent(context: context)
		
		// DELETE  /api/v2/forums/:id/:post_id
		var request = NetworkGovernor.buildTwittarRequest(withPath: "/api/v2/forums/\(post.thread.id)/\(post.id)", query: nil)
		NetworkGovernor.addUserCredential(to: &request, forUser: author)
		request.httpMethod = "DELETE"
		
		self.queueNetworkPost(request: request, success:  { data in
			LocalCoreData.shared.performNetworkParsing { context in
				context.pushOpErrorExplanation("Failure saving forum post deletion back to Core Data.")
				if let postInContext = try context.existingObject(with: post.objectID) as? ForumPost {
					let threadInContext = postInContext.thread
					if threadInContext.posts.count == 1 {
						// If this thread only has one post and we're deleting it, also delete the thread, as this
						// is what the server does. HOWEVER, the server might get another poster in the thread
						// that we don't know about, in which case the server DOESN'T delete the thread--plus,
						// it doesn't tell us whether it deleted it or not.
						// So, we try to do what the server does, and if the thread wasn't deleted it'll get re-added
						// upon refresh.
						context.delete(threadInContext)
					}
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
	
		// True to add this reaction to this post, false to delete it.
	@NSManaged public var isAdd: Bool
	
	override public func awakeFromInsert() {
		super.awakeFromInsert()
		operationDescription = "Posting a reaction to a Forums post."
	}

	override func postV3(context: NSManagedObjectContext) {
		guard let post = sourcePost else { 
			self.recordServerErrorFailure(ServerError("The post has disappeared. Perhaps it was deleted serverside?"))
			return
		}
		confirmPostBeingSent(context: context)
		
		// POST/DELETE /api/v3/forum/post/ID/laugh
		var request = NetworkGovernor.buildTwittarRequest(withEscapedPath: 
				"/api/v3/forum/post/\(post.id)/\(reactionWord)", query: nil)
		NetworkGovernor.addUserCredential(to: &request, forUser: author)
		request.httpMethod = isAdd ? "POST" : "DELETE"
		
		self.queueNetworkPost(request: request, success:  { data in
			LocalCoreData.shared.performNetworkParsing { context in
				context.pushOpErrorExplanation("Failure saving change to Forum Post reaction.")
				
				let response = try Settings.v3Decoder.decode(TwitarrV3PostData.self, from: data)
				ForumPostDataManager.shared.parsePostData(inThread: post.thread, from: response)
			}
		})
	}
	
	override func postV2(context: NSManagedObjectContext) {
		guard let post = sourcePost else { 
			self.recordServerErrorFailure(ServerError("The post has disappeared. Perhaps it was deleted serverside?"))
			return
		}
		confirmPostBeingSent(context: context)
		
		// POST/DELETE /api/v2/forums/:id/:post_id/react/:type
		let encodedReationWord = reactionWord.addingPathComponentPercentEncoding() ?? ""
		var request = NetworkGovernor.buildTwittarRequest(withEscapedPath: 
				"/api/v2/forums/\(post.thread.id)/\(post.id)/react/\(encodedReationWord)", query: nil)
		NetworkGovernor.addUserCredential(to: &request, forUser: author)
		request.httpMethod = isAdd ? "POST" : "DELETE"
		
		self.queueNetworkPost(request: request, success:  { data in
			LocalCoreData.shared.performNetworkParsing { context in
				context.pushOpErrorExplanation("Failure saving change to Forum Post reaction.")
				
				let response = try JSONDecoder().decode(TwitarrV2ForumPostReactionResponse.self, from: data)
				let postInContext = try context.existingObject(with: post.objectID) as! ForumPost
				postInContext.buildReactionsFromV2(context: context, v2Object: response.reactions)
			}
		})
	}
}


@objc(PostOpSeamailThread) public class PostOpSeamailThread: PostOperation {
	@NSManaged public var subject: String
	@NSManaged public var text: String
	@NSManaged public var recipients: Set<PotentialUser>?

	override public func awakeFromInsert() {
		super.awakeFromInsert()
		operationDescription = "Creating a new Seamail thread."
	}

	override func postV2(context: NSManagedObjectContext) {
		confirmPostBeingSent(context: context)
		
		// POST /api/v2/seamail
		var request = NetworkGovernor.buildTwittarRequest(withPath: "/api/v2/seamail", query: nil)
		NetworkGovernor.addUserCredential(to: &request, forUser: author)
		request.httpMethod = "POST"
		let usernames = recipients?.map { $0.username } ?? []
		let newThreadStruct = TwitarrV2NewSeamailThreadRequest(users: usernames, subject: subject, text: text)
		let newThreadData = try! JSONEncoder().encode(newThreadStruct)
		request.httpBody = newThreadData
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		
		self.queueNetworkPost(request: request, success:  { data in
			LocalCoreData.shared.performNetworkParsing { context in
				context.pushOpErrorExplanation("Failure saving new Seamail thread to Core Data.")
				let response = try JSONDecoder().decode(TwitarrV2NewSeamailThreadResponse.self, from: data)
				SeamailDataManager.shared.ingestSeamailThreads(from: [response.seamail])
			}
		})
	}
}

@objc(PostOpSeamailMessage) public class PostOpSeamailMessage: PostOperation {
	@NSManaged public var thread: SeamailThread?
	@NSManaged public var text: String

	override public func awakeFromInsert() {
		super.awakeFromInsert()
		operationDescription = "Post a new Seamail message."
	}

	override func postV2(context: NSManagedObjectContext) {
		guard let seamailThread = thread else { 
			self.recordServerErrorFailure(ServerError("The Seamail thread has disappeared. Perhaps it was deleted on the server?"))
			return
		}
		confirmPostBeingSent(context: context)
		
		// POST /api/v2/seamail/:id
		var request = NetworkGovernor.buildTwittarRequest(withPath: "/api/v2/seamail/\(seamailThread.id)", query: nil)
		NetworkGovernor.addUserCredential(to: &request, forUser: author)
		request.httpMethod = "POST"
		let newMessageStruct = TwitarrV2NewSeamailMessageRequest(text: text)
		let newMessageData = try! JSONEncoder().encode(newMessageStruct)
		request.httpBody = newMessageData
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		
		self.queueNetworkPost(request: request, success:  { data in
			LocalCoreData.shared.performNetworkParsing { context in
				context.pushOpErrorExplanation("Failure saving new Seamail message to Core Data.")
				let response = try JSONDecoder().decode(TwitarrV2NewSeamailMessageResponse.self, from: data)
				SeamailDataManager.shared.addNewSeamailMessage(context: context, 
						threadID: seamailThread.id, v2Object: response.seamail_message)
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

	override func postV3(context: NSManagedObjectContext) {
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

	override func postV2(context: NSManagedObjectContext) {
		guard let event = event else { 
			self.recordServerErrorFailure(ServerError("The Schedule Event we were going to follow has disappeared. Perhaps it was deleted on the server?"))
			return
		}
		guard CurrentUser.shared.getLoggedInUser(in: context)?.username == author.username else { return }
		confirmPostBeingSent(context: context)
		
		// POST or DELETE /api/v2/event/:id/favorite
		var request = NetworkGovernor.buildTwittarRequest(withPath: "/api/v2/event/\(event.id)/favorite", query: nil)
		NetworkGovernor.addUserCredential(to: &request, forUser: author)
		request.httpMethod =  newState ? "POST" : "DELETE"		
		queueNetworkPost(request: request, success:  { data in
			LocalCoreData.shared.performNetworkParsing { context in
				context.pushOpErrorExplanation("Failure saving new Schedule Event to Core Data. Was setting follow state on event.")
				let response = try JSONDecoder().decode(TwitarrV2EventFavoriteResponse.self, from: data)
				EventsDataManager.shared.parseV2Events([response.event], isFullList: false)
			}
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

	override func postV3(context: NSManagedObjectContext) {
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
			let postData = try! JSONEncoder().encode(postContent)
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

	override func postV2(context: NSManagedObjectContext) {
		guard let currentUser = CurrentUser.shared.getLoggedInUser(in: context), currentUser.username == author.username else { return }
		guard let userCommentedOn = userCommentedOn else { return }
		confirmPostBeingSent(context: context)

		let userCommentStruct = TwitarrV2ChangeUserCommentRequest(comment: comment)
		let encoder = JSONEncoder()
		let requestData = try! encoder.encode(userCommentStruct)
				
		// POST /api/v2/user/profile/:user/personal_comment
		let encodedUsername = userCommentedOn.username.addingPathComponentPercentEncoding() ?? ""
		var request = NetworkGovernor.buildTwittarRequest(withEscapedPath:"/api/v2/user/profile/\(encodedUsername)/personal_comment", 
				query: nil)
		NetworkGovernor.addUserCredential(to: &request, forUser: author)
		request.httpMethod = "POST"
		request.httpBody = requestData
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		queueNetworkPost(request: request, success:  { data in
			LocalCoreData.shared.performNetworkParsing { context in
				context.pushOpErrorExplanation("Failure saving User Comment change to Core Data. (the PostOp succeeded, but we couldn't save the change).")
				let decoder = JSONDecoder()
				let response = try decoder.decode(TwitarrV2ChangeUserCommentResponse.self, from: data)
				if response.status == "ok" {
					UserManager.shared.updateProfile(for: userCommentedOn.objectID, from: response.user)
				}
			}
		})
	}
}

@objc(PostOpUserFavorite) public class PostOpUserFavorite: PostOperation {
	@NSManaged public var isFavorite: Bool
	@NSManaged public var userBeingFavorited: KrakenUser?

	override public func willSave() {
		super.willSave()
		guard operationDescription == nil else { return }
		operationDescription = isFavorite ? "Pending: favorite another user." : "Pending: unfavorite another user."
	}

	override func postV2(context: NSManagedObjectContext) {
		guard let currentUser = CurrentUser.shared.loggedInUser, currentUser.username == author.username else { return }
		guard let userFavorited = userBeingFavorited else { return }
		confirmPostBeingSent(context: context)
				
		// POST /api/v2/user/profile/:username/star
		let encodedUsername = userFavorited.username.addingPathComponentPercentEncoding() ?? ""
		var request = NetworkGovernor.buildTwittarRequest(withEscapedPath:"/api/v2/user/profile/\(encodedUsername)/star", query: nil)
		NetworkGovernor.addUserCredential(to: &request, forUser: author)
		request.httpMethod = "POST"
		queueNetworkPost(request: request, success:  { data in
			LocalCoreData.shared.performNetworkParsing { context in
				context.pushOpErrorExplanation("Failure saving User Favorite change to Core Data. (the network call succeeded, but we couldn't save the change).")
				let decoder = JSONDecoder()
				let response = try decoder.decode(TwitarrV2ToggleUserStarResponse.self, from: data)
				if response.status == "ok", let currentUserInContext = context.object(with: self.author.objectID) as? LoggedInKrakenUser {
					currentUserInContext.updateUserStar(context: context, targetUser: userFavorited, newState: response.starred)
				}
			}
		})
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

	override func postV3(context: NSManagedObjectContext) {
		confirmPostBeingSent(context: context)
		
		let postContent = TwitarrV3UserProfileData(username: author.username, about: "", displayName: displayName, 
				email: email, homeLocation: homeLocation, message: "", preferredPronoun: pronouns, 
				realName: realName, roomNumber: roomNumber, limitAccess: false)
		let postData = try! JSONEncoder().encode(postContent)
		
		// POST /api/v3/user/profile`
		var request = NetworkGovernor.buildTwittarRequest(withEscapedPath: "/api/v3/user/profile", query: nil)
		NetworkGovernor.addUserCredential(to: &request, forUser: author)
		request.httpMethod = "POST"
		request.httpBody = postData
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		
		queueNetworkPost(request: request, success:  { data in
			if let response = try? Settings.v3Decoder.decode(TwitarrV3UserProfileData.self, from: data) {
				UserManager.shared.updateV3Profile(for: self.author, from: response)
			}
		})
	}

	override func postV2(context: NSManagedObjectContext) {
		guard let currentUser = CurrentUser.shared.getLoggedInUser(in: context), 
				currentUser.username == author.username else { return }
		confirmPostBeingSent(context: context)
		
		let profileUpdateStruct = TwitarrV2UpdateProfileRequest(displayName: displayName, email: email, 
				homeLocation: homeLocation, pronouns: pronouns, realName: realName, roomNumber: roomNumber)
		let encoder = JSONEncoder()
		let requestData = try! encoder.encode(profileUpdateStruct)

		var request = NetworkGovernor.buildTwittarRequest(withPath:"/api/v2/user/profile", query: nil)
		NetworkGovernor.addUserCredential(to: &request, forUser: author)
		request.httpMethod = "POST"
		request.httpBody = requestData
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		queueNetworkPost(request: request, success: { data in
			do {
				let decoder = JSONDecoder()
				let response = try decoder.decode(TwitarrV2UpdateProfileResponse.self, from: data)
				
				if response.status == "ok" {
					UserManager.shared.updateLoggedInUserInfo(from: response.user)
				}
				CurrentUser.shared.lastError = nil
			}
			catch {
				CoreDataLog.error("Failure parsing User Profile Edit response. (the network call succeeded, but we couldn't save the change locally).", 
						["Error" : error])
			}
		}, failure: { error in
			CurrentUser.shared.lastError = error
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
	override func postV3(context: NSManagedObjectContext) {
		confirmPostBeingSent(context: context)
		
		// POST api/v3/user/image
		var request = NetworkGovernor.buildTwittarRequest(withEscapedPath: "api/v3/user/image", query: nil)
		NetworkGovernor.addUserCredential(to: &request, forUser: author)
		if let imageData = image {
			let uploadData = TwitarrV3ImageUploadData(filename: "userAvatar", image: imageData as Data)
			let postData = try! JSONEncoder().encode(uploadData)
			request.httpBody = postData
			request.httpMethod = "POST"
			request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		}
		else {
			request.httpMethod = "DELETE"
		}
		
		queueNetworkPost(request: request, success: { data in
			var newFilename: String?
			if let response = try? Settings.v3Decoder.decode(TwitarrV3UploadedImageData.self, from: data) {
				newFilename = response.filename
			}
			UserManager.shared.updateUserImageInfo(user: self.author, newFilename: newFilename)
		})
	}

	override func postV2(context: NSManagedObjectContext) {
		confirmPostBeingSent(context: context)

//		self.recordServerErrorFailure(ServerError("This is a test error, for testing."))
		
		if let opImage = image {
			uploadPhoto(photoData: opImage, mimeType: imageMimetype, isUserPhoto: true) { photoID, error in
				if let err = error {
					self.recordServerErrorFailure(err)
				}
				else {
					self.author.invalidateUserPhoto(context)
					PostOperationDataManager.shared.remove(op: self)
				}
			}
		}
		else {
			// We're deleting the image
			var request = NetworkGovernor.buildTwittarRequest(withPath:"/api/v2/user/photo", query: nil)
			NetworkGovernor.addUserCredential(to: &request, forUser: author)
			request.httpMethod = "DELETE"
			queueNetworkPost(request: request, success:  { data in
				do {
					let decoder = JSONDecoder()
					let _ = try decoder.decode(TwitarrV2UpdateUserPhotoResponse.self, from: data)
					
					self.author.invalidateUserPhoto(nil)
				}
				catch {
					CoreDataLog.error("Failure saving User Photo change to Core Data. (the op succeeded, but we couldn't save the change).", 
							["Error" : error])
				}
			})
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

// POST /api/v2/forums, or POST /api/v2/forums/:id
struct TwitarrV2ForumNewPostRequest: Codable {
	let subject: String?								// Only if this is a new thread.
	let text: String
	let photos: [String]?
	let as_mod: Bool?
	let as_admin: Bool?
}

struct TwitarrV2ForumNewThreadResponse: Codable {
	let status: String
	let forum_thread: TwitarrV2ForumThread
}

struct TwitarrV2ForumNewPostResponse: Codable {
	let status: String
	let forum_post: TwitarrV2ForumPost
}


// POST /api/v2/forums/:id/:post_id/react/:type -- request has no body
struct TwitarrV2ForumPostReactionResponse: Codable {
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

// MARK: - V3 JSON Structs

struct TwitarrV3PostCreateData: Codable {
    /// The text of the forum post or twarrt.
    var text: String
    /// An optional image in Data format.
    var imageData: Data?
}

struct TwitarrV3PostContentData: Codable {
    /// The new text of the forum post.
    var text: String
    /// The filename of an existing image. Ignored if newImage is set. Set to "" to delete image. Be sure to set this field to 
    /// match the existing image filename if not changing.
    var imageFilename: String?
    /// A new image to replace the existing image.
    var newImage: TwitarrV3ImageUploadData?
}

struct TwitarrV3ImageUploadData: Codable {
    /// The name of the image file.
    var filename: String
    /// The image in `Data` format.
    var image: Data
}

struct TwitarrV3ForumCreateData: Codable {
    /// The forum's title.
    var title: String
    /// The text content of the forum post.
    var text: String
    /// The image content of the forum post.
    var image: Data?
}

struct TwitarrV3UploadedImageData: Codable {
    /// The generated name of the uploaded image.
    var filename: String
}

struct TwitarrV3NoteCreateData: Codable {
    /// The text of the note.
    var note: String
}
