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
fileprivate class TwitarrRecentNetworkCall: NSObject {

	// For each call, there's an anchor post we use for the timestamp, and we request numPosts posts either earlier
	// or later than the anchor.
	var anchor: TwitarrPost?
	var numPosts: Int
	var isNewer: Bool
	
	var indexRange: Range<Int>
	let callTime: Date
	
	init(anchor: TwitarrPost?, count: Int, newer: Bool) {
		self.anchor = anchor
		numPosts = count
		isNewer = newer
		self.callTime = Date()
		indexRange = 0 ..< 0
		super.init()
	}
	
	// Returns false if the indices can't be updated (perhaps one of the posts has been deleted?)
	@discardableResult func updateIndices(frc: NSFetchedResultsController<TwitarrPost>) -> Bool {
		if let anchor = anchor, let indexPath = frc.indexPath(forObject: anchor)
		{
			if isNewer {
				indexRange = indexPath.row - numPosts ..< indexPath.row
			}
			else {
				indexRange = indexPath.row ..< indexPath.row + numPosts
			}	
			return true
		}
		else {
			indexRange = 0 ..< numPosts
			return true
		}
	}
	
	override var description: String {
		var returnString = ""
		if let anchor = anchor {
			returnString.append("Anchor at: \(anchor.id) timestamp: \(anchor.createdAt). ")
		} 
		returnString.append("\(numPosts) posts. isNewer: \(isNewer). Range: \(indexRange)")
		return returnString
	}
}

// MARK: - Filter Pack

// 5 minute freshness period.
let tweetCacheFreshTime = 300.0

class TwitarrFilterPack: NSObject, FRCDataSourceLoaderDelegate {
	var predicate: NSPredicate						// For Core Data loads of this filter
	var sortDescriptors: [NSSortDescriptor]
	var authorFilter: String?						// Filters to tweets authored by this author
	var mentionsFilter: String?						// Filters to tweets that "@" mention this user
	var hashtagFilter: String?						// Filters to tweets with this hashtag
	var textFilter: String?							// Filters to tweets with this text
	
	var filterTitle: String
	var isSearchQuery: Bool = false
	var isContiguousTweets: Bool = false
	var morePostsExist: Bool = false				// TRUE if our last call on the current query indicated more results exist
	
	//
	var frc: NSFetchedResultsController<TwitarrPost>?
	
	// These are used to track what tweets we've loaded recently; used to prevent duplicate loads.
	// Said differently, this tells us when we need to perform a load because the data is missing or stale.
	fileprivate var recentNetworkCalls: [TwitarrRecentNetworkCall] = []
	private let recentNetworkCallsQ = DispatchQueue(label:"RecentNetworkCalls mutation serializer")
	var nextRecalculateTime: Date = Date()
	var coveredIndices: IndexSet = IndexSet()
	
	struct CallToMake {
		var index: Int
		var directionIsNewer: Bool
	}
	
	// MARK: Methods
	init(author: String?, text: String?) {
		sortDescriptors = [NSSortDescriptor(key: "id", ascending: false)]
		
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
		else {
			// Everything
			predicate = NSPredicate(value: true)
			filterTitle = "Twitarr"
			isContiguousTweets = true
		}
		
		super.init()
	}
	
	// Builds a request for some tweets, anchored at the given offset, or newest available if index is nil.
	// The filterPack's filters are used to build the request: if e.g. authorFilter is nonnull, the request will be for
	// tweets by that author.
	func buildRequest(anchorFRCIndex: Int?, newer: Bool, limit: Int = 50) -> URLRequest {
		var request: URLRequest
		var query: [URLQueryItem] = []
		
		// Get the tweet at the FRC index
		if let index = anchorFRCIndex, frc?.fetchedObjects?.count ?? -1 > index, let tweet = frc?.fetchedObjects?[index] {
			query.append(URLQueryItem(name: newer ? "after" : "before", value: String(tweet.id)))
		}
		else {
			query.append(URLQueryItem(name: "from", value: newer ? "last" : "first"))
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

		request = NetworkGovernor.buildTwittarRequest(withEscapedPath: "/api/v3/twitarr/", query: query)
		NetworkGovernor.addUserCredential(to: &request)
		return request		
	}
	
	fileprivate func recalculateCoveredTweets(adding newCall: TwitarrRecentNetworkCall? = nil) {
		recentNetworkCallsQ.async {
			guard let fetchedData = self.frc else { return }
			
			if let newNetworkCall = newCall {
				self.recentNetworkCalls.append(newNetworkCall)
			}
			var newCoveredIndices = IndexSet()
			self.recentNetworkCalls = self.recentNetworkCalls.filter {
				if $0.callTime > Date(timeIntervalSinceNow: 0 - tweetCacheFreshTime) {
					return $0.updateIndices(frc: fetchedData)
				}
				else {
					return false
				}
			}
			let earliestCall = self.recentNetworkCalls.reduce(Date()) { min($0, $1.callTime) } 
			self.nextRecalculateTime = Date(timeInterval: tweetCacheFreshTime, since: earliestCall) 
			for call in self.recentNetworkCalls {
				var clampedRange = call.indexRange
				if clampedRange.lowerBound < 0 {
					clampedRange = 0..<clampedRange.upperBound
				}
				newCoveredIndices.insert(integersIn: clampedRange)
			}
			self.coveredIndices = newCoveredIndices
		}
	}
	
	// Forces a reload, asking for tweets newer than the newest. Usually tied to pull-to-refresh.
	func loadNewestTweets(done: (() -> Void)? = nil) {
		let request: URLRequest
		// If we have a newest loaded tweet, make it the anchor and load 50 tweets newer than that.
//		if frc?.fetchedObjects?.count ?? -1 > 0, let _ = frc?.fetchedObjects?[0] {
//			request = buildRequest(anchorFRCIndex: 0, newer: true)
//		}
//		else {
			// No anchor-load the 50 newest tweets.
			request = buildRequest(anchorFRCIndex: nil, newer: false)
//		}
		TwitarrDataManager.shared.loadV3Tweets(request: request, done: done)
	}

	// Input index is usually a collectionView row index. This fn checks that we have recently loaded
	// from the server all the cells near the current cell, both 'newer' and 'older' than the current tweet.
	// Note that coveredTweets is an index set and needn't be contiguous.
	func checkLoadRequiredFor(frcIndex: Int) {
		if Date() > nextRecalculateTime {
			recalculateCoveredTweets()
		}
		var callAnchor: CallToMake?
		recentNetworkCallsQ.sync {
			// If everything's stale, (re)load the 50 tweets centered on the anchor index.
			if self.coveredIndices.isEmpty {
				callAnchor = CallToMake(index: max (0, frcIndex - 25), directionIsNewer: false)
			}
			else {
				// If there are stale/missing tweets 'below' but near the index, load older tweets
				if !self.coveredIndices.contains(integersIn: frcIndex ..< frcIndex + 11) {
					let uncovered = IndexSet(frcIndex ..< frcIndex + 11).subtracting(self.coveredIndices)
					if let firstUncovered = uncovered.min() {
						callAnchor = CallToMake(index: firstUncovered - 1, directionIsNewer: false)
					}
				}
				// If there are stale/missing tweets 'above' but near the index, load newer tweets
				let prevCheckRange = max(frcIndex - 10, 0) ..< frcIndex
				if callAnchor == nil, !prevCheckRange.isEmpty, !self.coveredIndices.contains(integersIn: prevCheckRange) {
					let uncovered = IndexSet(prevCheckRange).subtracting(self.coveredIndices)
					if let firstUncovered = uncovered.max() {
						callAnchor = CallToMake(index: firstUncovered + 1, directionIsNewer: true)
					}
				}
			}
		} 
		
		// NOTE: Currently, increasing indices always indicates decreasing timestamps. That is,
		// all sort orders are (... "timestamp", ascending: false). If that changes we need to change logic here.
		
		if let anchor = callAnchor {
			let request = buildRequest(anchorFRCIndex: anchor.index, newer: anchor.directionIsNewer)
			TwitarrDataManager.shared.loadV3Tweets(request: request)
		
			if let numFRCResults = frc?.fetchedObjects?.count, anchor.index >= 0, anchor.index < numFRCResults {
				let anchorTweet = frc?.object(at: IndexPath(row: anchor.index, section: 0))
				let newNetworkResults = TwitarrRecentNetworkCall(anchor: anchorTweet, count: 50, newer: anchor.directionIsNewer)
				recalculateCoveredTweets(adding: newNetworkResults)
			}
			else if anchor.index == 0 {
				loadNewestTweets()
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
	
	func getTweetWithID(_ tweetID: Int64) throws -> TwitarrPost? {
		let request = NSFetchRequest<TwitarrPost>(entityName: "TwitarrPost")
		request.predicate = NSPredicate(format: "id == %d", tweetID)
		request.fetchLimit = 1
		return try coreData.mainThreadContext.fetch(request).first
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
			if let error = NetworkGovernor.shared.parseServerError(package) {
				NetworkLog.error(error.localizedDescription)
			}
			else if let data = package.data {
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
	
	func loadV3Tweets(request: URLRequest, done: (() -> Void)? = nil) {
		networkUpdateActive = true
		NetworkGovernor.shared.queue(request) { (package: NetworkResponse) in
			self.networkUpdateActive = false
			if let error = NetworkGovernor.shared.parseServerError(package) {
				NetworkLog.error(error.localizedDescription)
			}
			else if let data = package.data {
//				print (String(decoding:data, as: UTF8.self))
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
	
	// The optional AnchorTweet specifies that the given posts are directly adjacent to the anchor (that is, if 
	// extendsNewer is true, the oldest tweet in posts is the tweet chronologically after anchor. If anchor is nil, 
	// we can only assume posts can replace the tweets between startTime and endTime.
	// ONLY USE THIS FOR STREAM-CONTIGUOUS POSTS. Not for searches/filters.
//	fileprivate func ingestStreamPosts(posts: [TwitarrV2Post], anchorTime: Int64, extendsNewer: Bool, morePostsExist: Bool) {
//		LocalCoreData.shared.performNetworkParsing { context in
//			context.pushOpErrorExplanation("Failure adding stream tweets to Core Data.")
//			
//			// Algorithm here is to do a bottom-up insert/update of sub-objects first, and higher-level objects then set their
//			// relationship links to the already-established sub-objects. 
//		
//			// Make a uniqued list of users from the posts, and get them inserted/updated.
//			let userArray = posts.map { $0.author }
//			UserManager.shared.update(users: userArray, inContext: context)
//			
//			// Photos, same idea
//			let tweetPhotos = Dictionary(posts.compactMap { $0.photo == nil ? nil : ($0.photo!.id, $0.photo!) },
//					uniquingKeysWith: { first,_ in first })
//			ImageManager.shared.update(photoDetails: tweetPhotos, inContext: context)
//						
//			// Delete any posts in CD that are in the date range but aren't in the post stream we got from the server.
//			// That is, we asked for "The next 50 posts before/after this timestamp." Get the time range from anchor post time
//			// to the post farthest from the anchor; any posts in Core Data in that same time range that aren't in the call results
//			// must be posts deleted serverside.
//			let newPostIDs = posts.map { $0.id }
//			let postDates = posts.map { $0.timestamp }
//			let earliestDate = postDates.min()
//			let latestDate = postDates.max()
//
//			if var startDate = earliestDate, var endDate = latestDate {
//				startDate = min(startDate, anchorTime)
//				endDate = max(endDate, anchorTime)
//				let request = self.coreData.persistentContainer.managedObjectModel.fetchRequestFromTemplate(withName: "TwitarrPostsToDelete", 
//						substitutionVariables: [ "startDate" : startDate, "endDate" : endDate, "ids" : newPostIDs]) as! NSFetchRequest<TwitarrPost>
//				request.fetchLimit = posts.count * 3 // Hopefully there will never be a case where 100 out of 150 posts get mod deleted.
//				do {
//					let postsToDelete = try request.execute()
//					postsToDelete.forEach { context.delete($0) }
//				}
//				catch {
//					CoreDataLog.error("Could not delete Twitarr posts that appear to be have been deleted on server.")
//				}
//			}
//			
//			// Get all the existing posts in CD that match posts in the call
//			let request = self.coreData.persistentContainer.managedObjectModel.fetchRequestFromTemplate(withName: "TwitarrPostsWithIDs", 
//					substitutionVariables: [ "ids" : newPostIDs ]) as! NSFetchRequest<TwitarrPost>
//			request.fetchLimit = posts.count + 10 
//			let cdResults = try request.execute()
//
//			// Remember: While the TweetStream changes get serialized here, that doesn't mean that network calls get 
//			// completed in order, or that we haven't made the same call twice somehow.
//			var cdPostsDict = Dictionary(cdResults.map { ($0.id, $0) }, uniquingKeysWith: { (first,_) in first })
//			for post in posts {
//				let removedValue = cdPostsDict.removeValue(forKey: post.id)
//				let cdPost = removedValue ?? TwitarrPost(context: context)
//				cdPost.buildFromV2(context: context, v2Object: post)
//				
//				if post.id == posts.last?.id {					
//					if !extendsNewer && morePostsExist && cdPost.isInserted {
//						cdPost.contigWithOlder = false
//					}
//				} else {
//					// Note: This weird construction is necessary to keep CoreData from over-saving the store.
//					cdPost.contigWithOlder == false ? cdPost.contigWithOlder = true : nil
//				}
//			}
//		}
//	}
	
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
		var request = NetworkGovernor.buildTwittarRequest(withPath: "/api/v3/twitarr/\(tweet.id)", query: nil)
		NetworkGovernor.addUserCredential(to: &request)
		networkUpdateActive = true
		NetworkGovernor.shared.queue(request) { (package: NetworkResponse) in
			self.networkUpdateActive = false
			if let error = NetworkGovernor.shared.parseServerError(package) {
				NetworkLog.error(error.localizedDescription)
			}
			else if let data = package.data {
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
			inReplyTo: TwitarrPost? = nil, editing: TwitarrPost? = nil, done: @escaping (PostOpTweet?) -> Void) {
		EmojiDataManager.shared.gatherEmoji(from: withText)	
		
		LocalCoreData.shared.performNetworkParsing { context in
			guard let currentUser = CurrentUser.shared.getLoggedInUser(in: context) else { done(nil); return }
			context.pushOpErrorExplanation("Couldn't save context while creating new Twitarr post.")
			
			var parentPost: TwitarrPost? = nil
			if let parent = inReplyTo {
				parentPost = context.object(with: parent.objectID) as? TwitarrPost
			}
			var editPost: TwitarrPost? = nil
			if let edit = editing {
				editPost = context.object(with: edit.objectID) as? TwitarrPost
			}
			let draftInContext = existingDraft != nil ? context.object(with: existingDraft!.objectID) as? PostOpTweet :  nil
			
			let postToQueue = draftInContext ?? PostOpTweet(context: context)
			postToQueue.text = withText
			postToQueue.parent = parentPost
			postToQueue.tweetToEdit = editPost
			postToQueue.operationState = .readyToSend
			postToQueue.author = currentUser
			
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
				DispatchQueue.main.async {
					let mainThreadPost = LocalCoreData.shared.mainThreadContext.object(with: postToQueue.objectID) as? PostOpTweet 
					done(mainThreadPost)
				}
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
