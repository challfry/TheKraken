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
				}
			}
			
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
}

@objc(PostOpTweet) public class PostOpTweet: PostOperation {
	@NSManaged public var text: String
	
		// Photo needs to be uploaded as a separate POST, then the id is sent.
	@NSManaged @objc dynamic public var image: NSData?
	
		// Parent tweet, if this is a response. Can be nil.
	@NSManaged public var parent: TwitarrPost?
	
		// If non-nil, this op edits the given tweet.
	@NSManaged public var tweetToEdit: TwitarrPost?
}

@objc(PostOpTweetReaction) public class PostOpTweetReaction: PostOperation {
	@NSManaged public var reactionWord: String
		
		// Parent tweet, if this is a response. Can be nil.
	@NSManaged public var sourcePost: TwitarrPost?
	
		// True to add this reaction to this post, false to delete it.
	@NSManaged public var isAdd: Bool
}

@objc(PostOpTweetDelete) public class PostOpTweetDelete: PostOperation {
	@NSManaged public var tweetToDelete: TwitarrPost?
}

@objc(PostOpSeamailThread) public class PostOpSeamailThread: PostOperation {
	@NSManaged public var subject: String?
	@NSManaged public var text: String?
	@NSManaged public var recipient: Set<PotentialUser>?
}


