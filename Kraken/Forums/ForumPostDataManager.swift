//
//  ForumPostDataManager.swift
//  Kraken
//
//  Created by Chall Fry on 2/3/21.
//  Copyright © 2021 Chall Fry. All rights reserved.
//

import UIKit
import CoreData

@objc(ForumPost) public class ForumPost: KrakenManagedObject {
    @NSManaged public var id: Int64
    @NSManaged public var text: String
    @NSManaged public var createTime: Date
    @NSManaged public var isPinned: Bool    
    @NSManaged public var reactionCount: Int64		// How many users like this post. 0 if unknown. This will be unknown for most posts.
    
    @NSManaged public var author: KrakenUser
    @NSManaged public var thread: ForumThread
    @NSManaged public var photos: NSMutableOrderedSet	// PhotoDetails
    @NSManaged public var reactions: Set<Reaction>

    @NSManaged public var reactionOps: NSMutableSet?
	@NSManaged public var opDeleting: PostOpForumPostDelete?
	@NSManaged public var opEditing: PostOpForumPost?
  
	// Properties built from reactions
	@NSManaged public var reactionDict: NSDictionary?			// the reactions set, keyed by reaction.word
	@objc dynamic public var likeCount: Int32 = 0
	@objc dynamic public var loveCount: Int32 = 0
	@objc dynamic public var laughCount: Int32 = 0

// MARK: Methods

	override public func awakeFromInsert() {
		// createdAt = Date()
		setPrimitiveValue(Date(), forKey: "createTime")
	}

	public override func awakeFromFetch() {
		super.awakeFromFetch()

		// Update derived properties
		laughCount = reactionDict?["laugh"] as? Int32 ?? 0
		likeCount = reactionDict?["like"] as? Int32 ?? 0
		loveCount = reactionDict?["love"] as? Int32 ?? 0
	}

	// Requires: Users, Photos for post.
	func buildFromV3(context: NSManagedObjectContext, v3Object: TwitarrV3PostData, thread: ForumThread) {
		TestAndUpdate(\.id, v3Object.postID)
		TestAndUpdate(\.text, v3Object.text)
		TestAndUpdate(\.isPinned, v3Object.isPinned == true)
		TestAndUpdate(\.createTime, v3Object.createdAt)
		TestAndUpdate(\.reactionCount, v3Object.likeCount)			// All like types
		TestAndUpdate(\.thread, thread)
		
		// Set the author
		if author.username != v3Object.author.username {
			let userPool: [UUID : KrakenUser ] = context.userInfo.object(forKey: "Users") as! [UUID : KrakenUser] 
			if let cdAuthor = userPool[v3Object.author.userID] {
				author = cdAuthor
			}
		}
		
		// Intent is to update photos in a way where we don't modify photos until we're sure it's changing.
		if let newImageFilenames = v3Object.images {
			let photoDict: [String : PhotoDetails] = context.userInfo.object(forKey: "PhotoDetails") as! [String : PhotoDetails] 
			for (index, image) in newImageFilenames.enumerated() {
				if photos.count <= index, let photoToAdd = photoDict[image] {
					photos.add(photoToAdd)
				} 
				if (photos[index] as? PhotoDetails)?.id != image, let photoToAdd = photoDict[image] {
					photos.replaceObject(at:index, with: photoToAdd)
				}
			}
			if photos.count > newImageFilenames.count {
				photos.removeObjects(in: NSRange(location: newImageFilenames.count, length: photos.count - newImageFilenames.count))
			}
		} 
		else {
			if photos.count > 0 {
				photos.removeAllObjects()
			}
		}
		
		buildUserReactionFromV3(context: context, userLike: v3Object.userLike, bookmark: v3Object.isBookmarked)
					
		let hashtags = StringUtilities.extractHashtags(v3Object.text)
		HashtagDataManager.shared.addHashtags(hashtags)
	}

	func buildFromV3DetailData(context: NSManagedObjectContext, v3Object: TwitarrV3PostDetailData) {
		TestAndUpdate(\.id, Int64(v3Object.postID))
		TestAndUpdate(\.text, v3Object.text)
		TestAndUpdate(\.createTime, v3Object.createdAt)
//		TestAndUpdate(\.thread, thread)

		// Set the author
		if author.username != v3Object.author.username {
			let userPool: [UUID : KrakenUser ] = context.userInfo.object(forKey: "Users") as! [UUID : KrakenUser] 
			if let cdAuthor = userPool[v3Object.author.userID] {
				author = cdAuthor
			}
		}
		
		// Intent is to update photos in a way where we don't modify photos until we're sure it's changing.
		if let newImageFilenames = v3Object.images {
			let photoDict: [String : PhotoDetails] = context.userInfo.object(forKey: "PhotoDetails") as! [String : PhotoDetails] 
			for (index, image) in newImageFilenames.enumerated() {
				if photos.count <= index, let photoToAdd = photoDict[image] {
					photos.add(photoToAdd)
				} 
				if (photos[index] as? PhotoDetails)?.id != image, let photoToAdd = photoDict[image] {
					photos.replaceObject(at:index, with: photoToAdd)
				}
			}
			if photos.count > newImageFilenames.count {
				photos.removeObjects(in: NSRange(location: newImageFilenames.count, length: photos.count - newImageFilenames.count))
			}
		} 
		else {
			if photos.count > 0 {
				photos.removeAllObjects()
			}
		}
		
		// Set the user's reaction and bookmarking.
		buildUserReactionFromV3(context: context, userLike: v3Object.userLike, bookmark: v3Object.isBookmarked)

		// Set reaction counts. The PostDetailData object gives us a list of each user that's reacted, but we aren't using that.
		let dict: NSDictionary = ["laugh" : v3Object.laughs.count, 
				"like" : v3Object.likes.count, 
				"love" : v3Object.loves.count]
		TestAndUpdate(\.reactionDict, dict)
	}
	
	func buildUserReactionFromV3(context: NSManagedObjectContext, userLike: TwitarrV3LikeType?, bookmark: Bool) {
		// Set the user's reaction to the post
		if let currentUser = CurrentUser.shared.getLoggedInUser(in: context) {
			let foundReaction = reactions.first { $0.user?.userID == currentUser.userID } 
			if foundReaction == nil && userLike == nil && !bookmark {
				// If there's no user like or bookmark, we don't need to create a reaction object
				return
			}
			let reaction = foundReaction ?? Reaction(context: context)
			reaction.buildReactionFromLikeAndBookmark(context: context, source: self, likeType: userLike, bookmark: bookmark)
		}
	}

	// Always returns nil if nobody's logged in.
	func getPendingUserReaction() -> PostOpForumPostReaction? {
		if let username = CurrentUser.shared.loggedInUser?.username, let reaction = reactionOps?.first(where: { reaction in
				guard let r = reaction as? PostOpForumPostReaction else { return false }
				return r.author.username == username }) {
			return reaction as? PostOpForumPostReaction
		}
		return nil
	}
	
	func setReaction(_ reactionWord: LikeOpKind) {
		LocalCoreData.shared.performLocalCoreDataChange { context, currentUser in
			guard let thisPost = context.object(with: self.objectID) as? ForumPost else { return }
			
			// Check for existing op for this user, with this word
			let op = thisPost.getPendingUserReaction() ?? PostOpForumPostReaction(context: context)
			op.operationState = .readyToSend
			op.reactionWord = reactionWord.string()
			op.sourcePost = thisPost
		}
	}

	func cancelReactionOp() {
		guard let existingOp = getPendingUserReaction() else { return }
		PostOperationDataManager.shared.remove(op: existingOp)
	}
	
	// Creates a postOp that will delete this post.
	func addDeletePostOp() {
		LocalCoreData.shared.performLocalCoreDataChange { context, currentUser in
			guard let thisPost = context.object(with: self.objectID) as? ForumPost else { return }

			// Until we add support for admin deletes
			guard currentUser.username == thisPost.author.username else { 
				CoreDataLog.debug("Kraken can't do admin deletes of forum posts. You can only delete your own post.")
				return
			}

			// Check for existing op for this post
			let existingOp = thisPost.opDeleting ?? PostOpForumPostDelete(context: context)
			existingOp.postToDelete = thisPost
			existingOp.operationState = .readyToSend
		}
	}
	
	func cancelDeleteOp() {
		guard let currentUsername = CurrentUser.shared.loggedInUser?.username else { return }
		if let deleteOp = opDeleting, deleteOp.author.username == currentUsername {
			PostOperationDataManager.shared.remove(op: deleteOp)
		}
	}
	
	func cancelEditOp() {
		guard let currentUsername = CurrentUser.shared.loggedInUser?.username else { return }
		if let editOp = opEditing, editOp.author.username == currentUsername {
			PostOperationDataManager.shared.remove(op: editOp)
		}
	}
}

class ReactionDictTransformer: ValueTransformer {
    public static func register() {
        ValueTransformer.setValueTransformer(ReactionDictTransformer(), 
        		forName: NSValueTransformerName(rawValue: String(describing: ReactionDictTransformer.self)))
    }
    
	override public class func transformedValueClass() -> AnyClass {
		return NSDictionary.self
	}

	override public class func allowsReverseTransformation() -> Bool {
		return true
	}
	
	override public func transformedValue(_ value: Any?) -> Any? {
		guard let dict = value as? NSDictionary, let data = try? NSKeyedArchiver.archivedData(withRootObject: dict, requiringSecureCoding: true) else { 
			return nil 
		}
		return data
    }
    
    override public func reverseTransformedValue(_ value: Any?) -> Any? {
        guard let data = value as? NSData, let dict = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSDictionary.self, from: data as Data) else { 
        	return nil
		}
		return dict
    }
}

// MARK: - Data Manager

@objc class ForumPostDataManager: NSObject {
	static let shared = ForumPostDataManager()
	private let coreData = LocalCoreData.shared

	// Used by UI to show loading cell and error cell.
	@objc dynamic var lastError : ServerError?
	@objc dynamic var isPerformingLoad: Bool = false

	// Requests the posts in a forum thread, merges the response into CoreData's store.
	func loadThreadPosts(for thread: ForumThread? = nil, forID: UUID? = nil, fromOffset: Int, 
			done: ((ForumThread?, Int) -> Void)? = nil) {
		let threadIDOptional: UUID? = thread?.id ?? forID
		guard let threadID = threadIDOptional else {
			AppLog.debug("LoadThreadPosts requires either a thread or a threadID to load from.")
			return
		}
		isPerformingLoad = true
		
		let queryParams: [URLQueryItem] = [ URLQueryItem(name: "start", value: String(fromOffset)) ]
		let path = "/api/v3/forum/\(threadID)"
		var request = NetworkGovernor.buildTwittarRequest(withPath: path, query: queryParams)
		NetworkGovernor.addUserCredential(to: &request)
		NetworkGovernor.shared.queue(request) { (package: NetworkResponse) in
			if let error = package.serverError {
				self.lastError = error
			}
			else if let data = package.data {
				self.lastError = nil
			//	print (String(data: data, encoding: .utf8))
				do {
					let response = try Settings.v3Decoder.decode(TwitarrV3ForumData.self, from: data)
					self.parseThreadWithPosts(for: thread, from: response, offset: fromOffset, done: done)
					done?(thread, fromOffset)
				}
				catch {
					NetworkLog.error("Failure parsing Forums response.", ["Error" : error, "url" : request.url as Any])
				} 
			}
			self.isPerformingLoad = false
		}
	}
	
	// Passing in either the thread or category reduces fetches that need to be done.
	func parseThreadWithPosts(for thread: ForumThread? = nil, inCategory: ForumCategory? = nil, 
			from v3Data: TwitarrV3ForumData, offset: Int = 0, done: ((ForumThread?, Int) -> Void)? = nil) {
		LocalCoreData.shared.performNetworkParsing { context in 
			context.pushOpErrorExplanation("Failed to parse Forum thread and add its posts to Core Data.")
		
			//
			var threadInContext: ForumThread
			var categoryInContext: ForumCategory
			if let thread = thread {
				threadInContext = try context.existingObject(with: thread.objectID) as! ForumThread
			}
			else {
				// Search for a thread, or make one
				let request = NSFetchRequest<ForumThread>(entityName: "ForumThread")
				request.predicate = NSPredicate(format: "id == %@", v3Data.forumID as CVarArg)
				let cdThreads = try context.fetch(request)
				threadInContext = cdThreads.first ?? ForumThread(context: context)
			}
			categoryInContext = threadInContext.category
			if let cat = inCategory {
				categoryInContext = try context.existingObject(with: cat.objectID) as! ForumCategory
			}
			
			if let callback = done {
				LocalCoreData.shared.setAfterSaveBlock(for: context) { saveSuccess in 
					let highestLoadedOffset = saveSuccess ? offset + v3Data.posts.count : offset
					let mainThreadForumThread = 
							LocalCoreData.shared.mainThreadContext.object(with: threadInContext.objectID) as? ForumThread 
					callback(mainThreadForumThread, highestLoadedOffset)
				}
			}

			// Update values on the thread
			threadInContext.buildFromV3(context: context, category: categoryInContext, v3ForumData: v3Data)
		}
	}
	
	func loadForumPostDetail(post: ForumPost) {
		var request = NetworkGovernor.buildTwittarRequest(withPath: "/api/v3/forum/post/\(post.id)", query: nil)
		NetworkGovernor.addUserCredential(to: &request)
		isPerformingLoad = true
		NetworkGovernor.shared.queue(request) { (package: NetworkResponse) in
			self.isPerformingLoad = false
			if let data = package.data {
//				print (String(decoding:data, as: UTF8.self))
				do {
					let post = try Settings.v3Decoder.decode(TwitarrV3PostDetailData.self, from: data)
					LocalCoreData.shared.performNetworkParsing { context in
						context.pushOpErrorExplanation("Failure adding post detail to Core Data.")
											
						// Make a uniqued list of users from the posts, and get them inserted/updated.
						UserManager.shared.update(users: [post.author], inContext: context)
					
						// Photos, same idea
						if let images = post.images {
							ImageManager.shared.updateV3(imageFilenames: images, inContext: context)
						}

						// Get the existing post in CD 
						let request = NSFetchRequest<ForumPost>(entityName: "ForumPost")
						request.predicate = NSPredicate(format: "id == %d", post.postID)
						request.fetchLimit = 1
						let cdResults = try context.fetch(request)
						let cdPost = cdResults.first ?? ForumPost(context: context)
						cdPost.buildFromV3DetailData(context: context, v3Object: post)
					}
				} catch 
				{
					NetworkLog.error("Failure parsing forum post detail.", ["Error" : error, "URL" : request.url as Any])
				} 
			}
		}
	}

	func parsePostData(inThread thread: ForumThread, from v3PostData: TwitarrV3PostData) {
		LocalCoreData.shared.performNetworkParsing { context in 
			context.pushOpErrorExplanation("Failed to parse Forum thread and add its posts to Core Data.")
			
			let threadInContext = try context.existingObject(with: thread.objectID) as! ForumThread
			let request = NSFetchRequest<ForumPost>(entityName: "ForumPost")
			request.predicate = NSPredicate(format: "id == %i", v3PostData.postID)
			let cdThreads = try request.execute()
			let post = cdThreads.first ?? ForumPost(context: context)
			
			var allPhotoFilenames: [String] = []
			if let images = v3PostData.images {
				allPhotoFilenames = images
			}
			ImageManager.shared.updateV3(imageFilenames: allPhotoFilenames, inContext: context)
			
			post.buildFromV3(context: context, v3Object: v3PostData, thread: threadInContext)
		}		
	}
	
	func queuePostEditOp(for editPost: ForumPost, newText: String, images: [PhotoDataType]?, 
			done: @escaping (PostOpForumPost?) -> Void) {
		EmojiDataManager.shared.gatherEmoji(from: newText)
		
		LocalCoreData.shared.performLocalCoreDataChange { context, currentUser in
			// Make sure there's a logged in user and that the logged in user authored the post we're editing.
			guard currentUser.username == editPost.author.username  else {
				done(nil) 
				return 
			}
			guard let editPostInContext = context.object(with: editPost.objectID) as? ForumPost else {
				done(nil)
				return
			}
			context.pushOpErrorExplanation("Couldn't save context while editing Forum post.")
			
			// Is there an existing pending edit for this post?
			// Since this app currently only allows the author to edit a post (that is, we don't support mod edit operations),
			// any edit op attached to this post should be authored by the current user.
			var editOp: PostOpForumPost
			if let opEditing = editPost.opEditing, let opInContext = context.object(with: opEditing.objectID) as? PostOpForumPost {
				editOp = opInContext
			}
			else {
				editOp = PostOpForumPost(context: context)
			}
			
			editOp.text = newText
			editOp.editPost = editPostInContext
			editOp.thread = editPostInContext.thread
			let photoOpArray: [PostOpPhoto_Attachment]? = images?.map {
				let op = PostOpPhoto_Attachment(context: context); op.setupFromPhotoData($0); 
				op.parentForumPostOp = editOp
				return op 
			}
			// In theory we could avoid replacing all the photos if there were no changes, but edits shouldn't happen *that* often.
			if let photoOpArray = photoOpArray {
				editOp.photos = NSOrderedSet(array: photoOpArray)
			}
			else {
				editOp.photos = nil
			}
			editOp.author = currentUser
			editOp.operationState = .readyToSend
						
			LocalCoreData.shared.setAfterSaveBlock(for: context) { saveSuccess in 
				let mainThreadPost = LocalCoreData.shared.mainThreadContext.object(with: editOp.objectID) as? PostOpForumPost 
				done(mainThreadPost)
			}
		}
	}
	
	// If inThread is nil, this post is a new thread, and titleText must be non-nil.
	func queuePost(existingDraft: PostOpForumPost?, inThread: ForumThread?, inCategory: ForumCategory?, 
			titleText: String?, postText: String, images: [PhotoDataType]?, done: @escaping (PostOpForumPost?) -> Void) {
		EmojiDataManager.shared.gatherEmoji(from: postText)	

		LocalCoreData.shared.performLocalCoreDataChange { context, currentUser in
			// Make sure there's a logged in user and that the logged in user authored the post we're editing.
			guard inThread != nil || titleText != nil  else {
				done(nil) 
				return 
			}
			context.pushOpErrorExplanation("Couldn't save context while editing Forum post.")
			
			// Get network context versions of passed in CoreData objects
			var postOp: PostOpForumPost
			if let draftOp = existingDraft, let existingOp = context.object(with: draftOp.objectID) as? PostOpForumPost {
				postOp = existingOp
			}
			else {
				postOp = PostOpForumPost(context: context)
			}
			if let thread = inThread, let existingThreaad = context.object(with: thread.objectID) as? ForumThread {
				postOp.thread = existingThreaad
			}
			if let cat = inCategory, let catInContext = context.object(with: cat.objectID) as? ForumCategory {
				postOp.category = catInContext
			}
			
			postOp.text = postText
			postOp.subject = titleText
			let photoOpArray: [PostOpPhoto_Attachment]? = images?.map {
				let op = PostOpPhoto_Attachment(context: context)
				op.setupFromPhotoData($0)
				op.parentForumPostOp = postOp
				return op 
			}
			if let photoOpArray = photoOpArray {
				postOp.photos = NSOrderedSet(array: photoOpArray)
			}
			else {
				postOp.photos = nil
			}
			postOp.author = currentUser
			postOp.operationState = .readyToSend
						
			LocalCoreData.shared.setAfterSaveBlock(for: context) { saveSuccess in 
				let mainThreadPost = LocalCoreData.shared.mainThreadContext.object(with: postOp.objectID) as? PostOpForumPost 
				done(mainThreadPost)
			}
		}
	}
}
	
// MARK: - V3 API Decoding
struct TwitarrV3ForumData: Codable {
	/// The forum's ID.
	var forumID: UUID
	/// The ID of the forum's containing Category..
	var categoryID: UUID
	/// The forum's title
	var title: String
	/// The forum's creator.
	var creator: TwitarrV3UserHeader
	/// Whether the forum is in read-only state.
	var isLocked: Bool
	/// Whether the user has favorited forum.
	var isFavorite: Bool
	/// Whether the user has muted the forum.
	var isMuted: Bool
	/// The paginator contains the total number of posts in the forum, and the start and limit of the requested subset in `posts`.
	var paginator: TwitarrV3Paginator
	/// Posts in the forum.
	var posts: [TwitarrV3PostData]
	/// If this forum is for an Event on the schedule, the ID of the event.
	var eventID: UUID?
	/// If this forum is pinned or not.
	var isPinned: Bool?
}

struct TwitarrV3PostData: Codable {
    /// The ID of the post.
    var postID: Int64
    /// The timestamp of the post.
    var createdAt: Date
    /// The post's author.
    var author: TwitarrV3UserHeader
    /// The text of the post.
    var text: String
    /// The filenames of the post's optional images.
    var images: [String]?
    /// Whether the current user has bookmarked the post.
    var isBookmarked: Bool
    /// The current user's `LikeType` reaction on the post.
    var userLike: TwitarrV3LikeType?
    /// The total number of `LikeType` reactions on the post.
    var likeCount: Int64
	/// Whether the post has been pinned to the forum.
	var isPinned: Bool?
}

public struct TwitarrV3PostDetailData: Codable {
    /// The ID of the post.
    var postID: Int
    /// The ID of the Forum containing the post.
    var forumID: UUID
    /// The timestamp of the post.
    var createdAt: Date
    /// The post's author.
    var author: TwitarrV3UserHeader
    /// The text of the forum post.
    var text: String
    /// The filenames of the post's optional images.
    var images: [String]?
    /// Whether the current user has bookmarked the post.
    var isBookmarked: Bool
    /// The current user's `LikeType` reaction on the post.
    var userLike: TwitarrV3LikeType?
    /// The seamonkeys with "laugh" reactions on the post.
    var laughs: [TwitarrV3UserHeader]
    /// The seamonkeys with "like" reactions on the post.
    var likes: [TwitarrV3UserHeader]
    /// The seamonkeys with "love" reactions on the post.
    var loves: [TwitarrV3UserHeader]
}


enum TwitarrV3LikeType: String, Codable {
    /// A 😆.
    case laugh
    /// A 👍.
    case like
    /// A ❤️.
    case love
}
