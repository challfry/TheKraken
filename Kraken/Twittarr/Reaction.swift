//
//  Reaction.swift
//  Kraken
//
//  Created by Chall Fry on 6/6/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit
import CoreData

@objc(Reaction) public class Reaction: KrakenManagedObject {
	@NSManaged public var word: String				// "like" is the most common
	
	// How many users have this reaction to this source item. Count is very likely to be larger than the number of 
	// specific known users.
	@NSManaged public var count: Int32				// 
	@NSManaged public var users: Set<KrakenUser> 	// Users known to have given this reaction
	
    
    // Reactions must have a source of some sort.
	@NSManaged public var sourceTweet: TwitarrPost?
	@NSManaged public var sourceForumPost: ForumPost?

	func buildFromV2(context: NSManagedObjectContext, post: TwitarrPost, v2Object: TwitarrV2Reactions, reactionName: String) {
		TestAndUpdate(\.word, reactionName)
		TestAndUpdate(\.count, v2Object.count)
		TestAndUpdate(\Reaction.sourceTweet, post)
				
		if let userInContext = CurrentUser.shared.getLoggedInUser(in: context) {
			let selfUser = users.first { object in return object.username == userInContext.username }
			if v2Object.me, selfUser == nil {
				users.insert(userInContext)
			}
			else if !v2Object.me, selfUser != nil {
				users.remove(userInContext)
			}
		}
	}
}
