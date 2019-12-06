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
		
		//
//		ForumReadCount.numPostsRead = postCount - v2Object.count

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
	}
}

@objc(ForumPost) public class ForumPost: KrakenManagedObject {
    @NSManaged public var id: String
    @NSManaged public var text: String
    @NSManaged public var timestamp: Int64
    
    @NSManaged public var author: KrakenUser
    @NSManaged public var forum: ForumThread
//	@NSManaged public var photos: Set<PhotoDetails>
    @NSManaged public var photos: NSMutableOrderedSet	// PhotoDetails
    
	func buildFromV2(context: NSManagedObjectContext, v2Object: TwitarrV2ForumPost, thread: ForumThread) {
		TestAndUpdate(\.id, v2Object.id)
		TestAndUpdate(\.text, v2Object.text)
		TestAndUpdate(\.timestamp, v2Object.timestamp)
		TestAndUpdate(\.forum, thread)
		
		if author.username != v2Object.author.username {
			let userPool: [String : KrakenUser ] = context.userInfo.object(forKey: "Users") as! [String : KrakenUser] 
			if let cdAuthor = userPool[v2Object.author.username] {
				author = cdAuthor
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
}

// Tracks the number of posts that the given user has read in the given thread.
@objc(ForumReadCount) public class ForumReadCount: KrakenManagedObject {
    @NSManaged public var numPostsRead: Int64		// How many posts this user has read in this thread.
    												// May not be == to the number of posts we've loaded.

    @NSManaged public var forumThread: ForumThread
    @NSManaged public var user: KrakenUser

}


class ForumsDataManager: NSObject {
	static let shared = ForumsDataManager()

	private let coreData = LocalCoreData.shared
	var lastError : ServerError?

	func loadForumThreads(fromOffset: Int, done: @escaping () -> Void) {
	
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
			//	print (String(data: data, encoding: .utf8))
				let decoder = JSONDecoder()
				do {
					let response = try decoder.decode(TwitarrV2GetForumsResponse.self, from: data)
					self.parseForumThreads(from: response.forumThreads)
				}
				catch {
					NetworkLog.error("Failure parsing Forums response.", ["Error" : error, "url" : request.url as Any])
				} 
			}
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
		}
	}
	
	
	func parseNewThreadPosts(from thread: TwitarrV2ForumThread) {
		LocalCoreData.shared.performNetworkParsing { context in 
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
	let newPosts: Bool?
	
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
	let latestRead: Int64
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
	let new: Bool
	
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
