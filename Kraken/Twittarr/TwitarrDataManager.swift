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
    @NSManaged public var id: String
    @NSManaged public var locked: Bool
    @NSManaged public var reactions: Set<Reaction>
    @NSManaged public var text: String
    @NSManaged public var timestamp: Int64
    @NSManaged public var contigWithOlder: Bool
    @NSManaged public var author: KrakenUser
    @NSManaged public var parentID: String?
    @NSManaged public var parent: TwitarrPost?
    @NSManaged public var children: Set<TwitarrPost>?
    @NSManaged public var photoDetails: PhotoDetails?
    
    	// Kraken relationships to other data
    @NSManaged public var opsWithThisParent: Set<PostOpTweet>?
    @NSManaged public var opsDeletingThisTweet: Set<PostOpTweetDelete>?	// Still needs to be to-many. Sigh.
    @NSManaged public var opsEditingThisTweet: PostOpTweet?		// I *think* this one can be to-one?
    @NSManaged public var reactionOps: NSMutableSet?

		// Properties built from reactions
	@objc dynamic public var reactionDict: NSMutableDictionary?			// the reactions set, keyed by reaction.word
	@objc dynamic public var likeReaction: Reaction?
  
// MARK: Methods

	public override func awakeFromFetch() {
		super.awakeFromFetch()

		// Update derived properties
    	let dict = NSMutableDictionary()
    	var newLikeReaction: Reaction?
		for reaction in reactions {
			dict.setValue(reaction, forKey: reaction.word)
			if reaction.word == "like" {
				newLikeReaction = reaction
			}
		}
		reactionDict = dict
		likeReaction = newLikeReaction
	}
    
	func buildFromV2(context: NSManagedObjectContext, v2Object: TwitarrV2Post) {
		var changed = TestAndUpdate(\.id, v2Object.id)
		changed = TestAndUpdate(\.locked, v2Object.locked) || changed
		changed = TestAndUpdate(\.text, v2Object.text) || changed 
		changed = TestAndUpdate(\.timestamp, v2Object.timestamp) || changed
		
		let userDict: [String : KrakenUser ] = context.userInfo.object(forKey: "Users") as! [String : KrakenUser] 
		if let krakenUser = userDict[v2Object.author.username] {
			if krakenUser.username != author.username {
				author = krakenUser
			}
		}
		else {
			CoreDataLog.error("Somehow we have a tweet without an author, or the author changed?")
		}

		if let v2Photo = v2Object.photo {
			if photoDetails?.id != v2Photo.id {
				let photoDict: [String : PhotoDetails ] = context.userInfo.object(forKey: "PhotoDetails") as! [String : PhotoDetails] 
				photoDetails = photoDict[v2Photo.id] 
			}
		}
		else {
			if photoDetails != nil {
				photoDetails = nil	// Can happen if photo was deleted from tweet
			}
		}
		
		// Hopefully item 0 in the parent chain is the *direct* parent?
		if v2Object.parentChain.count > 0 {
			let parentIDStr = v2Object.parentChain[0]
			TestAndUpdate(\TwitarrPost.parentID, parentIDStr)
			
			// Not hooking up the parent relationship yet. Not sure if we can, as the parent may not be cached at this point?
		}
		
		buildReactionsFromV2(context: context, v2Object: v2Object.reactions)
	}
	
	func buildReactionsFromV2(context: NSManagedObjectContext, v2Object: TwitarrV2ReactionsSummary) {
		// Delete any reactions not in the V2 blob
		let newReactionWords = Set<String>(v2Object.keys)
		for reaction in reactions {
			if !newReactionWords.contains(reaction.word) {
				reactions.remove(reaction)
			}
		}
		
		// Add/update
		for (reactionName, reactionV2Obj) in v2Object {
			var reaction = reactions.first { object in return object.word == reactionName }
			if reaction == nil {
				let r = Reaction(context: context)
				reactions.insert(r)	
				reaction = r
			}
			reaction?.buildFromV2(context: context, post: self, v2Object: reactionV2Obj, reactionName: reactionName)
		}
		
		// Update derived properties
    	let dict = NSMutableDictionary()
    	var newLikeReaction: Reaction?
		for reaction in reactions {
			dict.setValue(reaction, forKey: reaction.word)
			if reaction.word == "like" {
				newLikeReaction = reaction
			}
		}
		reactionDict = dict		
		likeReaction = newLikeReaction
	}
	
	func postDate() -> Date {
		return Date(timeIntervalSince1970: Double(timestamp) / 1000.0)
	}
	
	// Always returns nil if nobody's logged in.
	func getPendingUserReaction(_ named: String) -> PostOpTweetReaction? {
		if let username = CurrentUser.shared.loggedInUser?.username, let reaction = reactionOps?.first(where: { reaction in
				guard let r = reaction as? PostOpTweetReaction else { return false }
				return r.author.username == username && r.reactionWord == named }) {
			return reaction as? PostOpTweetReaction
		}
		return nil
	}
	
	func setReaction(_ reactionWord: String, to newState: Bool) {
		LocalCoreData.shared.performLocalCoreDataChange { context, currentUser in
			guard let thisPost = context.object(with: self.objectID) as? TwitarrPost else { return }

			// Check for existing op for this user, with this word
			let op = thisPost.getPendingUserReaction(reactionWord) ?? PostOpTweetReaction(context: context)
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
			returnString.append("Anchor at: \(anchor.id) timestamp: \(anchor.timestamp). ")
		} 
		returnString.append("\(numPosts) posts. isNewer: \(isNewer). Range: \(indexRange)")
		return returnString
	}
}

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
		sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
		
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
	
	func buildRequest(anchorTime: Int64?, newer: Bool, limit: Int = 50) -> URLRequest {
		var request: URLRequest
		var query: [URLQueryItem] = []
		
		// If we have a text string as part of the filter, and can URL-sanitize the string, use it
		if let queryString = textFilter, let escapedQuery = queryString.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) {
			query.append(URLQueryItem(name: "limit", value: "\(limit)"))
	//		query.append(URLQueryItem(name: "page", value: String(fromOffset)))
			request = NetworkGovernor.buildTwittarV2Request(withPath: "/api/v2/search/tweets/\(escapedQuery)", query: query)
			isSearchQuery = true
		}
		else {
			var query: [URLQueryItem] = []
			if let hashtag = hashtagFilter {
				query.append(URLQueryItem(name:"hashtag", value: hashtag))
			}
			if let mentions = mentionsFilter {
				query.append(URLQueryItem(name:"mentions", value: mentions))
			}
			if let author = authorFilter {
				query.append(URLQueryItem(name:"author", value: author))
			}
			query.append(URLQueryItem(name:"newer_posts", value:newer ? "true" : "false"))
			query.append(URLQueryItem(name:"limit", value:"\(limit)"))
	//		query.append(URLQueryItem(name:"app", value:"plain"))
			if let anchor = anchorTime {
				query.append(URLQueryItem(name: "start", value: String(anchor)))
			}
			request = NetworkGovernor.buildTwittarV2Request(withPath:"/api/v2/stream", query: query)
			isSearchQuery = false
		}
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
	
	func checkLoadRequiredFor(index: Int) {
		if Date() > nextRecalculateTime {
			recalculateCoveredTweets()
		}
		var callAnchor: CallToMake?
		recentNetworkCallsQ.sync {
			if self.coveredIndices.isEmpty {
				callAnchor = CallToMake(index: max (0, index - 25), directionIsNewer: false)
			}
			else {
				if !self.coveredIndices.contains(integersIn: index ..< index + 11) {
					let uncovered = IndexSet(index ..< index + 11).subtracting(self.coveredIndices)
					if let firstUncovered = uncovered.min() {
						callAnchor = CallToMake(index: firstUncovered - 1, directionIsNewer: false)
					}
				}
				let prevCheckRange = max(index - 10, 0) ..< index
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
		
		if let anchor = callAnchor, let numFRCResults = frc?.fetchedObjects?.count,
				anchor.index >= 0, anchor.index < numFRCResults {
			let anchorTweet = frc?.object(at: IndexPath(row: anchor.index, section: 0))
			TwitarrDataManager.shared.loadStreamTweets(anchorTweet: anchorTweet, newer: anchor.directionIsNewer, done: nil)
			let newNetworkResults = TwitarrRecentNetworkCall(anchor: anchorTweet, count: 50, newer: anchor.directionIsNewer)
			recalculateCoveredTweets(adding: newNetworkResults)
		}
		
	}
	
	func userIsViewingCell(at indexPath: IndexPath) {
		checkLoadRequiredFor(index: indexPath.row)
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
	var fetchedData: NSFetchedResultsController<TwitarrPost>
	
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
		let fetchRequest = NSFetchRequest<TwitarrPost>(entityName: "TwitarrPost")
		fetchRequest.predicate = NSPredicate(value: true)
		fetchRequest.sortDescriptors = [ NSSortDescriptor(key: "timestamp", ascending: false)]
		fetchRequest.fetchBatchSize = 50
		fetchedData = NSFetchedResultsController(fetchRequest: fetchRequest, managedObjectContext: coreData.mainThreadContext, 
				sectionNameKeyPath: nil, cacheName: nil)
		
		super.init()
		fetchedData.delegate = self
		do {
			try fetchedData.performFetch()
		}
		catch {
			CoreDataLog.error("Couldn't fetch Twitarr posts.", [ "error" : error ])
		}
	}
	
	// Maps parent post IDs to draft reply text. The most recent 'mainline' post draft is in the "" entry.
	// Probably don't need to save this between launches? Probably should move this to a "ComposeDataManager"?
	var recentTwitarrPostDrafts: [ String : String ] = [:]
	func getDraftPostText(replyingTo: String?) -> String? {
		return recentTwitarrPostDrafts[replyingTo ?? ""]
	}
	func saveDraftPost(text: String?, replyingTo: String?) {
		if let text = text {
			recentTwitarrPostDrafts[replyingTo ?? ""] = text
		}
	}
	
	func loadNewestTweets(_ filterPack: TwitarrFilterPack?,  done: (() -> Void)? = nil) {
		if filterPack?.isContiguousTweets ?? true {
			loadStreamTweets(anchorTweet: nil, newer: false, done: done)
		}
		else if let filter = filterPack {
			loadFilterTweets(filterPack: filter, fromOffset: 0, done: done)
		}
	}
	
	// This call loads a contiguous series of tweets from the stream. When processing the response, we infer 
	// deleted tweets by finding tweets in our CoreData cache that are in the timeframe the response covers but not
	// in the repsonse.
	func loadStreamTweets(anchorTweet: TwitarrPost?, newer: Bool = false, done: (() -> Void)? = nil) {
		var queryParams = [ URLQueryItem(name:"newer_posts", value:newer ? "true" : "false") ]
		queryParams.append(URLQueryItem(name:"limit", value:"50"))
//		queryParams.append(URLQueryItem(name:"app", value:"plain"))
		var anchorTime: Int64 = 0
		if let anchorTweet = anchorTweet {
			anchorTime = newer ? anchorTweet.timestamp + 1 : anchorTweet.timestamp - 1
			queryParams.append(URLQueryItem(name: "start", value: String(anchorTime)))
		}
		
		var request = NetworkGovernor.buildTwittarV2Request(withPath:"/api/v2/stream", query: queryParams)
		NetworkGovernor.addUserCredential(to: &request)
		networkUpdateActive = true
		NetworkGovernor.shared.queue(request) { (package: NetworkResponse) in
			self.networkUpdateActive = false
			if let error = NetworkGovernor.shared.parseServerError(package) {
				NetworkLog.error(error.localizedDescription)
			}
			else if let data = package.data {
//				print (String(decoding:data!, as: UTF8.self))
				let decoder = JSONDecoder()
				do {
					let tweetStream = try decoder.decode(TwitarrV2Stream.self, from: data)
					let morePostsExist = tweetStream.hasNextPage
					self.ingestStreamPosts(posts: tweetStream.streamPosts, anchorTime: anchorTime,
							extendsNewer: newer, morePostsExist: morePostsExist)
				} catch 
				{
					NetworkLog.error("Failure parsing stream tweets.", ["Error" : error, "URL" : request.url as Any])
				} 
			}
			
			done?()
		}
	}
	
	func loadFilterTweets(filterPack: TwitarrFilterPack, fromOffset: Int, done: (() -> Void)? = nil) {

		let request = filterPack.buildRequest(anchorTime: nil, newer: false)
		networkUpdateActive = true
		NetworkGovernor.shared.queue(request) { (package: NetworkResponse) in
			self.networkUpdateActive = false
			if let error = NetworkGovernor.shared.parseServerError(package) {
				NetworkLog.error(error.localizedDescription)
			}
			else if let data = package.data {
				let decoder = JSONDecoder()
				do {
					let tweetStream = try decoder.decode(TwitarrV2TweetQueryResult.self, from: data)
					let morePostsExist = tweetStream.tweets.more
		//			self.consumeStreamPosts(posts: tweetStream.tweets.matches, anchorTime: 0, extendsNewer: false, morePostsExist: morePostsExist)
				} catch 
				{
					NetworkLog.error("Failure parsing search tweets.", ["Error" : error, "URL" : request.url as Any])
				} 
			}
		}
	}
	
	// The optional AnchorTweet specifies that the given posts are directly adjacent to the anchor (that is, if 
	// extendsNewer is true, the oldest tweet in posts is the tweet chronologically after anchor. If anchor is nil, 
	// we can only assume posts can replace the tweets between startTime and endTime.
	// ONLY USE THIS FOR STREAM-CONTIGUOUS POSTS. Not for searches/filters.
	fileprivate func ingestStreamPosts(posts: [TwitarrV2Post], anchorTime: Int64, extendsNewer: Bool, morePostsExist: Bool) {
		LocalCoreData.shared.performNetworkParsing { context in
			context.pushOpErrorExplanation("Failure adding stream tweets to Core Data.")
			
			// Algorithm here is to do a bottom-up insert/update of sub-objects first, and higher-level objects then set their
			// relationship links to the already-established sub-objects. 
		
			// Make a uniqued list of users from the posts, and get them inserted/updated.
			let userArray = posts.map { $0.author }
			UserManager.shared.update(users: userArray, inContext: context)
			
			// Photos, same idea
			let tweetPhotos = Dictionary(posts.compactMap { $0.photo == nil ? nil : ($0.photo!.id, $0.photo!) },
					uniquingKeysWith: { first,_ in first })
			ImageManager.shared.update(photoDetails: tweetPhotos, inContext: context)
			
			// Reactions
			
			// Get all the existing posts in CD that match posts in the call
//			let newPostIDs = posts.map { $0.id }
//			let request = self.coreData.persistentContainer.managedObjectModel.fetchRequestFromTemplate(withName: "TwitarrPostsWithIDs", 
//					substitutionVariables: [ "ids" : newPostIDs ]) as! NSFetchRequest<TwitarrPost>
//			request.fetchLimit = posts.count + 10 
			
			
			// Get the CD cached posts for the same timeframe as the network call. 			
			let endDate = !extendsNewer && anchorTime != 0 ? anchorTime : posts.first?.timestamp ?? 0
			let startDate = extendsNewer && anchorTime != 0 ? anchorTime : posts.last?.timestamp ?? 0
			let request = self.coreData.persistentContainer.managedObjectModel.fetchRequestFromTemplate(withName: "PostsInDateRange", 
					substitutionVariables: [ "startDate" : startDate, "endDate" : endDate ]) as! NSFetchRequest<TwitarrPost>
			request.fetchLimit = posts.count * 3 // Hopefully there will never be a case where 100 out of 150 posts get mod deleted.
//			let request = NSFetchRequest<TwitarrPost>(entityName: "TwitarrPost")
			let cdResults = try request.execute()

			// Remember: While the TweetStream changes get serialized here, that doesn't mean that network calls get 
			// completed in order, or that we haven't made the same call twice somehow.
			var cdPostsDict = Dictionary(cdResults.map { ($0.id, $0) }, uniquingKeysWith: { (first,_) in first })
			for post in posts {
				let removedValue = cdPostsDict.removeValue(forKey: post.id)
				let cdPost = removedValue ?? TwitarrPost(context: context)
				cdPost.buildFromV2(context: context, v2Object: post)
				
				if post.id == posts.last!.id {					
					if !extendsNewer && morePostsExist && cdPost.isInserted {
						cdPost.contigWithOlder = false
					}
				} else {
					// Note: This weird construction is necessary to keep CoreData from over-saving the store.
					cdPost.contigWithOlder == false ? cdPost.contigWithOlder = true : nil
				}
			}
			
			if cdPostsDict.count > 0 {
				print ("Posts To Delete")
			}
			
			// Delete any posts in CD that are in the date range but aren't in the post stream we got from the server.
			// That is, we asked for "The next 50 posts before/after this timestamp." Get the time range from anchor post time
			// to the post farthest from the anchor; any posts in Core Data in that same time range that aren't in the call results
			// must be posts deleted serverside.
//			let endDate = !extendsNewer && anchorTime != 0 ? anchorTime : posts.first?.timestamp ?? 0
//			let startDate = extendsNewer && anchorTime != 0 ? anchorTime : posts.last?.timestamp ?? 0
//			let dateRangeRequest = self.coreData.persistentContainer.managedObjectModel.fetchRequestFromTemplate(withName: "TwitarrPostsToDelete", 
//					substitutionVariables: [ "startDate" : startDate, "endDate" : endDate, "ids" : newPostIDs ]) as! NSFetchRequest<TwitarrPost>
//			dateRangeRequest.fetchLimit = posts.count * 3 // Hopefully there will never be a case where 100 out of 150 posts get mod deleted.
//			let dateRangeResults = try dateRangeRequest.execute()
//			if dateRangeResults.count > 0 {
//				print ("meh")
//			}
//			dateRangeResults.forEach( { context.delete($0) } )
		}
	}
	
	// This is for posts created by the user; the responses from create methods return the post that got made.
	func ingestNewUserPost(post: TwitarrV2Post) {
		TwitarrDataManager.shared.ingestFilterPosts(posts: [post])
	}
		
	// Saves posts in Core Data. Merges with existing Core Data posts. This fn is for result arrays that contain 
	// posts that aren't contiguous in the tweet stream, such as search results.
	func ingestFilterPosts(posts: [TwitarrV2Post]) {
		LocalCoreData.shared.performNetworkParsing { context in
			context.pushOpErrorExplanation("Failure adding stream tweets to Core Data.")
			
			// Algorithm here is to do a bottom-up insert/update of sub-objects first, and higher-level objects then set their
			// relationship links to the already-established sub-objects. 
		
			// Make a uniqued list of users from the posts, and get them inserted/updated.
			let userArray = posts.map { $0.author }
			UserManager.shared.update(users: userArray, inContext: context)
			
			// Photos, same idea
			let tweetPhotos = Dictionary(posts.compactMap { $0.photo == nil ? nil : ($0.photo!.id, $0.photo!) },
					uniquingKeysWith: { first,_ in first })
			ImageManager.shared.update(photoDetails: tweetPhotos, inContext: context)
			
			// Reactions
			
			// Get all the existing posts in CD that match posts in the call
			let newPostIDs = posts.map { $0.id }
			let request = self.coreData.persistentContainer.managedObjectModel.fetchRequestFromTemplate(withName: "TwitarrPostsWithIDs", 
					substitutionVariables: [ "ids" : newPostIDs ]) as! NSFetchRequest<TwitarrPost>
			request.fetchLimit = posts.count + 10 
			let cdResults = try request.execute()

			// Remember: While the TweetStream changes get serialized here, that doesn't mean that network calls get 
			// completed in order, or that we haven't made the same call twice somehow.
			var cdPostsDict = Dictionary(cdResults.map { ($0.id, $0) }, uniquingKeysWith: { (first,_) in first })
			for post in posts {
				let removedValue = cdPostsDict.removeValue(forKey: post.id)
				let cdPost = removedValue ?? TwitarrPost(context: context)
				cdPost.buildFromV2(context: context, v2Object: post)
				
				// Don't modify contigWithOlder, we don't know whether it is or not, and an existing post may
				// have this info already set.
			}
		}
	}

	// For new mainline posts, new posts that are replies, and edits to existing posts
	// Creates a PostOperation, saving all the data needed to post a new tweet, and queues it for posting.
	func queuePost(_ existingDraft: PostOpTweet?, withText: String, image: Data?, mimeType: String?,
			inReplyTo: TwitarrPost? = nil, editing: TwitarrPost? = nil, done: @escaping (PostOpTweet?) -> Void) {
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
			postToQueue.image = image as NSData?
			postToQueue.imageMimetype = mimeType
			
			LocalCoreData.shared.setAfterSaveBlock(for: context) { saveSuccess in 
				DispatchQueue.main.async {
					let mainThreadPost = LocalCoreData.shared.mainThreadContext.object(with: postToQueue.objectID) as? PostOpTweet 
					done(mainThreadPost)
				}
			}
		}
	}
	
}

// The data manager can have multiple delegates, all of which are watching the same results set.
extension TwitarrDataManager: NSFetchedResultsControllerDelegate {
	// MARK: NSFetchedResultsControllerDelegate

	func controllerWillChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
	}

	func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange anObject: Any,
			at indexPath: IndexPath?, for type: NSFetchedResultsChangeType, newIndexPath: IndexPath?) {
	}

    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange sectionInfo: NSFetchedResultsSectionInfo, 
    		atSectionIndex sectionIndex: Int, for type: NSFetchedResultsChangeType) {
	}

	// We can't actually implement this in a multi-delegate model. Also, wth is NSFetchedResultsController doing having a 
	// delegate method that does this?
 //   func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, sectionIndexTitleForSectionName sectionName: String) -> String?
    
	func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
	}
}

// MARK: - V2 API Decoding

struct TwitarrV2Reactions: Codable {
	let count: Int32
	let me: Bool
}

typealias TwitarrV2ReactionsSummary = [ String : TwitarrV2Reactions ]

struct TwitarrV2Post: Codable {
	let id: String
	let author: TwitarrV2UserInfo
	let locked: Bool
	let timestamp: Int64
	let text: String
	let reactions: TwitarrV2ReactionsSummary
	let photo: TwitarrV2PhotoDetails?
	let parentChain: [String]

	enum CodingKeys: String, CodingKey {
		case id
		case author
		case locked
		case timestamp
		case text
		case reactions
		case photo
		case parentChain = "parent_chain"
	}
}

struct TwitarrV2Stream: Codable {
	let status: String
	let hasNextPage: Bool
	let nextPage: Int
	let streamPosts: [TwitarrV2Post]
	
	enum CodingKeys: String, CodingKey {
		case status
		case hasNextPage = "has_next_page"
		case nextPage = "next_page"
		case streamPosts = "stream_posts"
	}
}

struct TwitarrV2QueryText: Codable {
	let text: String
}

struct TwitarrV2TweetQuery: Codable {
	let matches: [TwitarrV2Post]
	let count: Int
	let more: Bool
}

struct TwitarrV2TweetQueryResult: Codable {
	let status: String
	let query: TwitarrV2QueryText
	let tweets: TwitarrV2TweetQuery
}
