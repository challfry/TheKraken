//
//  UserManager.swift
//  Kraken
//
//  Created by Chall Fry on 3/22/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import Foundation
import UIKit

// This is our internal model object for users.
class KrakenUser : NSObject {
	let name: String
	var displayName: String
	
	var emailAddress: String?
	var currentLocation: String?
	var roomNumber: String?
	var realName: String?
	var pronouns: String?
	var homeLocation: String?
	
	var numberOfTweets: Int?
	var numberOfMentions: Int?
	
	// Specific to the logged-in user
	var isStarred: Bool?
	var comment: String? 			// Logged in user's comment string on this user
	
	var lastPhotoUpdated: Int
	@objc dynamic weak var  thumbPhoto:  UIImage?
	var fullPhoto: UIImage?


	// Extra stuff the UserAccount type has
	// role
	// lastLogin time
	// emptyPassword bool
	// unnoticed_alerts
	
	init(with userName: String) {
		name = userName
		displayName = userName
		lastPhotoUpdated = 0
	}
	
	func loadUserThumbnail() {
		if thumbPhoto != nil {
			return
		}
		
		ImageManager.shared.userImageCache.image(forKey:name) { newImage in
			self.thumbPhoto = newImage
		}
	
//		let request = NetworkGovernor.buildTwittarV2Request(withPath:"/api/v2/user/photo/\(name)")
//		NetworkGovernor.shared.queue(request) { (data: Data?, response: URLResponse?) in
//			if let response = response as? HTTPURLResponse {
//				if response.statusCode < 300, let data = data {
//					self.thumbPhoto =  UIImage(data:data)
//				} else 
//				{
//					// Load failed for some reason
//				}
//			}
//		}
	}
}

class UserManager : NSObject {
	static let shared = UserManager()
	private var users = [String: KrakenUser]()
	
	func user(_ userName: String) -> KrakenUser? {
		if let existingUser = users[userName] {
			return existingUser
		}
		else {
			let unknownUser = KrakenUser(with:userName)
			
			// rcf fixme Do not add the unkown user to the users list. Instead, ask the server about this user.
			
			return unknownUser
		}
	}
	
	// Creates a user with this username if none exists.
	func updateUser(_ username: String, displayName: String, lastPhotoUpdated: Int) -> KrakenUser {
	
		// Is there an existing user in the cache?
		if let existingUser = users[username] {
			existingUser.displayName = displayName
			
			// Invalidate the cached photos if the lastPhotoUpdated time changed
			if lastPhotoUpdated > 0 && lastPhotoUpdated > existingUser.lastPhotoUpdated {
				existingUser.thumbPhoto = nil
				existingUser.fullPhoto = nil
				existingUser.lastPhotoUpdated = lastPhotoUpdated
			}
			
			return existingUser
		}
		else {
			let addingUser = KrakenUser(with: username)
			addingUser.displayName = displayName
			addingUser.lastPhotoUpdated = lastPhotoUpdated
			users[addingUser.name] = addingUser
			
			return addingUser
		}
	}
	
}






// Twittar API V2 UserInfo
struct TwitarrV2UserInfo: Codable {
	let username: String
	let displayName: String
	let lastPhotoUpdated: Int
	
	enum CodingKeys: String, CodingKey {
		case username
		case displayName = "display_name"
		case lastPhotoUpdated = "last_photo_updated"
	}
	
	// This initializer exists to ensure a KrakenUser is created for every UserInfo we decode.
	// Since KrakenUsers are in a dictionary, they're effectively uniqued, unlike UserInfo structs.
	init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        username = try container.decode(String.self, forKey: .username)
        displayName = try container.decode(String.self, forKey: .displayName)
        lastPhotoUpdated = try container.decode(Int.self, forKey: .lastPhotoUpdated)
		
		_ = UserManager.shared.updateUser(username, displayName: displayName, lastPhotoUpdated: lastPhotoUpdated)
	}
}

