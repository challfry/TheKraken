//
//  ForumsDataManager.swift
//  Kraken
//
//  Created by Chall Fry on 11/26/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit
import CoreData

@objc(ForumThread) public class ForumThread: KrakenManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var subject: String
    @NSManaged public var locked: Bool
    @NSManaged public var sticky: Bool				// TRUE if this forum should be displayed before non-sticky forums
    @NSManaged public var createTime: Date
    @NSManaged public var lastPostTime: Date?
    @NSManaged public var postCount: Int64			// == posts.count iff we've downloaded all the posts.
    @NSManaged public var lastUpdateTime: Date?		// Last time we loaded *posts* on this thread. ThreadMeta doesn't count.

// Relations
    @NSManaged public var category: ForumCategory
    @NSManaged public var creator: KrakenUser
    @NSManaged public var posts: Set<ForumPost>
    @NSManaged public var lastPoster: KrakenUser?
    @NSManaged public var readCount: Set<ForumReadCount>
    @NSManaged public var scheduleEvent: Event?				// Only for event forums

    @NSManaged public var newPostOps: Set<PostOpForumPost>			// New posts in forum, awaiting server
    @NSManaged public var postOpFavorite: Set<PostOpForumFavorite>		// Favorite/unfavorite op

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
		TestAndUpdate(\.sticky, v3Object.isPinned == true)

		if self.category != category {
			self.category = category
		}
	
		let userDict: [UUID : KrakenUser ] = context.userInfo.object(forKey: "Users") as! [UUID : KrakenUser] 
		if let krakenUser = userDict[v3Object.creator.userID] {
			if value(forKey: "creator") == nil || krakenUser.userID != creator.userID {
				creator = krakenUser
			}
		}
		if let lastPosterUserID = v3Object.lastPoster?.userID,  let krakenUser = userDict[lastPosterUserID] {
			if krakenUser.userID != lastPoster?.userID {
				lastPoster = krakenUser
			}
		}
		
		// Set per-user forum values in the Read Count object.
		if let rco = getReadCountObject(context: context) {
			rco.buildFromV3(context: context, v3Object: v3Object)
		}
	}
	
	// TwitarrV3ForumData does have data about posts in the thread.
	func buildFromV3(context: NSManagedObjectContext, category: ForumCategory, v3ForumData: TwitarrV3ForumData) {
		if primitiveValue(forKey: "category") == nil || self.category.id != category.id {
			self.category = category
		}
		if self.id != v3ForumData.forumID {
			self.id = v3ForumData.forumID
		}
		
		TestAndUpdate(\.subject, v3ForumData.title)
		TestAndUpdate(\.locked, v3ForumData.isLocked)
		TestAndUpdate(\.sticky, v3ForumData.isPinned == true)
		TestAndUpdate(\.postCount, Int64(v3ForumData.paginator.total))

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
		let allPhotoFilenames = v3ForumData.posts.compactMap { $0.images }.joined()
		ImageManager.shared.updateV3(imageFilenames: Array(allPhotoFilenames), inContext: context)

		// Finally, build all the posts.
		let cdPostsDict = Dictionary(posts.map { ($0.id, $0) }, uniquingKeysWith: { (first,_) in first })
		for post in v3ForumData.posts {
			let cdPost = cdPostsDict[post.postID] ?? ForumPost(context: context)
			cdPost.buildFromV3(context: context, v3Object: post, thread: self)
		}

		// Set per-user forum values in the Read Count object.
		if let rco = getReadCountObject(context: context) {
			rco.buildFromV3(context: context, v3ForumData: v3ForumData)
		}
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
			readCountObject?.isMuted = false
		}
		return readCountObject
	}
	
	// External method, called by the UI to update the view time of a forum. Call this just as the user finishes
	// looking at the forum.
	func updateLastReadTime(highestViewedIndex: Int64) {
		LocalCoreData.shared.performNetworkParsing { context in
			context.pushOpErrorExplanation("Failed to update forum read time.")
			if let selfInContext = try context.existingObject(with: self.objectID) as? ForumThread,
					let rco = selfInContext.getReadCountObject(context: context) {
				rco.lastReadTime = Date()
				rco.numPostsRead = highestViewedIndex
			}
		}		
	}
	
	// Always returns nil if nobody's logged in.
	func getPendingFavorite() -> PostOpForumFavorite? {
		if let userID = CurrentUser.shared.loggedInUser?.userID, let fav = postOpFavorite.first(where: { op in
				return op.author.userID == userID }) {
			return fav
		}
		return nil
	}

	func setForumFavoriteStatus(to newValue: Bool) {
		LocalCoreData.shared.performLocalCoreDataChange { context, currentUser in
			context.pushOpErrorExplanation("Failed to update forum favorite status.")
			guard let thisForum = context.object(with: self.objectID) as? ForumThread else { return }
			
			// Check for existing op 
			let op = thisForum.getPendingFavorite() ?? PostOpForumFavorite(context: context)
			op.operationState = .readyToSend
			op.favorite = newValue
			op.sourceForum = thisForum
		}		
	}
}

// Tracks the number of posts that the given user has read in the given thread.
@objc(ForumReadCount) public class ForumReadCount: KrakenManagedObject {
    @NSManaged public var numPostsRead: Int64		// How many posts this user has read in this thread.
    												// May not be == to the number of posts we've loaded.

	@NSManaged public var lastReadTime: Date?		// The last time this user looked at this forum on this device.
													// Not saved to server.
	
	@NSManaged public var isFavorite: Bool 			// If TRUE, the user has favorited this forum.
	@NSManaged public var isMuted: Bool 			// If TRUE, the user has muted this forum.

	@NSManaged public var userPosted: Bool			// TRUE iff .user has authored a post in .forumThread.

    @NSManaged public var forumThread: ForumThread
    @NSManaged public var user: KrakenUser
    
    // Sets reasonable default values for properties that could conceivably not change during buildFromV2 methods.
	public override func awakeFromInsert() {
		super.awakeFromInsert()
		numPostsRead = 0
		isFavorite = false
		isMuted = false
		userPosted = false
	}
	
	// Only call this within a CoreData perform block. ForumListData doesn't include data about posts.
	func buildFromV3(context: NSManagedObjectContext, v3Object: TwitarrV3ForumListData) {
		TestAndUpdate(\.isFavorite, v3Object.isFavorite)
		TestAndUpdate(\.isMuted, v3Object.isMuted)
		// Kraken tracks whether each post has been scrolled into view while Swiftarr only tracks each page load--
		// therefore loading page 1 of a forum on the web marks the first 50 posts as read. So, consider our count
		// better if the server count is less than 1 page more than the current count.
		if v3Object.readCount > numPostsRead + 50 {
			numPostsRead = v3Object.readCount
		}
	}
	
	// Only call this within a CoreData perform block. ForumListData doesn't include data about posts.
	func buildFromV3(context: NSManagedObjectContext, v3ForumData: TwitarrV3ForumData) {
		TestAndUpdate(\.isFavorite, v3ForumData.isFavorite)
		TestAndUpdate(\.isMuted, v3ForumData.isMuted)
		if let currentUser = CurrentUser.shared.getLoggedInUser(in: context), 
				v3ForumData.posts.contains(where: { $0.author.userID == currentUser.userID }) {
			// Because we get paginated data on posts, don't set userPosted to false
			TestAndUpdate(\.userPosted, true)
		}
	}
}

// In all cases, ForumThread loads have a 'refresh time' that is user-controlled and starts out as viewDidAppear time.
// At that time we load the first N threads for whatever filter/sort is in use. After that, as the user scrolls down we ask
// for more threads as necessary, anchored at the same refresh time as the initial call. There's a separate user action that
// can 'refresh', which resets the refresh time and loads from 0 again.
@objc class ForumFilterPack: NSObject {
	enum SortType {
		case update, create, alpha, event
	}
	
	enum FilterType {
		case favorite
		case recent
		case userCreated
		case userPosted
		case muted
	}

	// These determine the 'filter equality' for filter packs. 2 views showing the same categtory with the same
	// sort should use the same FilterPack, meaning they share a refresh time and # of threads loaded.
	let category: ForumCategory?
	let sort: SortType?
	let filter: FilterType?
	let search: String?
	
	// Used by UI to show time of last refresh--defined as a successful network load of threads from offset 0.
	// This is the 'anchor time'.
	@objc dynamic var refreshTime: Date = Date()
	
	var lastLoadTime: Date = Date()
		
	// This is the highest index we've actually loaded in this filterpack. If we ask for [start=50 & limit = 50] and get
	// 2 results back, this is set to 52.
	var highestLoadedIndex: Int = 0	
	// This is the highest index we've attempted to load. If we ask for [start=50 & limit = 50] and get
	// 2 results back, this is set to 100
	var highestLoadingIndex: Int = 0
	
	init(_ cat: ForumCategory, sort: SortType? = nil) {
		category = cat
		self.sort = sort
		self.filter = nil
		self.search = nil
	}
	
	init(search: String, sort: SortType = .update) {
		self.search = search
		self.sort = sort == .event ? .update : sort
		self.category = nil
		self.filter = nil
	}
	
	init(filter: FilterType) {
		self.filter = filter
		self.sort = nil
		self.category = nil
		self.search = nil
		lastLoadTime = Date()
	}
	
	func updateLoadIndex(requestIndex: Int, loadRequestSize: Int, numThreadsInResponse: Int) {
		highestLoadedIndex = max(highestLoadedIndex, requestIndex + numThreadsInResponse)
		lastLoadTime = Date()
	}
	
	// We attemtped to load more threads, but failed. We're therefore no longer loading the threads--back it out.
	func threadLoadError() {
		highestLoadingIndex = highestLoadedIndex
	}
	
	// This fn could be expanded to estimate the 'freshness' of the values around the requested index, and 
	// initiate reloads. This probably requires adding a way to track recent network calls.
	func loadNeeded(for index: Int) -> Int? {
//		print("LoadNeeded index: \(index), loaded: \(highestLoadedIndex), requested: \(highestLoadingIndex)")
		if index + 10 > highestLoadedIndex && index + 10 > highestLoadingIndex {
			return highestLoadedIndex
		}
		if index + 10 > highestLoadedIndex && lastLoadTime < Date() - 30 {
			return highestLoadedIndex
		}
		return nil
	}
	
	func refreshNow() {
		refreshTime = Date()
		lastLoadTime = Date()
		highestLoadedIndex = 0
		highestLoadingIndex = 0
	}
	
// Predicates
	func predicate() -> NSPredicate {
		if let cat = category {
			return NSPredicate(format: "%K == %@", #keyPath(ForumThread.category.id), cat.id as CVarArg)
		}
		else if let searchStr = search {
			return NSPredicate(format: "%K CONTAINS[cd] %@", #keyPath(ForumThread.subject), searchStr)
		}
		else if let filter = filter {
			switch filter {
				case .favorite:	return NSPredicate(value: false)
				case .recent: return NSPredicate(value: false)
				case .userCreated: 
					if let userID = CurrentUser.shared.loggedInUser?.userID {
						return NSPredicate(format: "creator.userID == %@", userID as CVarArg)
					}
				case .userPosted: return NSPredicate(value: false)
				case .muted: return NSPredicate(value: false)
			}
		}
		return NSPredicate(value: false)
	}
	
	func readCountPredicate() -> NSPredicate {
		if category != nil || search != nil {
			return NSPredicate(value: false)
		}
		else if let filter = filter {
			switch filter {
				case .favorite:	return NSPredicate(format: "isFavorite == TRUE")
				case .recent: return NSPredicate(format: "lastReadTime != NULL")
				case .userCreated: return NSPredicate(value: false)
				case .userPosted: return NSPredicate(format: "userPosted == TRUE")
				case .muted: return NSPredicate(format: "isMuted == TRUE")
			}
		}
		return NSPredicate(value: false)
	}
	
	func sortDescriptors() -> [NSSortDescriptor] {
		if let sortType = sort {
			switch sortType {
			case .update: 	
				return [NSSortDescriptor(key: "sticky", ascending: false),
						NSSortDescriptor(key: "lastPostTime", ascending: false)]
			case .create:
				return [NSSortDescriptor(key: "sticky", ascending: false),
						NSSortDescriptor(key: "createTime", ascending: false)]
			case .alpha:
				return [NSSortDescriptor(key: "subject", ascending: true)]
			case .event:
				return [NSSortDescriptor(key: "event.startTime", ascending: true)]
			}
		}
		else if let cat = category {
			if cat.isEventCategory {
				return [NSSortDescriptor(key: "sticky", ascending: false),
						NSSortDescriptor(key: "scheduleEvent.startTime", ascending: true),
						NSSortDescriptor(key: "subject", ascending: true)]
			}
			return [NSSortDescriptor(key: "sticky", ascending: false),
					NSSortDescriptor(key: "lastPostTime", ascending: false)]
		}
		else if let _ = search {
			return [NSSortDescriptor(key: "lastPostTime", ascending: false)]
		}
		else if let _ = self.filter {
			return [NSSortDescriptor(key: "lastPostTime", ascending: false)]
		}
		return [NSSortDescriptor(key: "lastPostTime", ascending: false)]
	}
	
	func readCountSortDescriptors() -> [NSSortDescriptor] {
		if let sortType = sort {
			switch sortType {
			case .update: 	
				return [NSSortDescriptor(key: "forumThread.sticky", ascending: false),
						NSSortDescriptor(key: "forumThread.lastPostTime", ascending: false)]
			case .create:
				return [NSSortDescriptor(key: "forumThread.sticky", ascending: false),
						NSSortDescriptor(key: "forumThread.createTime", ascending: false)]
			case .alpha:
				return [NSSortDescriptor(key: "forumThread.subject", ascending: true)]
			case .event:
				return [NSSortDescriptor(key: "forumThread.event.startTime", ascending: true)]
			}
		}
		else if let _ = category {
			return [NSSortDescriptor(key: "forumThread.sticky", ascending: false),
				NSSortDescriptor(key: "forumThread.lastPostTime", ascending: false)]
		}
		else if let _ = search {
			return [NSSortDescriptor(key: "forumThread.lastPostTime", ascending: false)]
		}
		else if let filter = self.filter {
			switch filter {
				case .favorite: return [NSSortDescriptor(key: "forumThread.lastPostTime", ascending: false)]
				case .recent: return [NSSortDescriptor(key: "lastReadTime", ascending: false)]
				case .userCreated: return [NSSortDescriptor(key: "forumThread.createTime", ascending: false)]
				case .userPosted: return [NSSortDescriptor(key: "forumThread.lastPostTime", ascending: false)]
				case .muted: return [NSSortDescriptor(key: "forumThread.lastPostTime", ascending: false)]
			}
		}
		return [NSSortDescriptor(key: "forumThread.lastPostTime", ascending: false)]
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
	func getFilterPack(for category: ForumCategory, sort: ForumFilterPack.SortType? = nil) -> ForumFilterPack {
		if let existingPack = filterPacks.first(where: { $0.category == category && $0.sort == sort }) {
			return existingPack
		}
		let newPack = ForumFilterPack(category, sort: sort)
		filterPacks.append(newPack)
		return newPack
	}

	func getFilterPack(search: String, sort: ForumFilterPack.SortType = .update) -> ForumFilterPack {
		if let existingPack = filterPacks.first(where: { $0.search == search && $0.sort == sort }) {
			return existingPack
		}
		let newPack = ForumFilterPack(search: search, sort: .update)
		filterPacks.append(newPack)
		return newPack
	}

	func getFilterPack(filter: ForumFilterPack.FilterType, sort: ForumFilterPack.SortType = .update) -> ForumFilterPack {
		if let existingPack = filterPacks.first(where: { $0.filter == filter && $0.sort == sort }) {
			return existingPack
		}
		let newPack = ForumFilterPack(filter: filter)
		filterPacks.append(newPack)
		return newPack
	}

	func checkLoadForumTheads(for filterPack: ForumFilterPack, userViewingIndex: Int) {
		// Clean out old filters. They may still be retained by views.
		filterPacks.removeAll { $0.refreshTime + 60 * 10 < Date() }
	
		if let loadIndex = filterPack.loadNeeded(for: userViewingIndex) {
			loadForumThreads(for: filterPack, startIndex: loadIndex)
		}
	}
	
	// This forces a reload from index 0, and resets the anchor time.
	func forceRefreshForumThreads(for filterPack: ForumFilterPack) {
		filterPack.refreshNow()
		loadForumThreads(for: filterPack, startIndex: 0)
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

		if let cat = filterPack.category {
			loadThreadsInCategory(for: filterPack, category: cat, loadStart: loadStartPoint, queryParams: queryParams)
		}
		else  {
			loadThreadsForSearch(for: filterPack, queryParams: queryParams)
		}
	}
	
	func loadThreadsInCategory(for filterPack: ForumFilterPack, category: ForumCategory, loadStart: Int, queryParams: [URLQueryItem]) {
		let path = "/api/v3/forum/categories/\(category.id)"
		var request = NetworkGovernor.buildTwittarRequest(withPath:path, query: queryParams)
		NetworkGovernor.addUserCredential(to: &request)
		NetworkGovernor.shared.queue(request) { (package: NetworkResponse) in
			if let error = package.serverError {
				self.lastError = error
				filterPack.threadLoadError()
			}
			else if let data = package.data {
				self.lastError = nil
			//	print (String(data: data, encoding: .utf8))
				do {
					let response = try Settings.v3Decoder.decode(TwitarrV3CategoryData.self, from: data)
					if let threads = response.forumThreads {
						self.ingestForumThreads(for: category, from: threads)
						filterPack.updateLoadIndex(requestIndex: loadStart, loadRequestSize: 50, numThreadsInResponse: threads.count) 
					}
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
	
	// All the calls that return a ForumSearchData
	func loadThreadsForSearch(for filterPack: ForumFilterPack, queryParams: [URLQueryItem]) {
		var queryParams = queryParams
		var path: String
		if let searchStr = filterPack.search {
			queryParams.append(URLQueryItem(name: "search", value: searchStr))
			path = "/api/v3/forum/search/"
		}
		else if let filter = filterPack.filter {
			switch filter {
				case .favorite: path = "/api/v3/forum/favorites/"
				case .recent: path = "/api/v3/forum/recent/"
				case .userCreated: path = "/api/v3/forum/owner/"
				case .userPosted: 	// No API call for this
					isPerformingLoad = false 
					return
				case .muted: path = "/api/v3/forum/mutes/"
			}
		}
		else {
			isPerformingLoad = false 
			return
		}
		var request = NetworkGovernor.buildTwittarRequest(withPath: path, query: queryParams)
		NetworkGovernor.addUserCredential(to: &request)
		NetworkGovernor.shared.queue(request) { (package: NetworkResponse) in
			if let error = package.serverError {
				self.lastError = error
				filterPack.threadLoadError()
			}
			else if let data = package.data {
				self.lastError = nil
			//	print (String(data: data, encoding: .utf8))
				do {
					let response = try Settings.v3Decoder.decode(TwitarrV3ForumSearchData.self, from: data)
					self.ingestForumThreads(for: nil, from: response.forumThreads)
					filterPack.updateLoadIndex(requestIndex: response.paginator.start, loadRequestSize: 50,
							numThreadsInResponse: response.forumThreads.count) 
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
	func ingestForumThreads(for category: ForumCategory?, from threads: [TwitarrV3ForumListData]) {
		LocalCoreData.shared.performNetworkParsing { context in
			context.pushOpErrorExplanation("Failed to parse Forum threads and add to Core Data.")

			// Make sure all the users mentioned as lastPosters get added to our User table
			// Note that this also sets "Users" on our context's userInfo.
			var forumCreators = threads.map { $0.creator }
			forumCreators.append(contentsOf: threads.compactMap { $0.lastPoster } )
			UserManager.shared.update(users: forumCreators, inContext: context)
			
			// Fetch threads from CD that match the ids in the given theads
			let allThreadIDs = threads.map { $0.forumID }
			let request = NSFetchRequest<ForumThread>(entityName: "ForumThread")
			request.predicate = NSPredicate(format: "id IN %@", allThreadIDs)
			let cdThreads = try request.execute()
			let cdThreadsDict = Dictionary(cdThreads.map { ($0.id, $0) }, uniquingKeysWith: { (first,_) in first })

			// Get all the categories, or just the one if we know all the threads are in this cat.
			var cats: [ForumCategory]
			if let cat = category {
				let catInContext = try context.existingObject(with: cat.objectID) as! ForumCategory
				cats = [catInContext]
			}
			else {
				let request = NSFetchRequest<ForumCategory>(entityName: "ForumCategory")
				cats = try request.execute()
			}
			
			for forumThread in threads {
				// NOTE: If we can't get the category, we don't build the forum object, we throw it away.
				if let catInContext = cats.first(where: { $0.id == forumThread.categoryID }) {
					let cdThread = cdThreadsDict[forumThread.forumID] ?? ForumThread(context: context)
					cdThread.buildFromV3(context: context, category: catInContext, v3Object: forumThread)
				}
			}
		}
	}
}

// MARK: - V3 API Decoding

// GET /api/v3/forum/catgories/ID
struct TwitarrV3ForumListData: Codable {
	/// The forum's ID.
	var forumID: UUID
	/// The ID of the forum's containing Category..
	var categoryID: UUID
	/// The forum's creator.
	var creator: TwitarrV3UserHeader
	/// The forum's title.
	var title: String
	/// The number of posts in the forum.
	var postCount: Int64
	/// The number of posts the user has read.  Specifically, this will be the number of posts the forum contained the last time the user called a fn that returned a `ForumData`.
	/// Blocked and muted posts are included in this number, but not returned in the array of posts.
	var readCount: Int64
	/// Time forum was created.
	var createdAt: Date
	/// The last user to post to the forum. Nil if there are no posts in the forum.
	var lastPoster: TwitarrV3UserHeader?
	/// Timestamp of most recent post. Needs to be optional because admin forums may be empty.
	var lastPostAt: Date?
	/// Whether the forum is in read-only state.
	var isLocked: Bool
	/// Whether user has favorited forum.
	var isFavorite: Bool
	/// Whether user has muted the forum.
	var isMuted: Bool
	/// If this forum is for an Event on the schedule, the start time of the event.
	var eventTime: Date?
	/// If this forum is for an Event on the schedule, the timezone that the ship is going to be in when the event occurs. Delivered as an abbreviation e.g. "EST".
	var timeZone: String?
	/// If this forum is for an Event on the schedule, the timezone ID that the ship is going to be in when the event occurs. Example: "America/New_York".
	var timeZoneID: String?
	/// If this forum is for an Event on the schedule, the ID of the event.
	var eventID: UUID?
	/// If this forum is pinned or not.
	var isPinned: Bool?
}

 struct TwitarrV3ForumSearchData: Codable {
	/// Paginates the list of forum threads. `paginator.total` is the total number of forums that match the request parameters.
	/// `limit` and `start` define a slice of the total results set being returned in `forumThreads`.
	var paginator: TwitarrV3Paginator
	/// A slice of the set of forum threads that match the request parameters.
	var forumThreads: [TwitarrV3ForumListData]
}
