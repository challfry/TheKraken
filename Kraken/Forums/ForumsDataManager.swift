//
//  ForumsDataManager.swift
//  Kraken
//
//  Created by Chall Fry on 11/26/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit

@objc(ForumThread) public class ForumThread: KrakenManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var subject: String
    @NSManaged public var locked: Bool
    @NSManaged public var sticky: Bool
    @NSManaged public var createTime: Date
    @NSManaged public var lastPostTime: Date?
    @NSManaged public var postCount: Int64			// == posts.count iff we've downloaded all the posts.
    @NSManaged public var lastUpdateTime: Date?		// Last time we loaded *posts* on this thread. ThreadMeta doesn't count.

// Relations
    @NSManaged public var creator: KrakenUser
    @NSManaged public var lastPoster: KrakenUser
    @NSManaged public var readCount: Set<ForumReadCount>
    @NSManaged public var category: ForumCategory
    @NSManaged public var posts: Set<ForumPost>
    @NSManaged public var event: Event?				// Only for event forums

    // Sets reasonable default values for properties that could conceivably not change during buildFromV2 methods.
	public override func awakeFromInsert() {
		super.awakeFromInsert()
		id = UUID()
		createTime = Date.distantPast
		locked = false
		sticky = false
		subject = ""
	}
	
    // Only call this within a CoreData perform block. ForumListData doesn't include data about posts.
    // Requires: Users for creators of all forums.
	func buildFromV3(context: NSManagedObjectContext, category: ForumCategory, v3Object: TwitarrV3ForumListData) {
		TestAndUpdate(\.id, v3Object.forumID)
		TestAndUpdate(\.subject, v3Object.title)
		TestAndUpdate(\.locked, v3Object.isLocked)
		TestAndUpdate(\.postCount, v3Object.postCount)
		TestAndUpdate(\.createTime, v3Object.createdAt)
		TestAndUpdate(\.lastPostTime, v3Object.lastPostAt)

		if self.category != category {
			self.category = category
		}
	
		let userDict: [UUID : KrakenUser ] = context.userInfo.object(forKey: "Users") as! [UUID : KrakenUser] 
		if let krakenUser = userDict[v3Object.creator.userID] {
			if value(forKey: "creator") == nil || krakenUser.userID != creator.userID {
				creator = krakenUser
			}
		}
		
		// Not parsed: isFavorite, 
		// Not yet parsed
//		TestAndUpdate(\.favorite, v3Object.isFavorite)
	}
	
	// TwitarrV3ForumData does have data about posts in the thread.
	func buildFromV3(context: NSManagedObjectContext, category: ForumCategory?, v3ForumData: TwitarrV3ForumData) {
		if let cat = category, self.category.objectID != cat.objectID {
			self.category = cat
		}
		if self.id != v3ForumData.forumID {
			self.id = v3ForumData.forumID
		}
		
		TestAndUpdate(\.subject, v3ForumData.title)
		TestAndUpdate(\.locked, v3ForumData.isLocked)
//		TestAndUpdate(\.postCount, v3Object.posts.count)

		// Make sure all the post authors get added to our User table
		// Note that this also sets "Users" on our context's userInfo.
		var userArray = v3ForumData.posts.map { $0.author }
		userArray.append(v3ForumData.creator)
		UserManager.shared.update(users: userArray, inContext: context)
		
		// Creator
		let userDict: [UUID : KrakenUser ] = context.userInfo.object(forKey: "Users") as! [UUID : KrakenUser] 
		if let krakenUser = userDict[v3ForumData.creator.userID] {
			if value(forKey: "creator") == nil || krakenUser.userID != creator.userID {
				creator = krakenUser
			}
		}

		// Get all the photos attached to all the posts into a Photos set.
		let allPhotoFilenames = v3ForumData.posts.compactMap { $0.image }
		ImageManager.shared.updateV3(imageFilenames: allPhotoFilenames, inContext: context)

		// Finally, build all the posts.
		let cdPostsDict = Dictionary(posts.map { ($0.id, $0) }, uniquingKeysWith: { (first,_) in first })
		for post in v3ForumData.posts {
			let cdPost = cdPostsDict[post.postID] ?? ForumPost(context: context)
			cdPost.buildFromV3(context: context, v3Object: post, thread: self)
		}

		// Not handled: isFavorite
	}
    
    // Only call this within a CoreData perform block.
//	func buildFromV2Meta(context: NSManagedObjectContext, v2Object: TwitarrV2ForumThreadMeta) {
//		TestAndUpdate(\.id, v2Object.id)
//		TestAndUpdate(\.subject, v2Object.subject)
//		TestAndUpdate(\.lastPostTime, v2Object.timestamp)
//		TestAndUpdate(\.sticky, v2Object.sticky)
//		TestAndUpdate(\.locked, v2Object.locked)
//		TestAndUpdate(\.postCount, v2Object.posts)
//		
//		if lastPoster.username != v2Object.lastPostAuthor.username {
//			let userPool: [String : KrakenUser ] = context.userInfo.object(forKey: "Users") as! [String : KrakenUser] 
//			if let cdAuthor = userPool[v2Object.lastPostAuthor.username] {
//				lastPoster = cdAuthor
//			}
//		}
//		
//		// Set up the associated ForumReadCount object if we have a postCount to update
//		if let newPostCount = v2Object.count, let readCountObject = getReadCountObject(context: context) {
//			readCountObject.numPostsRead = postCount - newPostCount
//		}
//		
//	}
//    
//	func buildFromV2(context: NSManagedObjectContext, v2Object: TwitarrV2ForumThread) {
//		TestAndUpdate(\.id, v2Object.id)
//		TestAndUpdate(\.subject, v2Object.subject)
//		TestAndUpdate(\.sticky, v2Object.sticky)
//		TestAndUpdate(\.locked, v2Object.locked)
//		TestAndUpdate(\.postCount, v2Object.postCount)
//	
//		for post in v2Object.posts {
//			var existingPost: ForumPost
//			if let optionalPost = posts.first(where: { $0.id == post.id }) {
//				existingPost = optionalPost
//			}
//			else {
//				existingPost = ForumPost(context: context)
//				posts.insert(existingPost)
//			}
//			existingPost.buildFromV2(context: context, v2Object: post, thread: self)
//		}
//		lastUpdateTime = Date()
//		
//		// So, ForumThreadMeta has a value for the timestamp of the last post in the thread.
//		// ForumThread does not (directly), but it has posts from the thread. The posts array may
//		// or may not include the last post in the thread.
//		// Good news is that, if after parsing the posts, postCount == posts.count, we have all the posts and
//		// (fingers crossed) posts.last.timeStamp == (the value ForumThreadMeta would give for lastPostTime).
//		if postCount > 0, postCount == posts.count {
//			let lastPostPostTime = posts.reduce(0) { max($0, $1.timestamp)  }
//			TestAndUpdate(\.lastPostTime, lastPostPostTime)
//		}
//		
//		internalUpdateLastReadTime(context: context, toNewTime: v2Object.latestRead)
//	}
	
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

// In all cases, ForumThread loads have a 'refresh time' that is user-controlled and starts out as viewDidAppear time.
// At that time we load the first N threads for whatever filter/sort is in use. After that, as the user scrolls down we ask
// for more threads as necessary, anchored at the same refresh time as the initial call. There's a separate user action that
// can 'refresh', which resets the refresh time and loads from 0 again.
@objc class ForumFilterPack: NSObject {
	enum SortType {
		case update, create, alpha
	}

	// These determine the 'filter equality' for filter packs. 2 views showing the same categtory with the same
	// sort should use the same FilterPack, meaning they share a refresh time and # of threads loaded.
	let category: ForumCategory
	let sort: SortType
	
	// Used by UI to show time of last refresh--defined as a successful network load of threads from offset 0.
	// This is the 'anchor time'.
	@objc dynamic var refreshTime: Date = Date()
		
	// This is the index of the oldest thread we're loaded this refresh, counting from the newest thread.
	var highestLoadedIndex: Int = 0
	var highestLoadingIndex: Int = 0
	
	init(_ cat: ForumCategory, sort: SortType) {
		category = cat
		self.sort = sort
	}
	
	func updateLoadIndex(requestIndex: Int, numThreadsInResponse: Int) {
		highestLoadedIndex = max(highestLoadedIndex, requestIndex + numThreadsInResponse)
		highestLoadingIndex = highestLoadedIndex
	}
	
	// We attemtped to load more threads, but failed. We're therefore no longer loading the threads--back it out.
	func threadLoadError() {
		highestLoadingIndex = highestLoadedIndex
	}
	
	// This fn could be expanded to estimate the 'freshness' of the values around the requested index, and 
	// initiate reloads. This probably requires adding a way to track recent network calls.
	func loadNeeded(for index: Int) -> Int? {
		if index + 10 > highestLoadingIndex {
			return highestLoadingIndex
		}
		return nil
	}
	
	func refreshNow() {
		refreshTime = Date()
		highestLoadedIndex = 0
		highestLoadingIndex = 0
	}
	
}


@objc class ForumsDataManager: NSObject {
	static let shared = ForumsDataManager()
	private let coreData = LocalCoreData.shared
	
	// Used by UI to show loading cell and error cell.
	@objc dynamic var lastError : ServerError?
	@objc dynamic var isPerformingLoad: Bool = false
		
	var filterPacks: [ForumFilterPack] = []

// MARK: Methods
	@discardableResult
	func checkLoadForumTheads(for category: ForumCategory, sort: ForumFilterPack.SortType, userViewingIndex: Int) -> ForumFilterPack? {
		// Clean out old filters. They may still be retained by views.
		filterPacks.removeAll { $0.refreshTime + 60 * 10 < Date() }
	
		// Find FilterPack
		var filterPack = filterPacks.first { $0.category.id == category.id && $0.sort == sort }
		if filterPack == nil {
			filterPack = ForumFilterPack(category, sort: sort)
			filterPacks.append(filterPack!)	
		}
		if let filter = filterPack, let loadIndex = filter.loadNeeded(for: userViewingIndex) {
			loadForumThreads(for: filter, startIndex: loadIndex)
		}
		return filterPack
	}
	
	// This forces a reload from index 0, and resets the anchor time.
	func forceRefreshForumThreads(for category: ForumCategory, sort: ForumFilterPack.SortType) -> ForumFilterPack? {
		var filterPack = filterPacks.first { $0.category.id == category.id && $0.sort == sort }
		if filterPack == nil {
			filterPack = ForumFilterPack(category, sort: sort)
			filterPacks.append(filterPack!)	
		}
		if let filter = filterPack {
			filter.refreshNow()
			loadForumThreads(for: filter, startIndex: 0)
		}
		return filterPack
	}
		
	func loadForumThreads(for filterPack: ForumFilterPack, startIndex: Int) {
		isPerformingLoad = true
				
		var loadStartPoint = 0
		var queryParams: [URLQueryItem] = []
		if filterPack.highestLoadingIndex > 0 {
			queryParams.append(URLQueryItem(name:"beforedate", value: "\(filterPack.refreshTime)"))
			queryParams.append(URLQueryItem(name:"start", value: "\(startIndex)"))
			loadStartPoint = startIndex
		}
		queryParams.append(URLQueryItem(name:"limit", value: "50"))
		
		filterPack.highestLoadingIndex = loadStartPoint + 50

		let path = "/api/v3/forum/categories/\(filterPack.category.id)"
		var request = NetworkGovernor.buildTwittarV2Request(withPath:path, query: queryParams)
		NetworkGovernor.addUserCredential(to: &request)
		NetworkGovernor.shared.queue(request) { (package: NetworkResponse) in
			if let error = NetworkGovernor.shared.parseServerError(package) {
				self.lastError = error
				filterPack.threadLoadError()
			}
			else if let data = package.data {
				self.lastError = nil
			//	print (String(data: data, encoding: .utf8))
				do {
					let response = try Settings.v3Decoder.decode([TwitarrV3ForumListData].self, from: data)
					self.ingestForumThreads(for: filterPack.category, from: response)
					filterPack.updateLoadIndex(requestIndex: loadStartPoint, numThreadsInResponse: response.count) 
				}
				catch {
					NetworkLog.error("Failure parsing Forums response.", ["Error" : error, "url" : request.url as Any])
				}
			}
			else {
				// Network error
				filterPack.threadLoadError()
			}
			self.isPerformingLoad = false
		}
	}
		
	// Takes an array of threads from a server response and merges them into CoreData's store.
	// Note: Probably only ever called from its network response handler. Broken out this way to make it easier to 
	// see what ops are performed within the CD context.
	func ingestForumThreads(for category: ForumCategory, from threads: [TwitarrV3ForumListData]) {
		LocalCoreData.shared.performNetworkParsing { context in
			context.pushOpErrorExplanation("Failed to parse Forum threads and add to Core Data.")
			
			let catInContext = try context.existingObject(with: category.objectID) as! ForumCategory

			// Make sure all the users mentioned as lastPosters get added to our User table
			// Note that this also sets "Users" on our context's userInfo.
			let forumCreators = threads.map { $0.creator }
			UserManager.shared.update(users: forumCreators, inContext: context)
			
			// Fetch threads from CD that match the ids in the given theads
			let allThreadIDs = threads.map { $0.forumID }
			let request = NSFetchRequest<ForumThread>(entityName: "ForumThread")
			request.predicate = NSPredicate(format: "id IN %@", allThreadIDs)
			let cdThreads = try request.execute()
			let cdThreadsDict = Dictionary(cdThreads.map { ($0.id, $0) }, uniquingKeysWith: { (first,_) in first })

			for forumThread in threads {
				let cdThread = cdThreadsDict[forumThread.forumID] ?? ForumThread(context: context)
				cdThread.buildFromV3(context: context, category: catInContext, v3Object: forumThread)
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

// MARK: - V3 API Decoding

// GET /api/v3/forum/catgories/ID
struct TwitarrV3ForumListData: Codable {
    /// The forum's ID.
    var forumID: UUID
    /// The forum's creator.
	var creator: TwitarrV3UserHeader
    /// The forum's title.
    var title: String
    /// The number of posts in the forum.
    var postCount: Int64
    /// Time forum was created.
    var createdAt: Date
    /// Timestamp of most recent post. Needs to be optional because admin forums may be empty.
    var lastPostAt: Date?
    /// Whether the forum is in read-only state.
    var isLocked: Bool
    /// Whether user has favorited forum.
    var isFavorite: Bool
}
