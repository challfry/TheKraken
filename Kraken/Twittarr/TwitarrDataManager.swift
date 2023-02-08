//
//  TwitarrDataManager.swift
//  Kraken
//
//  Created by Chall Fry on 3/22/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import Foundation
import CoreData
import UIKit

// Our model object for tweets. Why not just use the V2API tweet object? V3 is coming, and this way we 
// have a model object that doesn't have to exactly match a service response.
@objc(TwitarrPost) public class TwitarrPost: KrakenManagedObject {
    @NSManaged public var id: Int64
    @NSManaged public var locked: Bool
    @NSManaged public var reactions: Set<Reaction>
    @NSManaged public var numReactions: Int64			// V3 returns this rollup, separate from individual reactions.
    @NSManaged public var text: String
    @NSManaged public var author: KrakenUser
    @NSManaged public var replyGroup: Int64				// -1 if no replyGroup
//    @NSManaged public var parent: TwitarrPost?
//    @NSManaged public var children: Set<TwitarrPost>?
	@NSManaged public var createdAt: Date
    @NSManaged public var photoDetails: NSMutableOrderedSet		// Set of PhotoDetails
    
    	// Kraken Operation relationships to other data
    @NSManaged public var opsWithThisParent: Set<PostOpTweet>?
    @NSManaged public var opsDeletingThisTweet: Set<PostOpTweetDelete>?	// Still needs to be to-many. Sigh.
    @NSManaged public var opsEditingThisTweet: PostOpTweet?		// I *think* this one can be to-one?
    @NSManaged public var reactionOps: NSMutableSet?

		// Properties built from reactions
	@objc dynamic public var reactionDict: NSMutableDictionary?			// the reactions set, keyed by reaction.word
	@objc dynamic public var likeCount: Int32 = 0
	@objc dynamic public var loveCount: Int32 = 0
	@objc dynamic public var laughCount: Int32 = 0
  
// MARK: Methods

	override public func awakeFromInsert() {
		// createdAt = Date()
		setPrimitiveValue(Date(), forKey: "createdAt")
	}

	public override func awakeFromFetch() {
		super.awakeFromFetch()

		// Update derived properties
    	let dict = NSMutableDictionary()
		for reaction in reactions {
			dict.setValue(reaction, forKey: reaction.word)
			switch reaction.word {
				case "like": likeCount = reaction.count
				case "love": loveCount = reaction.count
				case "laugh": laughCount = reaction.count
				default: break
			}
		}
		reactionDict = dict
	}
    	
	func buildFromV3(context: NSManagedObjectContext, v3Object: TwitarrV3TwarrtData) {
		var changed = TestAndUpdate(\.id, v3Object.twarrtID)
		changed = TestAndUpdate(\.createdAt, v3Object.createdAt) || changed
		changed = TestAndUpdate(\.text, v3Object.text) || changed 
		changed = TestAndUpdate(\.numReactions, v3Object.likeCount) || changed 
		let replyGroup = v3Object.replyGroupID ?? -1
		changed = TestAndUpdate(\.replyGroup, replyGroup) || changed

		// Intent is to update photos in a way where we don't modify photos until we're sure it's changing.
		let tempDetails = mutableOrderedSetValue(forKey: "photoDetails")
		if let newImageFilenames = v3Object.images {
			let photoDict: [String : PhotoDetails] = context.userInfo.object(forKey: "PhotoDetails") as! [String : PhotoDetails] 
			for (index, image) in newImageFilenames.enumerated() {
				if tempDetails.count <= index, let photoToAdd = photoDict[image] {
					tempDetails.add(photoToAdd)
				} 
				if (tempDetails[index] as? PhotoDetails)?.id != image, let photoToAdd = photoDict[image] {
					tempDetails.replaceObject(at:index, with: photoToAdd)
				}
			}
			if tempDetails.count > newImageFilenames.count {
				tempDetails.removeObjects(in: NSRange(location: newImageFilenames.count, length: photoDetails.count - newImageFilenames.count))
			}
		} 
		else {
			if tempDetails.count > 0 {
				tempDetails.removeAllObjects()
			}
		}
		
		let userDict: [UUID : KrakenUser ] = context.userInfo.object(forKey: "Users") as! [UUID : KrakenUser] 
		if let krakenUser = userDict[v3Object.author.userID] {
			if value(forKey: "author") == nil || krakenUser.userID != author.userID {
				author = krakenUser
			}
		}
		
		buildUserReactionFromV3(context: context, userLike: v3Object.userLike)
		
		// Not handled: isBookmarked,
	}
	
	func buildFromV3DetailData(context: NSManagedObjectContext, v3Object: TwitarrV3TwarrtDetailData) {
		TestAndUpdate(\.id, Int64(v3Object.postID))
		TestAndUpdate(\.createdAt, v3Object.createdAt)
		TestAndUpdate(\.text, v3Object.text)
		TestAndUpdate(\.replyGroup, Int64(v3Object.replyGroupID ?? -1))

		let userDict: [UUID : KrakenUser ] = context.userInfo.object(forKey: "Users") as! [UUID : KrakenUser] 
		if let krakenUser = userDict[v3Object.author.userID] {
			if value(forKey: "author") == nil || krakenUser.userID != author.userID {
				author = krakenUser
			}
		}
		
		// Intent is to update photos in a way where we don't modify photos until we're sure it's changing.
		if let newImageFilenames = v3Object.images {
			let photoDict: [String : PhotoDetails] = context.userInfo.object(forKey: "PhotoDetails") as! [String : PhotoDetails] 
			for (index, image) in newImageFilenames.enumerated() {
				if photoDetails.count <= index, let photoToAdd = photoDict[image] {
					photoDetails.add(photoToAdd)
				} 
				if (photoDetails[index] as? PhotoDetails)?.id != image, let photoToAdd = photoDict[image] {
					photoDetails.replaceObject(at:index, with: photoToAdd)
				}
			}
			if photoDetails.count > newImageFilenames.count {
				photoDetails.removeObjects(in: NSRange(location: newImageFilenames.count, length: photoDetails.count - newImageFilenames.count))
			}
		} 
		else {
			if photoDetails.count > 0 {
				photoDetails.removeAllObjects()
			}
		}
		
		buildUserReactionFromV3(context: context, userLike: v3Object.userLike)
		
		func setReactionCounts(word: String, users: [TwitarrV3UserHeader]) {
			if let reactionObj = reactionDict?[word] as? Reaction {
				reactionObj.count = Int32(users.count)
			}
			else if users.count > 0 {
				let newReaction = Reaction(context: context)
				newReaction.word = word
				newReaction.count = Int32(users.count)
				newReaction.sourceTweet	= self
			}
		}
		setReactionCounts(word: "like", users: v3Object.likes)
		setReactionCounts(word: "love", users: v3Object.loves)
		setReactionCounts(word: "laugh", users: v3Object.laughs)
	}
	
	func buildUserReactionFromV3(context: NSManagedObjectContext, userLike: TwitarrV3LikeType?) {
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
				if let ucr = userCurrentReaction, userLike?.rawValue != ucr.word {
					if let _ = ucr.users.remove(currentUser) {
						ucr.count -= 1
					}
				}
			}
				
			// Add new reaction, if any
			if let newReactionWord = userLike?.rawValue, userCurrentReaction?.word != newReactionWord {
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
					newReaction.sourceTweet	= self
				}
			}
		}
	}
			
	// Always returns nil if nobody's logged in.
	func getPendingUserReaction() -> PostOpTweetReaction? {
		if let username = CurrentUser.shared.loggedInUser?.username, let reaction = reactionOps?.first(where: { reaction in
				guard let r = reaction as? PostOpTweetReaction else { return false }
				return r.author.username == username }) {
			return reaction as? PostOpTweetReaction
		}
		return nil
	}
	
	func setReaction(_ reactionWord: LikeOpKind) {
		LocalCoreData.shared.performLocalCoreDataChange { context, currentUser in
			guard let thisPost = context.object(with: self.objectID) as? TwitarrPost else { return }

			// Check for existing op for this user
			let op = thisPost.getPendingUserReaction() ?? PostOpTweetReaction(context: context)
			op.operationState = .readyToSend
			op.reactionWord = reactionWord.string()
			op.sourcePost = thisPost
		}
	}
	
	func cancelReactionOp(_ reactionWord: String) {
		guard let existingOp = getPendingUserReaction() else { return }
		PostOperationDataManager.shared.remove(op: existingOp)
	}
	
	// Currently only works for deletes where the author is the current user--not for admin deletes.
	func addDeleteTweetOp() {
		LocalCoreData.shared.performLocalCoreDataChange { context, currentUser in
			guard let thisPost = context.object(with: self.objectID) as? TwitarrPost else { return }

			// Until we add support for admin deletes
			guard currentUser.username == thisPost.author.username else { 
				CoreDataLog.debug("Kraken can't do admin deletes of twitarr posts.")
				return
			}

			// Check for existing op for this post
			var existingOp: PostOpTweetDelete?
			if let existingOps = thisPost.opsDeletingThisTweet {
				for task in existingOps {
					// Technically should always be true as we don't allow for admin deletes?
					if task.author.username == thisPost.author.username {
						existingOp = task
						return
					}
				}
			}
			if existingOp == nil {
				existingOp = PostOpTweetDelete(context: context)
				existingOp?.tweetToDelete = thisPost
			}
			existingOp?.operationState = .readyToSend
		}
	}
	
	func cancelDeleteOp() {
		guard let currentUsername = CurrentUser.shared.loggedInUser?.username else { return }
		if let deleteOp = opsDeletingThisTweet?.first(where: { $0.author.username == currentUsername }) {
			PostOperationDataManager.shared.remove(op: deleteOp)
		}
	}
	
	func cancelEditOp() {
		guard let currentUsername = CurrentUser.shared.loggedInUser?.username else { return }
		if let editOp = opsEditingThisTweet, editOp.author.username == currentUsername {
			PostOperationDataManager.shared.remove(op: editOp)
		}
	}
}

// MARK: -

// TODO: I think this needs to be reworked, as it doesn't handle filtered views well. Each recent call should
// store an array of IDs of the tweets it loaded, and we'd build contiguous covered regions by checking
// for one member's anchor being in another's loaded list.

// Stores info about recent successful calls that loaded tweets. 
fileprivate struct TwitarrRecentNetworkCall {

	var indexRange: Range<Int>
	let callTime: Date
		
	var description: String {
		var returnString = ""
		returnString.append("Range: \(indexRange), at: \(callTime)")
		return returnString
	}
}

// MARK: - Filter Pack

// 5 minute freshness period.
let tweetCacheFreshTime = 300.0

// A FilterPack is a set of filtering options to get a subset of the tweet stream, plus the predicate, sortDescriptor,
// and FRC to fetch those results from CoreData. The FilterPack also marshalls network calls to get/refresh the tweets,
// using a freshness algorithm that remembers which ranges of results were last fetched.
class TwitarrFilterPack: NSObject, FRCDataSourceLoaderDelegate {
	var replyGroupFilter: Int64?					// Filters to tweets in this reply group.
	var authorFilter: String?						// Filters to tweets authored by this author, by username
	var mentionsFilter: String?						// Filters to tweets that "@" mention this user
	var hashtagFilter: String?						// Filters to tweets with this hashtag
	var textFilter: String?							// Filters to tweets with this text
	
	var filterTitle: String
	var isSearchQuery: Bool = false
	var morePostsExist: Bool = false				// TRUE if our last call on the current query indicated more results exist
	var topPostIsNewest = true
	
	// The Core Data structures that fetch tweets from the stream; built using the filter info above.
	var frc: NSFetchedResultsController<TwitarrPost>?
	var predicate: NSPredicate						// For Core Data loads of this filter
	var sortDescriptors: [NSSortDescriptor]
	var anchor: Int64? 							// The twarrt id that anchors the list. Nil until we complete an unanchored request.
	
	// These are used to track what tweets we've loaded recently; used to prevent duplicate loads.
	// Said differently, this tells us when we need to perform a load because the data is missing or stale.
	private var recentNetworkCalls: [TwitarrRecentNetworkCall] = []
	private let recentNetworkCallsQ = DispatchQueue(label:"RecentNetworkCalls mutation serializer")
	private var nextRecalculateTime: Date = Date()
	private var coveredIndices: IndexSet = IndexSet()
	
	// MARK: Methods
	init(author: String? = nil, text: String? = nil, replyGroup: Int64? = nil) {
		
		// This could be extended to combine multiple predicate types together
		if let searchText = text {
			if searchText.hasPrefix("#") {
				hashtagFilter = searchText
				predicate = NSPredicate(format: "text contains %@", searchText)
				filterTitle = searchText
			}
			else if searchText.hasPrefix("@") {
				mentionsFilter = searchText
				predicate = NSPredicate(format: "text contains %@", searchText)
				filterTitle = "Mentions: \(searchText)"
			}
			else {
				textFilter = searchText
				predicate = NSPredicate(format: "text contains %@", searchText)
				filterTitle = "Contains: \(searchText)"
			}
		}
		else if let author = author {
			authorFilter = author
			predicate = NSPredicate(format: "author.username == %@", author)
			filterTitle = "Author: \(author)"
		}
		else if let replyGroup = replyGroup {
			replyGroupFilter = replyGroup
			predicate = NSPredicate(format: "replyGroup == %d OR id == %d", replyGroup, replyGroup)
			filterTitle = "Thread"
			topPostIsNewest = false
		}
		else {
			// Everything
			predicate = NSPredicate(value: true)
			filterTitle = "Twitarr"
		}
		sortDescriptors = [NSSortDescriptor(key: "id", ascending: !topPostIsNewest)]

		super.init()
	}
	
	init(urlString: String) {
		var predicates = Array<NSPredicate>()			
		filterTitle = "Tweets"
		if let url = URL(string: urlString), let components = URLComponents(string: urlString),
				 url.pathComponents.count > 1, url.pathComponents[1] == "tweets" {
			if url.pathComponents.count == 3, let tweetID = Int64(url.pathComponents[2]) {
				replyGroupFilter = tweetID
				predicate = NSPredicate(format: "replyGroup == %d OR id == %d", tweetID, tweetID)
				filterTitle = "Thread"
				topPostIsNewest = false
			}
			
			for queryItem in components.queryItems ?? [] {
				if var value = queryItem.value {
					switch queryItem.name {
						case "search": 
							textFilter = value
							predicates.append(NSPredicate(format: "text contains %@", value))
							filterTitle = value
						case "hashtag": 
							if !value.hasPrefix("#") {
								value.insert("#", at: value.startIndex)
							}
							hashtagFilter = value
							predicates.append(NSPredicate(format: "text contains %@", value))
							filterTitle = value
						case "mentions":
							if !value.hasPrefix("@") {
								value.insert("@", at: value.startIndex)
							}
							mentionsFilter = value
							predicates.append(NSPredicate(format: "text contains %@", value))
							filterTitle = value
						case "mentionSelf":
							mentionsFilter = "@\(CurrentUser.shared.loggedInUser?.username ?? "")"
							predicates.append(NSPredicate(format: "text contains %@", value))
							filterTitle = value
//						case "byUser":
						case "byUsername":
							authorFilter = value
							predicates.append(NSPredicate(format: "author.username == %@", value))
							filterTitle = "Author: \(value)"
//						case "bookmarked":
						case "replyGroup":
							let threadID = Int64(value) ?? 0
							replyGroupFilter = threadID
							predicates.append(NSPredicate(format: "replyGroup == %d OR id == %d", threadID, threadID))
							filterTitle = "Thread"
							topPostIsNewest = false
//						case "hideReplies":
//						case "likeType":
//						case "after":
//						case "before":
//						case "afterDate":
//						case "beforeDate":
//						case "from":
//						case "start":
//						case "limit":
						default: break
					}
				}
			}
		}
		// AND predicate with no subpredicates evals to true.
		predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
		sortDescriptors = [NSSortDescriptor(key: "id", ascending: !topPostIsNewest)]
		super.init()
	}
	
	// Returns TRUE of any sort of filter is applied, FALSE if it specifies all tweets
	func hasFilter() -> Bool {
		return replyGroupFilter != nil || authorFilter != nil || mentionsFilter != nil || hashtagFilter != nil ||
				textFilter != nil
	}
	
	// Builds a request for some tweets, anchored at the given offset, or newest available if index is nil.
	// The filterPack's filters are used to build the request: if e.g. authorFilter is nonnull, the request will be for
	// tweets by that author.
	func buildRequest(startIndex: Int?, limit: Int = 50) -> URLRequest {
		var request: URLRequest
		var query: [URLQueryItem] = []
		
		// If we're showing a particular replygroup, filter for it
		if let replyGroup = replyGroupFilter {
			query.append(URLQueryItem(name: "replyGroup", value: String(replyGroup)))
			if anchor == nil {
				anchor = replyGroup - 1
			}
		}
		
		// Anchor the request at our anchor point, if we have one
		if let anchor = anchor {
			query.append(URLQueryItem(name: topPostIsNewest ? "before" : "after", value: String(anchor)))
		}
		else {
			query.append(URLQueryItem(name: "from", value: topPostIsNewest ? "last" : "first"))
		}
		
		// If we have a text string as part of the filter, and can URL-sanitize the string, use it
		if let searchString = textFilter {
			query.append(URLQueryItem(name: "search", value: searchString))
		}
		if let nameString = authorFilter {
			query.append(URLQueryItem(name: "byusername", value: nameString)) // FIXME: no such query param exists yet
		}
		if let nameString = mentionsFilter {
			query.append(URLQueryItem(name: "mentions", value: nameString))
		}
		if let hashtag = hashtagFilter {
			query.append(URLQueryItem(name: "hashtag", value: hashtag))
		}
		query.append(URLQueryItem(name: "limit", value: "\(limit)"))
	//	query.append(URLQueryItem(name: "page", value: String(fromOffset)))

		request = NetworkGovernor.buildTwittarRequest(withEscapedPath: "/api/v3/twitarr", query: query)
		NetworkGovernor.addUserCredential(to: &request)
		return request		
	}
	
	private func recalculateCoveredTweets(adding newCall: TwitarrRecentNetworkCall? = nil, removing: TwitarrRecentNetworkCall? = nil,
			removingAll: Bool = false) {
		recentNetworkCallsQ.sync {
			if removingAll {
				recentNetworkCalls.removeAll()
			}
			if let newNetworkCall = newCall {
				recentNetworkCalls.append(newNetworkCall)
			}
			if let failedNetworkCall = removing {
				recentNetworkCalls.removeAll { $0.indexRange == failedNetworkCall.indexRange && $0.callTime == failedNetworkCall.callTime }
			}
			recentNetworkCalls = recentNetworkCalls.filter {
				$0.callTime > Date(timeIntervalSinceNow: 0 - tweetCacheFreshTime)
			}
			coveredIndices = recentNetworkCalls.reduce(IndexSet()) { $0.union(IndexSet($1.indexRange)) }
			
			let earliestCall = self.recentNetworkCalls.reduce(Date()) { min($0, $1.callTime) } 
			self.nextRecalculateTime = Date(timeInterval: tweetCacheFreshTime, since: earliestCall) 
		}
	}
	
	// Forces a reload, asking for the newest tweets that match the filterpack. Usually tied to pull-to-refresh.
	func loadNewestTweets(done: (() -> Void)? = nil) {
		anchor = nil
		let request: URLRequest = buildRequest(startIndex: nil)
		TwitarrDataManager.shared.loadV3Tweets(request: request) { result in
			if case .success(let anchorID) = result { 
				self.anchor = anchorID
				self.recalculateCoveredTweets(adding: TwitarrRecentNetworkCall(indexRange: 0..<50, callTime: Date()), removingAll: true)
			}
			done?()
		}
	}

	// Input index is usually a collectionView row index. This fn checks that we have recently loaded
	// from the server all the cells near the current cell, both 'newer' and 'older' than the current tweet.
	// Note that coveredTweets is an index set and needn't be contiguous.
	func checkLoadRequiredFor(frcIndex: Int) {
		if Date() > nextRecalculateTime {
			recalculateCoveredTweets()
		}
		var covered = IndexSet()
		recentNetworkCallsQ.sync {
			covered = self.coveredIndices
		}
		var startIndex: Int?
		// If everything's stale, (re)load the 50 tweets centered on the anchor index.
		if covered.isEmpty {
			startIndex = max(0, frcIndex - 25)
		}
		else {
			// If there are stale/missing tweets at higher indices near the index, reload them
			if !covered.contains(integersIn: frcIndex ..< frcIndex + 11) {
				let uncovered = IndexSet(frcIndex ..< frcIndex + 11).subtracting(covered)
				if let firstUncovered = uncovered.min() {
					startIndex = firstUncovered - 1
				}
			}
			// If there are stale/missing tweets at lower indices near the index, reload them
			let prevCheckRange = max(frcIndex - 10, 0) ..< frcIndex
			if startIndex == nil, !prevCheckRange.isEmpty, !covered.contains(integersIn: prevCheckRange) {
				let uncovered = IndexSet(prevCheckRange).subtracting(covered)
				if let firstUncovered = uncovered.max() {
					startIndex = firstUncovered + 1
				}
			}
		}
			
		if let startIndex = startIndex {
			let newCoveredIndices = TwitarrRecentNetworkCall(indexRange: startIndex..<(startIndex + 50), callTime: Date())
			recalculateCoveredTweets(adding: newCoveredIndices)
		
			let request = buildRequest(startIndex: startIndex)
			TwitarrDataManager.shared.loadV3Tweets(request: request) { result in
				switch result {
				case .failure: self.recalculateCoveredTweets(removing: newCoveredIndices)
				case .success(let firstID): 
					if self.anchor == nil && startIndex == 0 {
						self.anchor = firstID
					}
				}
			}
		}
	}
	
	// FRCLoaderDelegate fn
	func userIsViewingCell(at indexPath: IndexPath) {
		checkLoadRequiredFor(frcIndex: indexPath.row)
	}

}


// MARK: -
// TwitarrDataManager provides access to tweets.
//
// That is, it is responsible for initiating and processing server calls to get tweets and associated data; it maintains 
// a local cache of that data; and it provides a unified API such that online and offline access to tweets work the same way.
// This includes searching for tweets--when offline, searching the tweet stream is performed locally, whereas the same search
// initiates network requests when online.
class TwitarrDataManager: NSObject {
	static let shared = TwitarrDataManager()
	
	private let coreData = LocalCoreData.shared
//	var fetchedData: NSFetchedResultsController<TwitarrPost>
	
	// TRUE when we've got a network call running to update the stream, or the current filter.
	@objc dynamic var networkUpdateActive: Bool = false  
	
	// Once we've loaded the very first tweet, olderPosts gets .false. If we scroll backwards, get older tweets, 
	// but not the first ever, it'll get .true. NewerPostsExist is only .true if we scroll forward, load new posts,
	// and the server returns N new posts but says there's even newer ones available. 
	var newerPostsExist: Bool? 
	var olderPostsExist: Bool?
	var totalTweets: Int = 0
	
	//
	var lastError : Error?
	
// MARK: Methods
	
	init(filterString: String? = nil) {
		super.init()
	}
	
	// Maps parent post IDs to draft reply text. The most recent 'mainline' post draft is in the "" entry.
	// Probably don't need to save this between launches? Probably should move this to a "ComposeDataManager"?
	var recentTwitarrPostDrafts: [ Int64 : String ] = [:]
	func getDraftPostText(replyingTo: Int64?) -> String? {
		return recentTwitarrPostDrafts[replyingTo ?? -1]
	}
	func saveDraftPost(text: String?, replyingTo: Int64?) {
		if let text = text {
			recentTwitarrPostDrafts[replyingTo ?? -1] = text
		}
		else {
			recentTwitarrPostDrafts.removeValue(forKey: replyingTo ?? -1)
		}
	}
	
	func getTweetWithID(_ tweetID: Int64, inContext: NSManagedObjectContext? = nil) -> TwitarrPost? {
		guard inContext != nil || Thread.isMainThread else {
			print("not main thread")
			return nil
		}
		let context = inContext ?? coreData.mainThreadContext
		let request = NSFetchRequest<TwitarrPost>(entityName: "TwitarrPost")
		request.predicate = NSPredicate(format: "id == %d", tweetID)
		request.fetchLimit = 1
		return try? context.fetch(request).first
	}
		
	// This call loads a contiguous series of tweets from the stream. When processing the response, we infer 
	// deleted tweets by finding tweets in our CoreData cache that are in the timeframe the response covers but not
	// in the repsonse.
	func loadStreamTweets(anchorTweet: TwitarrPost?, newer: Bool = false, done: (() -> Void)? = nil) {
		var queryParams = [URLQueryItem]()
		queryParams.append(URLQueryItem(name: "limit", value: "50"))
		if let anchorID = anchorTweet?.id {
			queryParams.append(URLQueryItem(name: newer ? "after" : "before", value: String(anchorID)))
		}
		
		var request = NetworkGovernor.buildTwittarRequest(withPath: "/api/v3/twitarr", query: queryParams)
		NetworkGovernor.addUserCredential(to: &request)
		networkUpdateActive = true
		NetworkGovernor.shared.queue(request) { (package: NetworkResponse) in
			self.networkUpdateActive = false
			if let data = package.data {
//				print (String(decoding:data!, as: UTF8.self))
				do {
					let twarrts = try Settings.v3Decoder.decode([TwitarrV3TwarrtData].self, from: data)
					self.ingestV3StreamPosts(twarrts: twarrts)						
				} catch 
				{
					NetworkLog.error("Failure parsing stream tweets.", ["Error" : error, "URL" : request.url as Any])
				} 
			}
			
			done?()
		}
	}
	
	// Done callback is called with the ID of the first twarrt of the response.
	func loadV3Tweets(request: URLRequest, done: ((Result<Int64?, Error>) -> Void)? = nil) {
		networkUpdateActive = true
		NetworkGovernor.shared.queue(request) { (package: NetworkResponse) in
			self.networkUpdateActive = false
			if let error = package.getAnyError() {
				done?(.failure(error))
				return
			}
			var firstID: Int64? = nil
			if let data = package.data {
//				print (String(decoding:data, as: UTF8.self))
				do {
					let twarrts = try Settings.v3Decoder.decode([TwitarrV3TwarrtData].self, from: data)
					self.ingestV3StreamPosts(twarrts: twarrts)
					firstID = twarrts.isEmpty ? nil : twarrts[0].twarrtID					
				} catch 
				{
					NetworkLog.error("Failure parsing stream tweets.", ["Error" : error, "URL" : request.url as Any])
				} 
			}
			
			done?(.success(firstID))
		}
	}
		
	fileprivate func ingestV3StreamPosts(twarrts: [TwitarrV3TwarrtData]) {
		LocalCoreData.shared.performNetworkParsing { context in
			context.pushOpErrorExplanation("Failure adding stream tweets to Core Data.")
			
			// Algorithm here is to do a bottom-up insert/update of sub-objects first, and higher-level objects then set their
			// relationship links to the already-established sub-objects. 
		
			// Make a uniqued list of users from the posts, and get them inserted/updated.
			let userArray = twarrts.map { $0.author }
			UserManager.shared.update(users: userArray, inContext: context)
		
			// Photos, same idea
			let tweetPhotos = twarrts.compactMap { $0.images }.joined()
			ImageManager.shared.updateV3(imageFilenames: Array(tweetPhotos), inContext: context)

			// IF we have a post in CD in the # range of the incoming twarrts, but 'skipped' by the incoming twarrts,
			// that means the post is 1) Muted, 2) Blocked, 3) Muteword-muted, or 4) Mod-deleted. We might be able to infer
			// which by running the CD post contents against the user's mutes, etc. 
		
			// Get all the existing posts in CD that match posts in the call
			let newPostIDs = twarrts.map { $0.twarrtID }
			let request = NSFetchRequest<TwitarrPost>(entityName: "TwitarrPost")
			request.predicate = NSPredicate(format: "id IN %@", newPostIDs)
			request.fetchLimit = twarrts.count + 10 
			let cdResults = try context.fetch(request)
			var cdPostsDict = Dictionary(cdResults.map { ($0.id, $0) }, uniquingKeysWith: { (first,_) in first })

			for twarrt in twarrts {
				let removedValue = cdPostsDict.removeValue(forKey: twarrt.twarrtID)
				let cdPost = removedValue ?? TwitarrPost(context: context)
				cdPost.buildFromV3(context: context, v3Object: twarrt)
			}
		}
	}
	
	func loadV3TweetDetail(tweet: TwitarrPost) {
		loadV3TweetDetail(tweetID: tweet.id)
	}
	
	func loadV3TweetDetail(tweetID: Int64) {
		var request = NetworkGovernor.buildTwittarRequest(withPath: "/api/v3/twitarr/\(tweetID)", query: nil)
		NetworkGovernor.addUserCredential(to: &request)
		networkUpdateActive = true
		NetworkGovernor.shared.queue(request) { (package: NetworkResponse) in
			self.networkUpdateActive = false
			if let data = package.data {
//				print (String(decoding:data, as: UTF8.self))
				do {
					let twarrt = try Settings.v3Decoder.decode(TwitarrV3TwarrtDetailData.self, from: data)
					LocalCoreData.shared.performNetworkParsing { context in
						context.pushOpErrorExplanation("Failure adding tweet detail to Core Data.")
											
						// Make a uniqued list of users from the posts, and get them inserted/updated.
						UserManager.shared.update(users: [twarrt.author], inContext: context)
					
						// Photos, same idea
						if let images = twarrt.images {
							ImageManager.shared.updateV3(imageFilenames: images, inContext: context)
						}

						// Get the existing post in CD 
						let request = NSFetchRequest<TwitarrPost>(entityName: "TwitarrPost")
						request.predicate = NSPredicate(format: "id == %d", twarrt.postID)
						request.fetchLimit = 1
						let cdResults = try context.fetch(request)
						let cdPost = cdResults.first ?? TwitarrPost(context: context)
						cdPost.buildFromV3DetailData(context: context, v3Object: twarrt)
					}
				} catch 
				{
					NetworkLog.error("Failure parsing tweet detail.", ["Error" : error, "URL" : request.url as Any])
				} 
			}
		}
	}

	
	// This is for posts created by the user; the responses from create methods return the post that got made.
	func ingestNewUserPost(post: TwitarrV3TwarrtData) {
		TwitarrDataManager.shared.ingestV3StreamPosts(twarrts: [post])
	}
		
	// For new mainline posts, new posts that are replies, and edits to existing posts
	// Creates a PostOperation, saving all the data needed to post a new tweet, and queues it for posting.
	func queuePost(_ existingDraft: PostOpTweet?, withText: String, images: [PhotoDataType]?, 
			replyGroupID: Int64? = nil, editing: TwitarrPost? = nil, done: @escaping (PostOpTweet?) -> Void) {
		EmojiDataManager.shared.gatherEmoji(from: withText)	
		
		LocalCoreData.shared.performNetworkParsing { context in
			guard let _ = CurrentUser.shared.getLoggedInUser(in: context) else { done(nil); return }
			context.pushOpErrorExplanation("Couldn't save context while creating new Twitarr post.")
			
			var editPost: TwitarrPost? = nil
			if let edit = editing {
				editPost = context.object(with: edit.objectID) as? TwitarrPost
			}
			let draftInContext = existingDraft != nil ? context.object(with: existingDraft!.objectID) as? PostOpTweet :  nil
			
			let postToQueue = draftInContext ?? PostOpTweet(context: context)
			postToQueue.prepare(context: context, postText: withText, replyGroup: replyGroupID, tweetToEdit: editPost)
			
			let photoOpArray: [PostOpPhoto_Attachment]? = images?.map {
				let op = PostOpPhoto_Attachment(context: context); op.setupFromPhotoData($0); 
				op.parentTweetPostOp = postToQueue
				return op 
			}
			// In theory we could avoid replacing all the photos if there were no changes, but edits shouldn't happen *that* often.
			if let photoOpArray = photoOpArray {
				postToQueue.photos = NSOrderedSet(array: photoOpArray)
			}
			else {
				postToQueue.photos = nil
			}
			
			LocalCoreData.shared.setAfterSaveBlock(for: context) { saveSuccess in 
				let mainThreadPost = LocalCoreData.shared.mainThreadContext.object(with: postToQueue.objectID) as? PostOpTweet 
				done(mainThreadPost)
			}
		}
	}
	
}

// MARK: - V3 API Decoding


struct TwitarrV3TwarrtData: Codable {
    /// The ID of the twarrt.
    var twarrtID: Int64
    /// The timestamp of the twarrt.
    var createdAt: Date
    /// The twarrt's author.
    var author: TwitarrV3UserHeader
    /// The text of the twarrt.
    var text: String
    /// The filenames of the twarrt's optional images.
    var images: [String]?
    /// The ID of the twarrt to which this twarrt is a reply.
    var replyGroupID: Int64?
    /// Whether the current user has bookmarked the twarrt.
    var isBookmarked: Bool
    /// The current user's `LikeType` reaction on the twarrt.
    var userLike: TwitarrV3LikeType?
    /// The total number of `LikeType` reactions on the twarrt.
    var likeCount: Int64
}

public struct TwitarrV3TwarrtDetailData: Codable {
    /// The ID of the post/twarrt.
    var postID: Int
    /// The timestamp of the post/twarrt.
    var createdAt: Date
    /// The twarrt's author.
    var author: TwitarrV3UserHeader
    /// The text of the forum post or twarrt.
    var text: String
    /// The filenames of the post/twarrt's optional images.
    var images: [String]?
    /// The ID of the twarrt to which this twarrt is a reply.
    var replyGroupID: Int?
    /// Whether the current user has bookmarked the post.
    var isBookmarked: Bool
    /// The current user's `LikeType` reaction on the twarrt.
    var userLike: TwitarrV3LikeType?
    /// The users with "laugh" reactions on the post/twarrt.
    var laughs: [TwitarrV3UserHeader]
    /// The users with "like" reactions on the post/twarrt.
    var likes: [TwitarrV3UserHeader]
    /// The users with "love" reactions on the post/twarrt.
    var loves: [TwitarrV3UserHeader]
}


// Paginator is a component of a bunch of structs
public struct TwitarrV3Paginator: Codable {
    /// The total number of items returnable by the request.
    var total: Int
	/// The index number of the first item in the collection array, relative to the overall returnable results.
	var start: Int
	/// The number of results requested. The collection array could be smaller than this number.
	var limit: Int
}
