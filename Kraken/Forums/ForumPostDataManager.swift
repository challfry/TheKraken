//
//  ForumPostDataManager.swift
//  Kraken
//
//  Created by Chall Fry on 2/3/21.
//  Copyright © 2021 Chall Fry. All rights reserved.
//

import UIKit

@objc(ForumPost) public class ForumPost: KrakenManagedObject {
    @NSManaged public var id: Int64
    @NSManaged public var text: String
    @NSManaged public var createTime: Date		
    @NSManaged public var reactionCount: Int64		// How many users like this post. 0 if unknown. This will
    											// be unknown for most posts.
    
    @NSManaged public var author: KrakenUser
    @NSManaged public var thread: ForumThread
    @NSManaged public var photos: NSMutableOrderedSet	// PhotoDetails
    @NSManaged public var reactions: Set<Reaction>

    @NSManaged public var reactionOps: NSMutableSet?
	@NSManaged public var opDeleting: PostOpForumPostDelete?
	@NSManaged public var opEditing: PostOpForumPost?
  
	// Properties built from reactions
	@objc dynamic public var reactionDict: NSMutableDictionary?			// the reactions set, keyed by reaction.word

// MARK: Methods

	override public func awakeFromInsert() {
		// createdAt = Date()
		setPrimitiveValue(Date(), forKey: "createTime")
	}

	public override func awakeFromFetch() {
		super.awakeFromFetch()

		// Update derived properties
    	let dict = NSMutableDictionary()
		for reaction in reactions {
			dict.setValue(reaction, forKey: reaction.word)
		}
		reactionDict = dict
	}

	// Requires: Users, Photos for post.
	func buildFromV3(context: NSManagedObjectContext, v3Object: TwitarrV3PostData, thread: ForumThread) {
		TestAndUpdate(\.id, v3Object.postID)
		TestAndUpdate(\.text, v3Object.text)
		TestAndUpdate(\.createTime, v3Object.createdAt)
		TestAndUpdate(\.reactionCount, v3Object.likeCount)
		TestAndUpdate(\.thread, thread)
		
		// Set the author
		if author.username != v3Object.author.username {
			let userPool: [UUID : KrakenUser ] = context.userInfo.object(forKey: "Users") as! [UUID : KrakenUser] 
			if let cdAuthor = userPool[v3Object.author.userID] {
				author = cdAuthor
			}
		}
		
		if let newImageFilename = v3Object.image {
			if (photos.firstObject as? PhotoDetails)?.id != newImageFilename {
				photos.removeAllObjects()
				let photoDict: [String : PhotoDetails] = context.userInfo.object(forKey: "PhotoDetails") as! [String : PhotoDetails] 
				if let newPhotoDetails = photoDict[newImageFilename] {
					photos.insert(newPhotoDetails, at: 0)
				}
			}

		} 
		else {
			if photos.count > 0{
				photos.removeAllObjects()
			}
		}
					
		// Set the user's reaction to the tweet
		if let currentUser = CurrentUser.shared.getLoggedInUser(in: context) {
			// Find any existing reaction the user has
			var userCurrentReaction: Reaction?
			if let userReacts = currentUser.reactions {
				var userCurrentReactions = reactions.intersection(userReacts)
				
				// If the user has multiple reactions, something bad has happended. Remove all.
				if userCurrentReactions.count > 1 {
					userCurrentReactions.forEach { 
						if let _ = $0.users.remove(currentUser) {
							$0.count -= 1
						}
					}
					userCurrentReactions.removeAll()
				}
				
				// If the new reaction is different or deleted, remove existing reaction from CD.
				userCurrentReaction = userCurrentReactions.first
				if let ucr = userCurrentReaction, v3Object.userLike?.rawValue != ucr.word {
					if let _ = ucr.users.remove(currentUser) {
						ucr.count -= 1
					}
				}
			}
				
			// Add new reaction, if any
			if let newReactionWord = v3Object.userLike?.rawValue, userCurrentReaction?.word != newReactionWord {
				if let reaction = reactions.first(where: { $0.word == newReactionWord } ) {
					let (didInsert, _) = reaction.users.insert(currentUser)
					if didInsert {
						reaction.count += 1
					}
				}
				else {
					let newReaction = Reaction(context: context)
					newReaction.word = newReactionWord
					newReaction.count = 1
					newReaction.users = Set([currentUser])
					newReaction.sourceForumPost	= self
				}
			}
		}
		// TODO: Not handled: isBookmarked, userLike

		let hashtags = StringUtilities.extractHashtags(v3Object.text)
		HashtagDataManager.shared.addHashtags(hashtags)
	}

//	func buildFromV2(context: NSManagedObjectContext, v2Object: TwitarrV2ForumPost, thread: ForumThread) {
//		TestAndUpdate(\.id, v2Object.id)
//		TestAndUpdate(\.text, v2Object.text)
//		TestAndUpdate(\.timestamp, v2Object.timestamp)
//		TestAndUpdate(\.thread, thread)
//		
//		// Set the author
//		if author.username != v2Object.author.username {
//			let userPool: [String : KrakenUser ] = context.userInfo.object(forKey: "Users") as! [String : KrakenUser] 
//			if let cdAuthor = userPool[v2Object.author.username] {
//				author = cdAuthor
//			}
//		}
//		
//		// If the author of this post is the current user, mark that they've posted in the thread
//		if author.username == CurrentUser.shared.getLoggedInUser(in: context)?.username {
//			if let rco = thread.getReadCountObject(context: context), rco.userPosted != true {
//				rco.userPosted = true
//			}
//		}
//		
//		// Are all the photoDetails in our photos ordered set the same as what's in the network response?
//		var photosUnchanged = photos.count == v2Object.photos.count
//		if photosUnchanged {
//			for (index, photoAsAny) in photos.enumerated() {
//				if let photo = photoAsAny as? PhotoDetails, v2Object.photos[index].id != photo.id {
//					photosUnchanged = false
//					break
//				}
//			}
//		}
//		
//		// If the photos have changed in any way, just delete all of them and rebuild. 
//		if !photosUnchanged {
//			photos.removeAllObjects()
//			let photoDict: [String : PhotoDetails] = context.userInfo.object(forKey: "PhotoDetails") as! [String : PhotoDetails] 
//			for v2Photo in v2Object.photos {
//				let newPhoto = photoDict[v2Photo.id] ?? PhotoDetails(context: context)
//				newPhoto.buildFromV2(context: context, v2Object: v2Photo)
//				photos.add(newPhoto)
//			}
//		}
//		
//		let hashtags = StringUtilities.extractHashtags(v2Object.text)
//		HashtagDataManager.shared.addHashtags(hashtags)
//	}

	// Note that for forum posts, we're not putting in the effort to model reactions fully, as the server API
	// isn't set up such that we can really use reactions fully. Mostly, the only way to get the full set of reactions
	// to a post is to make a special API call, one that must be made for EACH post.
	func buildReactionsFromV2(context: NSManagedObjectContext, v2Object: TwitarrV2ReactionsSummary) {

//		// Find the 'like' reaction, set count, add/remove current user from set of likers.
//		if let likeReaction = v2Object["like"] {
//			reactionCount = Int64(likeReaction.count)
//			if let currentUser = CurrentUser.shared.getLoggedInUser(in: context) {
//				if likeReaction.me && !likedByUsers.contains(currentUser) {
//					likedByUsers.insert(currentUser)
//				}
//				else if !likeReaction.me && likedByUsers.contains(currentUser) {
//					likedByUsers.remove(currentUser)
//				}
//			}
//		}
	}
	
	// Always returns nil if nobody's logged in.
	func getPendingUserReaction(_ named: String) -> PostOpForumPostReaction? {
		if let username = CurrentUser.shared.loggedInUser?.username, let reaction = reactionOps?.first(where: { reaction in
				guard let r = reaction as? PostOpForumPostReaction else { return false }
				return r.author.username == username && r.reactionWord == named }) {
			return reaction as? PostOpForumPostReaction
		}
		return nil
	}
	
	// This func lets you set any reaction you like, however our data model only stores 'like' reactions for 
	// Forum posts. This is okay. The server keeps track of other reactions, even if we don't.
	func setReaction(_ reactionWord: String, to newState: Bool) {
		LocalCoreData.shared.performLocalCoreDataChange { context, currentUser in
			guard let thisPost = context.object(with: self.objectID) as? ForumPost else { return }
			
			// Check for existing op for this user, with this word
			let op = thisPost.getPendingUserReaction(reactionWord) ?? PostOpForumPostReaction(context: context)
			op.isAdd = newState
			op.operationState = .readyToSend
			op.reactionWord = reactionWord
			op.sourcePost = thisPost
		}
	}

	func cancelReactionOp(_ reactionWord: String) {
		guard let existingOp = getPendingUserReaction(reactionWord) else { return }
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
		
		let queryParams: [URLQueryItem] = []
		let path = "api/v3/forum/\(threadID)"
		var request = NetworkGovernor.buildTwittarV2Request(withPath: path, query: queryParams)
		NetworkGovernor.addUserCredential(to: &request)
		NetworkGovernor.shared.queue(request) { (package: NetworkResponse) in
			if let error = NetworkGovernor.shared.parseServerError(package) {
				self.lastError = error
				done?(thread, fromOffset)
			}
			else if let data = package.data {
				self.lastError = nil
			//	print (String(data: data, encoding: .utf8))
				do {
					let response = try Settings.v3Decoder.decode(TwitarrV3ForumData.self, from: data)
					self.parseThreadWithPosts(for: thread, from: response, offset: fromOffset, done: done)
				}
				catch {
					NetworkLog.error("Failure parsing Forums response.", ["Error" : error, "url" : request.url as Any])
					done?(thread, fromOffset)
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
					DispatchQueue.main.async {
						let highestLoadedOffset = saveSuccess ? offset + v3Data.posts.count : offset
						let mainThreadForumThread = 
								LocalCoreData.shared.mainThreadContext.object(with: threadInContext.objectID) as? ForumThread 
						callback(mainThreadForumThread, highestLoadedOffset)
					}
				}
			}

			// Update values on the thread
			threadInContext.buildFromV3(context: context, category: categoryInContext, v3ForumData: v3Data)
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
			if let image = v3PostData.image {
				allPhotoFilenames =  [image]
			}
			ImageManager.shared.updateV3(imageFilenames: allPhotoFilenames, inContext: context)
			
			post.buildFromV3(context: context, v3Object: v3PostData, thread: threadInContext)
		}		
	}
	
	func queuePostEditOp(for editPost: ForumPost, newText: String, images: [PhotoUploadPackage]?, 
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
			let photoOpArray: [PostOpForum_Photo]? = images?.map { let op = PostOpForum_Photo(context: context); op.setupFromPackage($0); return op }
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
	func queuePost(existingDraft: PostOpForumPost?, inThread: ForumThread?, titleText: String?, postText: String, images: [PhotoUploadPackage]?,
			done: @escaping (PostOpForumPost?) -> Void) {
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
			var threadInContext: ForumThread?
			if let thread = inThread, let existingThreaad = context.object(with: thread.objectID) as? ForumThread {
				threadInContext = existingThreaad
			}
			
				
			postOp.text = postText
			postOp.subject = titleText
			postOp.thread = threadInContext
			let photoOpArray: [PostOpForum_Photo]? = images?.map { let op = PostOpForum_Photo(context: context); op.setupFromPackage($0); return op }
			if let photoOpArray = photoOpArray {
				postOp.photos = NSOrderedSet(array: photoOpArray)
			}
			else {
				postOp.photos = nil
			}
			postOp.author = currentUser
			postOp.operationState = .readyToSend
						
			LocalCoreData.shared.setAfterSaveBlock(for: context) { saveSuccess in 
				DispatchQueue.main.async {
					let mainThreadPost = LocalCoreData.shared.mainThreadContext.object(with: postOp.objectID) as? PostOpForumPost 
					done(mainThreadPost)
				}
			}
		}
	}
}
	
// MARK: - V2 API Decoding

// Contains info on individual posts in a thread
struct TwitarrV2ForumThread: Codable {
	let id: String
	let subject: String
	let sticky: Bool
	let locked: Bool
	let postCount: Int64
	let latestRead: Int64?
	let posts: [TwitarrV2ForumPost]
	
	let nextPage: Int64?
	let prevPage: Int64?
	let pageCount: Int64?
	let page: Int64?
	
	enum CodingKeys: String, CodingKey {
		case id, subject, sticky, locked, page, posts
		case nextPage = "next_page"
		case prevPage = "prev_page"
		case pageCount = "page_count"
		case postCount = "post_count"
		case latestRead = "latest_read"
	}
}

struct TwitarrV2ForumPost: Codable {
	let id: String
	let forumId: String
	let author: TwitarrV2UserInfo
	let threadLocked: Bool
	let text: String
	let timestamp: Int64
	let photos: [TwitarrV2PhotoDetails]
	let new: Bool?
	
	enum CodingKeys: String, CodingKey {
		case id, author, text, timestamp, photos, new
		case forumId = "forum_id"
		case threadLocked = "thread_locked"
	}
}

// GET /api/v2/forums/:id
struct TwitarrV2GetForumPostsResponse: Codable {
	let status: String
	let forumThread: TwitarrV2ForumThread
	
	enum CodingKeys: String, CodingKey {
		case status
		case forumThread = "forum_thread"
	}
}

// MARK: - V3 API Decoding
struct TwitarrV3ForumData: Codable {
    /// The forum's ID.
    var forumID: UUID
    /// The forum's title
    var title: String
    /// The forum's creator.
    var creator: TwitarrV3UserHeader
    /// Whether the forum is in read-only state.
    var isLocked: Bool
    /// Whether the user has favorited forum.
    var isFavorite: Bool
    /// The posts in the forum.
    var posts: [TwitarrV3PostData]
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
    /// The filename of the post's optional image.
    var image: String?
    /// Whether the current user has bookmarked the post.
    var isBookmarked: Bool
    /// The current user's `LikeType` reaction on the post.
    var userLike: TwitarrV3LikeType?
    /// The total number of `LikeType` reactions on the post.
    var likeCount: Int64
}

enum TwitarrV3LikeType: String, Codable {
    /// A 😆.
    case laugh
    /// A 👍.
    case like
    /// A ❤️.
    case love
}
