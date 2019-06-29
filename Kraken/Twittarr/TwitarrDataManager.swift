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
    
    @NSManaged public var reactionOps: NSMutableSet?
    @objc dynamic public var reactionOpsCount: Int = 0
    
    @objc dynamic public var reactionDict: NSMutableDictionary?
    
	public override func awakeFromFetch() {
		super.awakeFromFetch()
    	let dict = NSMutableDictionary()
		for reaction in reactions {
			dict.setValue(reaction, forKey: reaction.word)
		}
		reactionDict = dict
		reactionOpsCount = reactionOps?.count ?? 0
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
		
		for (reactionName, reactionV2Obj) in v2Object.reactions {
			var reaction = reactions.first { object in return object.word == reactionName }
			if reaction == nil {
				let r = Reaction(context: context)
				reactions.insert(r)	
				reaction = r
			}
			reaction?.buildFromV2(context: context, post: self, v2Object: reactionV2Obj, reactionName: reactionName)
		}

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
		let context = LocalCoreData.shared.networkOperationContext
		context.perform {
			guard let currentUser = CurrentUser.shared.loggedInUser,
					let thisPost = context.object(with: self.objectID) as? TwitarrPost,
					let thisUser = context.object(with: currentUser.objectID) as? KrakenUser else { return }
			
			// Check for existing op for this user, with this word
			if let existingOp = thisPost.getPendingUserReaction(reactionWord) {
				existingOp.isAdd = newState
			}
			else {
				let op = PostOpTweetReaction(context: context)
				op.reactionWord = reactionWord
				op.sourcePost = thisPost
				op.isAdd = newState
				op.author = thisUser
				op.readyToSend = true
				op.originalPostTime = Date()
			}
			
			do {
				try context.save()
			}
			catch {
				CoreDataLog.error("Couldn't save context.", ["error" : error])
			}
		}
	}
	
	func cancelReactionOp(_ reactionWord: String) {
		if let existingOp = getPendingUserReaction(reactionWord) {
			let context = LocalCoreData.shared.networkOperationContext
			context.perform {
				if let reaction = context.object(with: existingOp.objectID) as? PostOpTweetReaction, !reaction.sentNetworkCall {
					context.delete(reaction)
					do {
						try context.save()
					}
					catch {
						CoreDataLog.error("Couldn't save context.", ["error" : error])
					}
				}
			}
		}
	}
	
}

fileprivate class RecentNetworkCall : NSObject {
	var mostRecent: TwitarrPost 
	var earliest: TwitarrPost
	var mostRecentIndex: Int = -1
	var earliestIndex: Int = -1
	let callTime: Date
	
	init(mostRecent: TwitarrPost, earliest: TwitarrPost) {
		self.mostRecent = mostRecent
		self.earliest = earliest
		self.callTime = Date()
	}
	
	func updateIndices(frc: NSFetchedResultsController<TwitarrPost>) {
		if let mostRecentIndexPath = frc.indexPath(forObject: mostRecent)
		{
			mostRecentIndex = mostRecentIndexPath.last!
		}
		else {
			mostRecentIndex = -1
		}
		if let earliestIndexPath = frc.indexPath(forObject: earliest)
		{
			earliestIndex = earliestIndexPath.last!
		}
		else {
			earliestIndex = -1
		}
	}
	
	func covers(index: Int) -> Bool {
		guard earliestIndex != -1 && mostRecentIndex != -1 else {
			return false
		}
		return index >= earliestIndex && index <= mostRecentIndex 
	}
}

// TwitarrDataManager provides access to tweets.
//
// That is, it is responsible for initiating and processing server calls to get tweets and associated data; it maintains 
// a local cache of that data; and it provides a unified API such that online and offline access to tweets work the same way.
// This includes searching for tweets--when offline, searching the tweet stream is performed locally, whereas the same search
// initiates network requests when online.
class TwitarrDataManager: NSObject {
	static let shared = TwitarrDataManager()
	
	private let coreData = LocalCoreData.shared
	var filter: String?
	var fetchedData: NSFetchedResultsController<TwitarrPost>
	fileprivate var recentNetworkCalls: [RecentNetworkCall] = []
	private let recentNetworkCallsQ = DispatchQueue(label:"RecentNetworkCalls mutation serializer")
	var viewDelegates: [NSObject & NSFetchedResultsControllerDelegate] = []

	// Once we've loaded the very first tweet, olderPosts gets .false. If we scroll backwards, get older tweets, 
	// but not the first ever, it'll get .true. NewerPostsExist is only .true if we scroll forward, load new posts,
	// and the server returns N new posts but says there's even newer ones available. 
	var newerPostsExist: Bool? 
	var olderPostsExist: Bool?
	var totalTweets: Int = 0
	
	//
	var lastError : Error?
	
	init(filterString: String? = nil) {
		filter = filterString
		let fetchRequest = NSFetchRequest<TwitarrPost>(entityName: "TwitarrPost")
		fetchRequest.sortDescriptors = [ NSSortDescriptor(key: "timestamp", ascending: false)]
		fetchRequest.fetchBatchSize = 50
		fetchedData = NSFetchedResultsController(fetchRequest: fetchRequest, managedObjectContext: coreData.mainThreadContext, 
				sectionNameKeyPath: nil, cacheName: nil)
		
		if let filter = filter {
			fetchRequest.predicate = NSPredicate(format: "text contains %@", filter)
		}

		super.init()
		fetchedData.delegate = self
	}
	
	func addDelegate(_ newDelegate: NSObject & NSFetchedResultsControllerDelegate) {
		if !viewDelegates.contains(where: { $0 === newDelegate } ) {
			viewDelegates.insert(newDelegate, at: 0)
		}
	}
	
	func removeDelegate(_ oldDelegate: NSObject & NSFetchedResultsControllerDelegate) {
		viewDelegates.removeAll(where: { $0 === oldDelegate } )
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

	func requestTweet(atIndex requestIndex: Int) {
		// Check our recent network calls to see if we've requested this tweet from the server recently
		recentNetworkCallsQ.async {
			let cutoffDate = Date(timeIntervalSinceNow: -60 * 5)
			self.recentNetworkCalls = self.recentNetworkCalls.compactMap( { $0.callTime > cutoffDate ? $0 : nil } )
			let indexCovered = self.recentNetworkCalls.reduce( false, { $0 || $1.covers(index: requestIndex) } )

			if !indexCovered {
				
			}	
		}
		
	}
	
	
	func loadNewestTweets(done: (() -> Void)? = nil) {
		loadStreamTweets(anchorTweet: nil) {	
			done?()
		}
	}
	
	func loadStreamTweets(anchorTweet: TwitarrPost?, newer: Bool = false, done: (() -> Void)? = nil) {
		var queryParams = [ URLQueryItem(name:"newer_posts", value:newer ? "true" : "false") ]
		queryParams.append(URLQueryItem(name:"limit", value:"50"))
//		queryParams.append(URLQueryItem(name:"app", value:"plain"))
		var anchorTime: Int64 = 0
		if let anchorTweet = anchorTweet {
			anchorTime = newer ? anchorTweet.timestamp + 1 : anchorTweet.timestamp - 1
			queryParams.append(URLQueryItem(name: "start", value: String(anchorTime)))
		}
		
		let request = NetworkGovernor.buildTwittarV2Request(withPath:"/api/v2/stream", query: queryParams)
		NetworkGovernor.shared.queue(request) { (data: Data?, response: URLResponse?) in
			if let response = response as? HTTPURLResponse, response.statusCode < 300,
					let data = data {
//				print (String(decoding:data!, as: UTF8.self))
				let decoder = JSONDecoder()
				do {
					let tweetStream = try decoder.decode(TwitarrV2Stream.self, from: data)
					let morePostsExist = tweetStream.hasNextPage
					self.addPostsToStream(posts: tweetStream.streamPosts, anchorTime: anchorTime,
							extendsNewer: newer, morePostsExist: morePostsExist)
				} catch 
				{
					NetworkLog.error("Failure parsing stream tweets.", ["Error" : error, "URL" : request.url as Any])
				} 
			}
			
			done?()
		}
	}
	
	func loadSearchTweets(fromOffset: Int, done: (() -> Void)? = nil) {
		guard let filter = filter, let escapedQuery = filter.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
			CoreDataLog.error("Need to have a filter set to loadSearchTweets.")
			return
		}
	
		let queryParams = [ URLQueryItem(name: "limit", value: "50"), URLQueryItem(name: "page", value: String(fromOffset))]

		let request = NetworkGovernor.buildTwittarV2Request(withPath: "/api/v2/search/tweets/\(escapedQuery)", query: queryParams)
		NetworkGovernor.shared.queue(request) { (data: Data?, response: URLResponse?) in
			if let response = response as? HTTPURLResponse, response.statusCode < 300,
					let data = data {
				let decoder = JSONDecoder()
				do {
					let tweetStream = try decoder.decode(TwitarrV2TweetQueryResult.self, from: data)
					let morePostsExist = tweetStream.tweets.more
		//			self.addPostsToStream(posts: tweetStream.tweets.matches, anchorTime: 0, extendsNewer: false, morePostsExist: morePostsExist)
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
	fileprivate func addPostsToStream(posts: [TwitarrV2Post], anchorTime: Int64, extendsNewer: Bool, morePostsExist: Bool) {
		let context = coreData.networkOperationContext
		context.perform {
			do {
				// Algorithm here is to do a bottom-up insert/update of sub-objects first, and higher-level objects then set their
				// relationship links to the already-established sub-objects. 
			
				// Make a uniqued list of users from the posts, and get them inserted/updated.
				let jsonUsers = Dictionary(posts.map { ($0.author.username, $0.author) }, uniquingKeysWith: { (first,_) in first })
				UserManager.shared.update(users: jsonUsers, inContext: context)
				
				// Photos, same idea
				let tweetPhotos = Dictionary(posts.compactMap { $0.photo == nil ? nil : ($0.photo!.id, $0.photo!) },
						uniquingKeysWith: { first,_ in first })
				ImageManager.shared.update(photoDetails: tweetPhotos, inContext: context)
				
				// Reactions
				
				// Get the CD cached posts for the same timeframe as the network call. 			
				let endDate = !extendsNewer && anchorTime != 0 ? anchorTime : posts.first?.timestamp ?? 0
				let startDate = extendsNewer && anchorTime != 0 ? anchorTime : posts.last?.timestamp ?? 0
				let request = self.coreData.persistentContainer.managedObjectModel.fetchRequestFromTemplate(withName: "PostsInDateRange", 
						substitutionVariables: [ "startDate" : startDate, "endDate" : endDate ]) as! NSFetchRequest<TwitarrPost>
				request.fetchLimit = posts.count * 3 // Hopefully there will never be a case where 100 out of 150 posts get mod deleted.
		//		let request = NSFetchRequest<TwitarrPost>(entityName: "TwitarrPost")
				let cdResults = try request.execute()

				// Remember: While the TweetStream changes get serialized here, that doesn't mean that network calls get 
				// completed in order, or that we haven't made the same call twice somehow.
				var cdPostsDict = Dictionary(cdResults.map { ($0.id, $0) }, uniquingKeysWith: { (first,_) in first })
				var mostRecent: TwitarrPost?
				var earliest: TwitarrPost?
				for post in posts {
					let cdPost = cdPostsDict.removeValue(forKey: post.id) ?? TwitarrPost(context: context)
					cdPost.buildFromV2(context: context, v2Object: post)
					
					if post.id == posts.first!.id {
						mostRecent = cdPost
					}
					else if post.id == posts.last!.id {
						earliest = cdPost
						
						if !extendsNewer && morePostsExist && cdPost.isInserted && self.filter == nil {
							cdPost.contigWithOlder = false
						}
					} else if self.filter == nil {
						// Note: This weird construction is necessary to keep CoreData from over-saving the store.
						cdPost.contigWithOlder == false ? cdPost.contigWithOlder = true : nil
					}
					
					// When there's a filter, we don't know if posts we add to the stream are contiguous. 
					if cdPost.isInserted && self.filter != nil {
						cdPost.contigWithOlder = false
					}
				}
				
				// Delete any posts in CD that are in the date range but aren't in the post stream we got from the server.
				if self.filter == nil {
					cdPostsDict.forEach( {key, value in context.delete(value) } )
				}
				
				if let earliest = earliest, let mostRecent = mostRecent {
					let newNetworkResults = RecentNetworkCall(mostRecent: mostRecent, earliest: earliest)
					self.recentNetworkCallsQ.async {
						self.recentNetworkCalls.insert(newNetworkResults, at: 0)
						self.recentNetworkCalls.forEach( { $0.updateIndices(frc: self.fetchedData) } )
					}
				}
								
				try context.save()
			}
			catch {
				CoreDataLog.error("Failure adding stream tweets to CD.", ["Error" : error])
			}
		}
	}
	
	// For new mainline posts and new posts that are replies. Not for edits of existing posts.
	func queueNewPost(withText: String, image: Data?, inReplyTo: TwitarrPost? = nil) {
		let context = LocalCoreData.shared.networkOperationContext
		context.perform {
			guard let currentUser = CurrentUser.shared.getLoggedInUser(in: context) else { return }
			
			var parentPost: TwitarrPost? = nil
			if let parent = inReplyTo {
				parentPost = context.object(with: parent.objectID) as? TwitarrPost
			}
			
			let newPost = PostOpTweet(context: context)
			newPost.text = withText
			newPost.parent = parentPost
			newPost.readyToSend = false
			newPost.sentNetworkCall = false
			newPost.originalPostTime = Date()
			newPost.author = currentUser
			newPost.image = image as NSData?
			
			do {
				try context.save()
			}
			catch {
				CoreDataLog.error("Couldn't save context.", ["error" : error])
			}
		}
	}
	
}

// The data manager can have multiple delegates, all of which are watching the same results set.
extension TwitarrDataManager : NSFetchedResultsControllerDelegate {

	func controllerWillChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
		viewDelegates.forEach( { $0.controllerWillChangeContent?(controller) } )
	}

	func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange anObject: Any,
			at indexPath: IndexPath?, for type: NSFetchedResultsChangeType, newIndexPath: IndexPath?) {
		viewDelegates.forEach( { $0.controller?(controller, didChange: anObject, at: indexPath, for: type, newIndexPath: newIndexPath) } )
	}

    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange sectionInfo: NSFetchedResultsSectionInfo, 
    		atSectionIndex sectionIndex: Int, for type: NSFetchedResultsChangeType) {
    	viewDelegates.forEach( { $0.controller?(controller, didChange: sectionInfo, atSectionIndex: sectionIndex, for: type) } )		
	}

	// We can't actually implement this in a multi-delegate model. Also, wth is NSFetchedResultsController doing having a 
	// delegate method that does this?
 //   func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, sectionIndexTitleForSectionName sectionName: String) -> String?
    
	func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
		viewDelegates.forEach( { $0.controllerDidChangeContent?(controller) } )
	}
}


// MARK: - V2 API Decoding

struct TwitarrV2Reactions: Codable {
	let count: Int32
	let me: Bool
}

struct TwitarrV2Post: Codable {
	let id: String
	let author: TwitarrV2UserInfo
	let locked: Bool
	let timestamp: Int64
	let text: String
	let reactions: [ String: TwitarrV2Reactions ]
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
