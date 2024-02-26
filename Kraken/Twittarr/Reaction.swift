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
	@NSManaged public var word: String				// V3 defines "like", "love", "laugh". More may be added later.
	@NSManaged public var bookmark: Bool			// True if the user has bookmarked this content.
	
    // Reactions must have a source of some sort.
	@NSManaged public var sourceTweet: TwitarrPost?
	@NSManaged public var sourceForumPost: ForumPost?
	@NSManaged public var user: KrakenUser?
	
	func getLikeOpKind() -> LikeOpKind {
		switch word {
		case "like": return .like
		case "love": return .love
		case "laugh": return .laugh
		default: return .none
		}
	}
	
	func buildReactionFromLikeAndBookmark(context: NSManagedObjectContext, source: ForumPost, 
			likeType: TwitarrV3LikeType?, bookmark: Bool) {
		TestAndUpdate(\.sourceForumPost, source)
		TestAndUpdate(\.word, likeType?.rawValue ?? "")
		TestAndUpdate(\.bookmark, bookmark)
		
		if let currentUser = CurrentUser.shared.getLoggedInUser(in: context) {
			TestAndUpdate(\.user, currentUser)
		}
	}
	func buildReactionFromLikeAndBookmark(context: NSManagedObjectContext, source: TwitarrPost, 
			likeType: TwitarrV3LikeType?, bookmark: Bool) {
		TestAndUpdate(\.sourceTweet, source)
		TestAndUpdate(\.word, likeType?.rawValue ?? "")
		TestAndUpdate(\.bookmark, bookmark)
		
		if let currentUser = CurrentUser.shared.getLoggedInUser(in: context) {
			TestAndUpdate(\.user, currentUser)
		}
	}
}
