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
	
	func getLikeOpKind() -> LikeOpKind {
		switch word {
		case "like": return .like
		case "love": return .love
		case "laugh": return .laugh
		default: return .none
		}
	}
}
