//
//  ForumsDataManager.swift
//  Kraken
//
//  Created by Chall Fry on 11/26/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit

@objc(ForumThread) public class ForumThread: KrakenManagedObject {
    @NSManaged public var id: String
    @NSManaged public var subject: String
    @NSManaged public var locked: Bool
    @NSManaged public var sticky: Bool
    @NSManaged public var lastPostTime: Int64
    @NSManaged public var postCount: Int64			// == posts.count iff we've downloaded all the posts.
    
    @NSManaged public var posts: Set<ForumPost>
    @NSManaged public var lastPoster: KrakenUser
    @NSManaged public var readCount: Set<ForumReadCount>
    
    @NSManaged public var lastUpdateTime: Date?				// Last time we loaded *posts* on this thread. ThreadMeta doesn't count.
    

    // Sets reasonable default values for properties that could conceivably not change during buildFromV2 methods.
	public override func awakeFromInsert() {
		super.awakeFromInsert()
		locked = false
		sticky = false
		subject = ""
	}
    
    // Only call this within a CoreData perform block.
	func buildFromV2Meta(context: NSManagedObjectContext, v2Object: TwitarrV2ForumThreadMeta) {
		TestAndUpdate(\.id, v2Object.id)
		TestAndUpdate(\.subject, v2Object.subject)
		TestAndUpdate(\.lastPostTime, v2Object.timestamp)
		TestAndUpdate(\.sticky, v2Object.sticky)
		TestAndUpdate(\.locked, v2Object.locked)
		TestAndUpdate(\.postCount, v2Object.posts)
		
		if lastPoster.username != v2Object.lastPostAuthor.username {
			let userPool: [String : KrakenUser ] = context.userInfo.object(forKey: "Users") as! [String : KrakenUser] 
			if let cdAuthor = userPool[v2Object.lastPostAuthor.username] {
				lastPoster = cdAuthor
			}
		}
		
		// Set up the associated ForumReadCount object if we have a postCount to update
		if let newPostCount = v2Object.count, let readCountObject = getReadCountObject(context: context) {
			readCountObject.numPostsRead = postCount - newPostCount
		}
		
	}
    
	func buildFromV2(context: NSManagedObjectContext, v2Object: TwitarrV2ForumThread) {
		TestAndUpdate(\.id, v2Object.id)
		TestAndUpdate(\.subject, v2Object.subject)
		TestAndUpdate(\.sticky, v2Object.sticky)
		TestAndUpdate(\.locked, v2Object.locked)
		TestAndUpdate(\.postCount, v2Object.postCount)
	
		for post in v2Object.posts {
			var existingPost: ForumPost
			if let optionalPost = posts.first(where: { $0.id == post.id }) {
				existingPost = optionalPost
			}
			else {
				existingPost = ForumPost(context: context)
				posts.insert(existingPost)
			}
			existingPost.buildFromV2(context: context, v2Object: post, thread: self)
		}
		lastUpdateTime = Date()
		
		internalUpdateLastReadTime(context: context, toNewTime: v2Object.latestRead)
	}
	
	// Creates the RCO for this user+forum if it doesn't exist. Remember that every user has an RCO for every forum they
	// interact with. Will be nil if no logged in user.
	func getReadCountObject(context: NSManagedObjectContext) -> ForumReadCount? {
		guard self.managedObjectContext === context else { 
			CoreDataLog.error("ForumThread needs to be in the nextworkOperationContext.", nil)
			return nil
		}
		guard let currentUser = CurrentUser.shared.getLoggedInUser(in: context) else { return nil }
		
		var readCountObject = readCount.first { $0.user.username == currentUser.username }
		if readCountObject == nil {
			readCountObject = ForumReadCount(context: context)
			readCountObject?.user = currentUser
			readCountObject?.forumThread = self
			readCountObject?.isFavorite = false
		}
		return readCountObject
	}
	
	// External method, called by the UI to update the view time of a forum. Call this just as the user finishes
	// looking at the forum.
	func updateLastReadTime() {
		LocalCoreData.shared.performNetworkParsing { context in
			context.pushOpErrorExplanation("Failed to update forum read time.")
			if let selfInContext = try context.existingObject(with: self.objectID) as? ForumThread,
					let rco = selfInContext.getReadCountObject(context: context) {
				rco.lastReadTime = Date()
				
				// Note that we're not updating the number of posts read to == postCount. postCount is how many
				// posts the forum has in total. posts.count is how many we've downloaded--the user cannot have
				// (locally) read more than that. They may not even have read all the downloaded posts--we could 
				// modify this fn and the UI to track how far the user scrolled.
				if rco.numPostsRead	< Int64(self.posts.count) {
					rco.numPostsRead = Int64(self.posts.count)
				}
			}
		}		
	}
	
	func lastPostDate() -> Date {
		return Date(timeIntervalSince1970: Double(lastPostTime) / 1000.0)
	}

	// For use during parsing. Updates last read time server-provided timestamp of when user last viewed the thread.
	// Note that LastReadTime is the *previous* time we loaded this thread.
	func internalUpdateLastReadTime(context: NSManagedObjectContext, toNewTime: Int64?) {
		if let newTime = toNewTime, let rco = self.getReadCountObject(context: context) {
			let lastReadTime = Date(timeIntervalSince1970: Double(newTime) / 1000.0)
			if let objectLRT = rco.lastReadTime, lastReadTime <= objectLRT {
				// Do nothing -- the object already has a LRT that's more recent than the new value
			}
			else {
				rco.lastReadTime = lastReadTime
			}
		}
	}
	
	func setForumFavoriteStatus(to: Bool) {
		LocalCoreData.shared.performLocalCoreDataChange { context, currentUser in
			context.pushOpErrorExplanation("Failed to update forum favorite status.")
			if let selfInContext = try context.existingObject(with: self.objectID) as? ForumThread,
					let rco = selfInContext.getReadCountObject(context: context) {
				rco.isFavorite = to
				let isLocked = selfInContext.locked
				selfInContext.locked = !isLocked
				selfInContext.locked = isLocked
			}
		}		
	}
}

@objc(ForumPost) public class ForumPost: KrakenManagedObject {
    @NSManaged public var id: String
    @NSManaged public var text: String
    @NSManaged public var timestamp: Int64
    @NSManaged public var totalLikes: Int64		// How many users like this post. 0 if unknown. This will
    											// be unknown for most posts.
    
    @NSManaged public var author: KrakenUser
    @NSManaged public var thread: ForumThread
//	@NSManaged public var photos: Set<PhotoDetails>
    @NSManaged public var photos: NSMutableOrderedSet	// PhotoDetails
    @NSManaged public var reactionOps: NSMutableSet?
    @NSManaged public var likedByUsers: Set<KrakenUser>
    @NSManaged public var editedBy: PostOpForumPost?
	@NSManaged public var opDeleting: PostOpForumPostDelete?
   
// MARK: Methods

	func buildFromV2(context: NSManagedObjectContext, v2Object: TwitarrV2ForumPost, thread: ForumThread) {
		TestAndUpdate(\.id, v2Object.id)
		TestAndUpdate(\.text, v2Object.text)
		TestAndUpdate(\.timestamp, v2Object.timestamp)
		TestAndUpdate(\.thread, thread)
		
		// Set the author
		if author.username != v2Object.author.username {
			let userPool: [String : KrakenUser ] = context.userInfo.object(forKey: "Users") as! [String : KrakenUser] 
			if let cdAuthor = userPool[v2Object.author.username] {
				author = cdAuthor
			}
		}
		
		// If the author of this post is the current user, mark that they've posted in the thread
		if author.username == CurrentUser.shared.loggedInUser?.username {
			if let rco = thread.getReadCountObject(context: context), rco.userPosted != true {
				rco.userPosted = true
			}
		}
		
		// Are all the photoDetails in our photos ordered set the same as what's in the network response?
		var photosUnchanged = photos.count == v2Object.photos.count
		if photosUnchanged {
			for (index, photoAsAny) in photos.enumerated() {
				if let photo = photoAsAny as? PhotoDetails, v2Object.photos[index].id != photo.id {
					photosUnchanged = false
					break
				}
			}
		}
		
		// If the photos have changed in any way, just delete all of them and rebuild. 
		if !photosUnchanged {
			photos.removeAllObjects()
			let photoDict: [String : PhotoDetails] = context.userInfo.object(forKey: "PhotoDetails") as! [String : PhotoDetails] 
			for v2Photo in v2Object.photos {
				let newPhoto = photoDict[v2Photo.id] ?? PhotoDetails(context: context)
				newPhoto.buildFromV2(context: context, v2Object: v2Photo)
				photos.add(newPhoto)
			}
		}
	}

	// Note that for forum posts, we're not putting in the effort to model reactions fully, as the server API
	// isn't set up such that we can really use reactions fully. Mostly, the only way to get the full set of reactions
	// to a post is to make a special API call, one that must be made for EACH post.
	func buildReactionsFromV2(context: NSManagedObjectContext, v2Object: TwitarrV2ReactionsSummary) {

		// Find the 'like' reaction, set count, add/remove current user from set of likers.
		if let likeReaction = v2Object["like"] {
			totalLikes = Int64(likeReaction.count)
			if let currentUser = CurrentUser.shared.getLoggedInUser(in: context) {
				if likeReaction.me && !likedByUsers.contains(currentUser) {
					likedByUsers.insert(currentUser)
				}
				else if !likeReaction.me && likedByUsers.contains(currentUser) {
					likedByUsers.remove(currentUser)
				}
			}
		}
	}

	func postDate() -> Date {
		return Date(timeIntervalSince1970: Double(timestamp) / 1000.0)
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
		if let editOp = editedBy, editOp.author.username == currentUsername {
			PostOperationDataManager.shared.remove(op: editOp)
		}
	}
}

// Tracks the number of posts that the given user has read in the given thread.
@objc(ForumReadCount) public class ForumReadCount: KrakenManagedObject {
    @NSManaged public var numPostsRead: Int64		// How many posts this user has read in this thread.
    												// May not be == to the number of posts we've loaded.

	@NSManaged public var lastReadTime: Date?		// The last time this user looked at this forum on this device.
													// Not saved to server.
	
	@NSManaged public var isFavorite: Bool 			// If TRUE, the user has favorited this forum. Note that the server
													// doesn't support favorites for forum threads (only posts).

	@NSManaged public var userPosted: Bool			// TRUE iff .user has authored a post in .forumThread.

    @NSManaged public var forumThread: ForumThread
    @NSManaged public var user: KrakenUser
    
    // Sets reasonable default values for properties that could conceivably not change during buildFromV2 methods.
	public override func awakeFromInsert() {
		super.awakeFromInsert()
		numPostsRead = 0
		isFavorite = false
		userPosted = false
	}
    
//	func buildFromV2(context: NSManagedObjectContext, v2Object: TwitarrV2ForumThread) {
//	}

}


@objc class ForumsDataManager: NSObject {
	static let shared = ForumsDataManager()
	private let coreData = LocalCoreData.shared
	
	// Used by UI to show loading cell and error cell.
	@objc dynamic var lastError : ServerError?
	@objc dynamic var isPerformingLoad: Bool = false
	
	// Used by UI to show time of last refresh--defined as a successful network load of threads from offset 0.
	@objc dynamic var lastForumRefreshTime: Date = Date()
	
	func loadForumThreads(fromOffset: Int, done: @escaping () -> Void) {
		isPerformingLoad = true
		
		var queryParams: [URLQueryItem] = []
		queryParams.append(URLQueryItem(name:"page", value: "\(fromOffset / 20)"))
		queryParams.append(URLQueryItem(name:"limit", value: "20"))

		var request = NetworkGovernor.buildTwittarV2Request(withPath:"/api/v2/forums", query: queryParams)
		NetworkGovernor.addUserCredential(to: &request)
		NetworkGovernor.shared.queue(request) { (package: NetworkResponse) in
			if let error = NetworkGovernor.shared.parseServerError(package) {
				self.lastError = error
			}
			else if let data = package.data {
				self.lastError = nil
			//	print (String(data: data, encoding: .utf8))
				let decoder = JSONDecoder()
				do {
					let response = try decoder.decode(TwitarrV2GetForumsResponse.self, from: data)
					self.parseForumThreads(from: response.forumThreads)
				}
				catch {
					NetworkLog.error("Failure parsing Forums response.", ["Error" : error, "url" : request.url as Any])
				}
				
				if fromOffset == 0 {
					self.lastForumRefreshTime = Date()
				}
			}
			self.isPerformingLoad = false
		}
	}
	
	// Takes an array of threads from a server response and merges them into CoreData's store.
	// Note: Probably only ever called from its network response handler. Broken out this way to make it easier to 
	// see what ops are performed within the CD context.
	func parseForumThreads(from threads: [TwitarrV2ForumThreadMeta]) {
		LocalCoreData.shared.performNetworkParsing { context in
			context.pushOpErrorExplanation("Failed to parse Forum threads and add to Core Data.")

			// Make sure all the users mentioned as lastPosters get added to our User table
			// Note that this also sets "Users" on our context's userInfo.
			let lastPostAuthors = threads.map { $0.lastPostAuthor }
			UserManager.shared.update(users: lastPostAuthors, inContext: context)
			
			// Fetch threads from CD that match the ids in the given theads
			let allThreadIDs = threads.map { $0.id }
			let request = self.coreData.persistentContainer.managedObjectModel.fetchRequestFromTemplate(withName: "ForumThreadsWithIds", 
					substitutionVariables: [ "ids" : allThreadIDs ]) as! NSFetchRequest<ForumThread>
			let cdThreads = try request.execute()
			let cdThreadsDict = Dictionary(cdThreads.map { ($0.id, $0) }, uniquingKeysWith: { (first,_) in first })

			for forumThread in threads {
				let cdThread = cdThreadsDict[forumThread.id] ?? ForumThread(context: context)
				cdThread.buildFromV2Meta(context: context, v2Object: forumThread)
			}
		}
	}
	
	// Requests the posts in a forum thread, merges the response into CoreData's store.
	func loadThreadPosts(for thread: ForumThread, fromOffset: Int, done: @escaping () -> Void) {
		internalLoadThreadPosts(for: thread, fromOffset: fromOffset, isSecondLoad: false, done: done)
	}
	
	private func internalLoadThreadPosts(for thread: ForumThread, fromOffset: Int, isSecondLoad: Bool, done: @escaping () -> Void) {
		guard !thread.id.isEmpty else {
			NetworkLog.error("Cannot call /api/v2/forums/:id, id is nil.", ["thread" : thread])
			return
		}
		isPerformingLoad = true
		
		var queryParams: [URLQueryItem] = []
		queryParams.append(URLQueryItem(name:"page", value: "\(fromOffset / 20)"))
		queryParams.append(URLQueryItem(name:"limit", value: "20"))

		var request = NetworkGovernor.buildTwittarV2Request(withPath:"/api/v2/forums/\(thread.id)", query: queryParams)
		NetworkGovernor.addUserCredential(to: &request)
		NetworkGovernor.shared.queue(request) { (package: NetworkResponse) in
			if let error = NetworkGovernor.shared.parseServerError(package) {
				self.lastError = error
			}
			else if let data = package.data {
				self.lastError = nil
			//	print (String(data: data, encoding: .utf8))
				let decoder = JSONDecoder()
				do {
					let response = try decoder.decode(TwitarrV2GetForumPostsResponse.self, from: data)
					self.parseNewThreadPosts(from: response.forumThread)
				}
				catch {
					NetworkLog.error("Failure parsing Forums response.", ["Error" : error, "url" : request.url as Any])
				} 
			}
			self.isPerformingLoad = false

			// If the load we just completed was the last page we were aware of, but the load's new postCount
			// says there are posts on the next page, get the next page.
			if !isSecondLoad, fromOffset / 20 != thread.postCount / 20 {
				self.internalLoadThreadPosts(for: thread, fromOffset: fromOffset + 20, isSecondLoad: true, done: done)
			}
		}
	}
	
	
	func parseNewThreadPosts(from thread: TwitarrV2ForumThread) {
		LocalCoreData.shared.performNetworkParsing { context in 
			try self.internalParseNewThreadPosts(context: context, from: thread)
		}		
	}
	
	func internalParseNewThreadPosts(context: NSManagedObjectContext, from thread: TwitarrV2ForumThread) throws {
		context.pushOpErrorExplanation("Failed to parse Forum thread and add its posts to Core Data.")
		
		// Make sure all the post authors get added to our User table
		// Note that this also sets "Users" on our context's userInfo.
		let postAuthors = thread.posts.map { $0.author }
		UserManager.shared.update(users: postAuthors, inContext: context)
		
		// Get all the photos atached to all the posts into a Photos set.
		let allPhotos = thread.posts.flatMap { $0.photos }
		let forumPhotos = Dictionary( allPhotos.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first } )
		ImageManager.shared.update(photoDetails: forumPhotos, inContext: context)
		
		// Fetch threads from CD that match the ids in the given theads
		let request = self.coreData.persistentContainer.managedObjectModel.fetchRequestFromTemplate(withName: "ForumThreadsWithIds", 
				substitutionVariables: [ "ids" : [thread.id] ]) as! NSFetchRequest<ForumThread>
		let cdThreads = try request.execute()
		let forumThread = cdThreads.first ?? ForumThread(context: context)

		forumThread.buildFromV2(context: context, v2Object: thread)
	}
	
	func queuePostEditOp(for editPost: ForumPost, newText: String, images: [PhotoUploadPackage]?, 
			done: @escaping (PostOpForumPost?) -> Void) {
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
			if let editedBy = editPost.editedBy, let opInContext = context.object(with: editedBy.objectID) as? PostOpForumPost {
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

// Does not contain info on individual posts in a thread
struct TwitarrV2ForumThreadMeta: Codable {
	let id: String
	let subject: String
	let sticky: Bool
	let locked: Bool
	let lastPostAuthor: TwitarrV2UserInfo
	let posts: Int64
	let timestamp: Int64
	let lastPostPage: Int64
	let count: Int64?
	let newPosts: Int64?
	
	enum CodingKeys: String, CodingKey {
		case id, subject, sticky, locked, posts, timestamp, count
		case lastPostAuthor = "last_post_author"
		case lastPostPage = "last_post_page"
		case newPosts = "new_posts"
	}
}

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
	let pageCount: Int64
	let page: Int64
	
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

// GET /api/v2/forums
struct TwitarrV2GetForumsResponse: Codable {
	let status: String
	let forumThreads: [TwitarrV2ForumThreadMeta]
	let nextPage: Int64?
	let prevPage: Int64?
	let threadCount: Int64
	let page: Int64
	let pageCount: Int64
	
	enum CodingKeys: String, CodingKey {
		case status, page
		case forumThreads = "forum_threads"
		case nextPage =  "next_page"
		case prevPage = "prev_page"
		case threadCount = "thread_count"
		case pageCount = "page_count"
	}
}

// POST /api/v2/forums
struct TwitarrV2PostNewForum: Codable {
	let subject: String
	let text: String
	let photos: [String]
	let asMod: Bool
	let asAdmin: Bool
	
	enum CodingKeys: String, CodingKey {
		case subject, text, photos
		case asMod = "as_mod"
		case asAdmin = "as_admin"
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
