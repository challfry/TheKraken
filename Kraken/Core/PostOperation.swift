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
	
	override init() {
		let context = LocalCoreData.shared.mainThreadContext
		let fetchRequest = NSFetchRequest<PostOperation>(entityName: "PostOperation")
		fetchRequest.sortDescriptors = [NSSortDescriptor(key: "originalPostTime", ascending: true)]
		controller = NSFetchedResultsController(fetchRequest: fetchRequest, managedObjectContext: context, 
				sectionNameKeyPath: nil, cacheName: nil)
		super.init()
		controller.delegate = self

		do {
			try controller.performFetch()
			controllerDidChangeContent(controller as! NSFetchedResultsController<NSFetchRequestResult>)
		} catch {
			CoreDataLog.error("Failed to fetch PostOperations", ["error" : error])
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
		if Settings.shared.blockEmptyingPostOpsQueue {
			NetworkLog.debug("Not sending ops to server; blocked by user setting")
			return
		}
		
		// TODO: Need to throttle here; otherwise we try to send every op each time an op is mutated.
	
		if let operations = controller.fetchedObjects {
			for op in operations {
				if op.readyToSend && !op.sentNetworkCall {
					// Tell the op to send to server here
					NetworkLog.debug("Sending op to server", ["op" : op])
					op.post()
				}
			}
		}
	}
	
	func countOpsWithErors() {
		var opsWithErrors = 0
		if let operations = controller.fetchedObjects {
			for op in operations {
				if op.errorString != nil {
					opsWithErrors += 1
				}
			}
		}
		operationsWithErrorsCount = opsWithErrors
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
		// UniqueID we create per op. Not sent to server.
//	@NSManaged public var id: String
	
		// TRUE if this post can be delivered to the server
	@NSManaged public var readyToSend: Bool
	
		// TRUE if we've sent this op to the server. Can no longer cancel.
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
	
		// TODO: We'll need a policy for attempting to send content that fails. We can:
			// - Resend X times, then delete?
			// - Allow user to resend manually from the list of deferred posts in Settings
			// - Tell the user immediately, then go to an editor screen?
	
	override public func awakeFromInsert() {
		super.awakeFromInsert()
		if let moc = managedObjectContext, let currentUser = CurrentUser.shared.getLoggedInUser(in: moc) {
			author = currentUser
		}
		originalPostTime = Date()
		readyToSend = false
		sentNetworkCall = false
	}
	
	// Sends this post to the server.
	func post() {
		// set sentNetworkCall
	}
	
	func queueNetworkPost(request: URLRequest, success: @escaping (Data) -> Void) {
		NetworkGovernor.shared.queue(request) { (data: Data?, response: URLResponse?) in
			if let err = NetworkGovernor.shared.parseServerError(data: data, response: response) {
				self.recordServerErrorFailure(err)
			}
			else if let data = data {
				PostOperationDataManager.shared.remove(op: self)
				success(data)
			}
		}
	}
	
	func uploadPhoto(photoData: NSData, mimeType: String, done: @escaping (String?, ServerError?) -> Void) {
		let filename = "photo.jpg"
		var request = NetworkGovernor.buildTwittarV2Request(withPath: "/api/v2/photo", query: nil)
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

		NetworkGovernor.shared.queue(request) { (data: Data?, response: URLResponse?) in
			var photoID: String?
			var serverError: ServerError?
			if let err = NetworkGovernor.shared.parseServerError(data: data, response: response) {
				serverError = err
			}
			else if let data = data {
				let decoder = JSONDecoder()
				do {
					let response = try decoder.decode(TwitarrV2PostPhotoResponse.self, from: data)
					photoID = response.photo.id
				} catch 
				{
					serverError = ServerError("Failure parsing image upload response: \(error)")
					NetworkLog.error("Failure parsing image upload response.", ["Error" : error, "URL" : request.url as Any])
				} 
			} 
			done(photoID, serverError)
		}
	}
	
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

@objc(PostOpTweet) public class PostOpTweet: PostOperation {
	@NSManaged public var text: String
	
		// Photo needs to be uploaded as a separate POST, then the id is sent.
	@NSManaged @objc dynamic public var image: NSData?
	@NSManaged @objc dynamic public var imageMimetype: String?
	
		// Parent tweet, if this is a response. Can be nil.
	@NSManaged public var parent: TwitarrPost?
	
		// If non-nil, this op edits the given tweet.
	@NSManaged public var tweetToEdit: TwitarrPost?
	
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
			uploadPhoto(photoData: image, mimeType: mimetype) { photoID, error in
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
			let context = LocalCoreData.shared.networkOperationContext
			context.perform {
				do {
					let response = try JSONDecoder().decode(TwitarrV2TweetReactionResponse.self, from: data)
					let postInContext = try context.existingObject(with: post.objectID) as! TwitarrPost
					postInContext.buildReactionsFromV2(context: context, v2Object: response.reactions)
					try context.save()
				}
				catch {
					CoreDataLog.error("Failure saving change to tweet reaction.", ["Error" : error])
				}
			}
		}
	}
}

@objc(PostOpTweetDelete) public class PostOpTweetDelete: PostOperation {
	@NSManaged public var tweetToDelete: TwitarrPost?

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
			let context = LocalCoreData.shared.networkOperationContext
			context.perform {
				do {
					let postInContext = try context.existingObject(with: post.objectID) as! TwitarrPost
					context.delete(postInContext)
					try context.save()
				}
				catch {
					CoreDataLog.error("Failure saving tweet deletion back to Core Data.", ["Error" : error])
				}
			}
		}
	}
}

@objc(PostOpSeamailThread) public class PostOpSeamailThread: PostOperation {
	@NSManaged public var subject: String
	@NSManaged public var text: String
	@NSManaged public var recipients: Set<PotentialUser>?

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
			do {
				let response = try JSONDecoder().decode(TwitarrV2NewSeamailThreadResponse.self, from: data)
				SeamailDataManager.shared.addNewSeamails(from: [response.seamail])
			}
			catch {
				CoreDataLog.error("Failure saving new Seamail thread to Core Data.", ["Error" : error])
			}
		}
	}
}

@objc(PostOpSeamailMessage) public class PostOpSeamailMessage: PostOperation {
	@NSManaged public var thread: SeamailThread?
	@NSManaged public var text: String

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
			let context = LocalCoreData.shared.networkOperationContext
			context.perform {
				do {
					let response = try JSONDecoder().decode(TwitarrV2NewSeamailMessageResponse.self, from: data)
					SeamailDataManager.shared.addNewSeamailMessage(context: context, 
							threadID: seamailThread.id, v2Object: response.seamail_message)
				}
				catch {
					CoreDataLog.error("Failure saving new Seamail thread to Core Data.", ["Error" : error])
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
