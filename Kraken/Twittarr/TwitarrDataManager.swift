//
//  TwitarrDataManager.swift
//  Kraken
//
//  Created by Chall Fry on 3/22/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import Foundation


// A contiguous slice of tweets from the twitarr stream
class TweetChunk: CustomStringConvertible {
	var tweets = [TwitarrV2Post]()
	
//	var hasNewer: Bool = false
//	var hasOlder: Bool = false
	
	// Computed props for newest id, oldest id, newest timestamp, oldest timestamp
	func newestTimestamp() -> Int {
		let timestamp = tweets.first?.timestamp ?? 0
		return timestamp
	}
	
	func oldestTimestamp() -> Int {
		let timestamp = tweets.last?.timestamp ?? 0
		return timestamp
	}
	
    var description: String {
        let result = tweets.reduce("\(tweets.count) tweets in chunk:\n", { str, post in
        	str + "    \(post)\n"
        })
        return result 
    }
}


class TwitarrDataManager: NSObject {
	static let shared = TwitarrDataManager()
	
	// item 0 of tweetChunk 0 is the most recent tweet in the stream -- the one posted closest to now.
	// Both within chunks and in the stream, the most-recent item is at 0.
	// Therefore, the timeline always goes from tweet N in a chunk to a discontinuity (where tweets aren't loaded)
	// to tweet 0 in the next chunk.
	public var tweetStream = [TweetChunk]()
	var totalTweets: Int = 0
	private let tweetStreamQ = DispatchQueue(label:"TweetStream mutation serializer")
	
	// Once we've loaded the very first tweet, olderPosts gets .false. If we scroll backwards, get older tweets, 
	// but not the first ever, it'll get .true. NewerPostsExist is only .true if we scroll forward, load new posts,
	// and the server returns N new posts but says there's even newer ones available. 
	var newerPostsExist: Bool? 
	var olderPostsExist: Bool?
	
	//
	var lastError : Error?
	
	func loadNewestTweets(done: (() -> Void)? = nil) {
		loadStreamTweets(anchorTweet: nil) {	

			// testing
			self.tweetStreamQ.async {
				self.loadStreamTweets(anchorTweet:self.tweetStream.last?.tweets.last) {
					print(self.tweetStream)
				}
			}
			
			done?()
		}
	}
	
	func loadStreamTweets(anchorTweet: TwitarrV2Post?, newer: Bool = false, done: (() -> Void)? = nil) {
		var queryParams = [ URLQueryItem(name:"newer_posts", value:newer ? "true" : "false") ]
		if let anchorTweet = anchorTweet {
			let startTime = newer ? anchorTweet.timestamp + 1 : anchorTweet.timestamp - 1
			queryParams.append(URLQueryItem(name: "start", value: String(startTime)))
		}
		
		let request = NetworkGovernor.buildTwittarV2Request(withPath:"/api/v2/stream", query: queryParams)
		NetworkGovernor.shared.queue(request) { (data: Data?, response: URLResponse?) in
			if let response = response as? HTTPURLResponse, response.statusCode < 300,
					let data = data {
//				print (String(decoding:data!, as: UTF8.self))
				let decoder = JSONDecoder()
				if let tweetStream = try? decoder.decode(TwitarrV2Stream.self, from: data) {
					let morePostsExist = tweetStream.hasNextPage
					self.addPostsToStream(posts: tweetStream.streamPosts, anchorTweet:anchorTweet,
							extendsNewer: newer, morePostsExist: morePostsExist)
				}
			}
			
			done?()
		}
		
	}
	
	// If there's a post with that timestamp, returns its location as a (chunk,index) tuple
	// If orOlder is TRUE, returns the location of the nearest tweet occuring before timestamp.
	// Note that in the case where the timestamp falls betwen 2 chunks, if orOlder is TRUE we'll return index 0 of
	// the next-oldest chunk, and if orOlder is FALSE we return the last index in the previous (newer) chunk.
	private func findPostLoc(at timestamp:Int, orOlder: Bool) -> (chunk: Int, index: Int) {
		if (orOlder) {
			if let chunk = tweetStream.firstIndex( where: { $0.oldestTimestamp() <= timestamp }),
					let index = tweetStream[chunk].tweets.firstIndex( where: { $0.timestamp <= timestamp }) {
				return (chunk, index)
			}
			
			// If the given timestamp is older than the oldest post in our cache, return index 0 of a new chunk
		//	if let oldestTimestamp = tweetStream.last?.oldestTimestamp(), oldestTimestamp > timestamp {
				return (tweetStream.count, 0)
		//	}
		}
		else {
			if let chunk = tweetStream.lastIndex( where: { $0.newestTimestamp() >= timestamp }),
					let index = tweetStream[chunk].tweets.lastIndex( where: { $0.timestamp >= timestamp }) {
				return (chunk, index)
			}
			
			// If the given timestamp is newer than the newest post in our cache, return index 0 of chunk -1
		//	if let newestTimestamp = tweetStream.first?.newestTimestamp(), newestTimestamp < timestamp {
				return (-1, 0)
		//	}
		}
	}
	
	
	// The optional AnchorTweet specifies that the given posts are directly adjacent to the anchor (that is, if 
	// extendsNewer is true, the oldest tweet in posts is the tweet chronologically after anchor. If anchor is nil, 
	// we can only assume posts can replace the tweets between startTime and endTime.
	private func addPostsToStream(posts: [TwitarrV2Post], anchorTweet: TwitarrV2Post?, extendsNewer: Bool, morePostsExist: Bool) {

		// Remember: While the TweetStream changes get serialized here, that doesn't mean that network calls get 
		// completed in order, or that we haven't made the same call twice somehow.
		tweetStreamQ.async {
			if self.tweetStream.isEmpty {
				let newChunk = TweetChunk()
				newChunk.tweets = posts
				self.tweetStream.append(newChunk)
				self.totalTweets = posts.count
				
				if (extendsNewer) {
					self.newerPostsExist = morePostsExist
				}
				else {
					self.olderPostsExist = morePostsExist
				}
			}
			else {
				if var oldestPostTimestamp = posts.last?.timestamp, var newestPostTimestamp = posts.first?.timestamp {

					var allDone = false
					if let anchor = anchorTweet {
						let anchorPostLoc = self.findPostLoc(at: anchor.timestamp, orOlder: false)
						if anchorPostLoc.chunk >= 0 && 
								anchor.id == self.tweetStream[anchorPostLoc.chunk].tweets[anchorPostLoc.index].id {
							if extendsNewer {
								let newestLoc = self.findPostLoc(at: newestPostTimestamp, orOlder:true)
								let chunk = self.tweetStream[anchorPostLoc.chunk]
								let replacementStartIndex = newestLoc.chunk == anchorPostLoc.chunk ? newestLoc.index : 0
								let replacementEndIndex = anchorPostLoc.index
								chunk.tweets.replaceSubrange(replacementStartIndex..<replacementEndIndex, with: posts)
								
								//
								if newestLoc.chunk < anchorPostLoc.chunk {
									// Coalesce the prefix (if any) of newestChunk into anchorChunk.
									let newestChunk = self.tweetStream[newestLoc.chunk]
									chunk.tweets.insert(contentsOf: newestChunk.tweets[0..<newestLoc.index], at: 0)
							
									// Now remove all the chunks that have been coalesced. 
									self.tweetStream.removeSubrange(newestLoc.chunk..<anchorPostLoc.chunk)
								}
							}
							else {
								let oldestLoc = self.findPostLoc(at: oldestPostTimestamp, orOlder:false)
								let chunk = self.tweetStream[anchorPostLoc.chunk]
								let replacementStartIndex = anchorPostLoc.index + 1
								let replacementEndIndex = oldestLoc.chunk == anchorPostLoc.chunk ? oldestLoc.index + 1 : 
										chunk.tweets.count
								chunk.tweets.replaceSubrange(replacementStartIndex..<replacementEndIndex, with: posts)
								
								//
								if oldestLoc.chunk > anchorPostLoc.chunk {
									// Coalesce the suffix (if any) of oldestChunk into anchorChunk.
									let oldestChunk = self.tweetStream[oldestLoc.chunk]
									chunk.tweets.append(contentsOf: oldestChunk.tweets.suffix(from:oldestLoc.index + 1))
							
									// Now remove all the chunks that have been coalesced. 
									self.tweetStream.removeSubrange((anchorPostLoc.chunk + 1)...oldestLoc.chunk)
								}
							}
							
							allDone = true
						}

						// If we have an anchor tweet but can't find it, modify our date range to be just before/after
						// the anchor; this handles the case where the tweet before/after the anchor has been deleted 
						// and no longer shows up in the stream.
						if extendsNewer {
							oldestPostTimestamp = anchor.timestamp + 1
						}
						else {
							newestPostTimestamp = anchor.timestamp - 1
						}
					}
					
					// This part is for when we don't have an anchor that we can find.
					if !allDone {
						let oldestLoc = self.findPostLoc(at: oldestPostTimestamp, orOlder:false)
						let newestLoc = self.findPostLoc(at: newestPostTimestamp, orOlder:true)
						
						if oldestLoc.chunk == newestLoc.chunk && oldestLoc.chunk < self.tweetStream.count {
							let chunk = self.tweetStream[oldestLoc.chunk]
							chunk.tweets.replaceSubrange(newestLoc.index...oldestLoc.index, with: posts)
						}
						else if oldestLoc.chunk < newestLoc.chunk {
							// Between chunks. With no anchor, we have to insert a new chunk here.
							let newChunk = TweetChunk()
							newChunk.tweets = posts
							self.tweetStream.insert(newChunk, at:newestLoc.chunk)
						}
						else {
							// We span chunks. Need to merge.
							var newestTweets = self.tweetStream[newestLoc.chunk].tweets.prefix(through:newestLoc.index)
							newestTweets.append(contentsOf: posts)
							newestTweets.append(contentsOf: self.tweetStream[oldestLoc.chunk].tweets.suffix(from:oldestLoc.index + 1))
							self.tweetStream[newestLoc.chunk].tweets = Array(newestTweets)
							
							// Now, delete chunks that got merged
							self.tweetStream.removeSubrange((newestLoc.chunk + 1)...oldestLoc.chunk)
						}
					}
					
					// Get our sum of tweets
					self.totalTweets = self.tweetStream.reduce(0) { $0 + $1.tweets.count }
					
					// Record whether newer/older posts exist in the timeline
					if extendsNewer, let newNewestTimestamp = self.tweetStream.first?.newestTimestamp(),
							newNewestTimestamp == newestPostTimestamp {
						self.newerPostsExist = morePostsExist
					}
					else if !extendsNewer, let newOldestTimestamp = self.tweetStream.last?.oldestTimestamp(),
							newOldestTimestamp == oldestPostTimestamp {
						self.olderPostsExist = morePostsExist
					}
				}
			}
		}
	}
	
}


struct TwitarrV2Reactions: Codable {
	let count: Int
	let me: Bool
}

struct TwitarrV2Post: Codable {
	let id: String
	let author: TwitarrV2UserInfo
	let locked: Bool
	let timestamp: Int
	let text: String
	let reactions: [String: TwitarrV2Reactions ]
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

