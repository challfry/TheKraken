//
//  UserManager.swift
//  Kraken
//
//  Created by Chall Fry on 3/22/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import Foundation
import UIKit
import CoreData

// This is our internal model object for users.
@objc(KrakenUser) public class KrakenUser : KrakenManagedObject {
	@NSManaged public var username: String
	@NSManaged public var displayName: String
	@NSManaged public var realName: String?
	@NSManaged public var pronouns: String?
	
	@NSManaged public var emailAddress: String?
	@NSManaged public var currentLocation: String?
	@NSManaged public var roomNumber: String?
	@NSManaged public var homeLocation: String?
	
	@NSManaged public var numberOfTweets: Int32
	@NSManaged public var numberOfMentions: Int32
	
	@NSManaged public var lastPhotoUpdated: Int64
	@NSManaged public var thumbPhotoData: Data?
	
	@objc dynamic public var thumbPhoto: UIImage?
	@objc dynamic weak var fullPhoto: UIImage?
	
	// Only follow this link when parsing! This goes to all comments *others* have left, including anyone who logged into this device!
	@NSManaged private var commentedUpon: [CommentsAndStars]?
	
	func buildFromV2UserInfo(context: NSManagedObjectContext, v2Object: TwitarrV2UserInfo)
	{
		TestAndUpdate(\.username, v2Object.username)
		TestAndUpdate(\.displayName, v2Object.displayName)
		TestAndUpdate(\.lastPhotoUpdated, v2Object.lastPhotoUpdated)
	}
	
	func buildFromV2UserProfile(context: NSManagedObjectContext, v2Object: TwitarrV2UserProfile) {
		TestAndUpdate(\.username, v2Object.username)
		TestAndUpdate(\.displayName, v2Object.displayName)
		TestAndUpdate(\.realName, v2Object.realName)
		TestAndUpdate(\.pronouns, v2Object.pronouns)

		TestAndUpdate(\.emailAddress, v2Object.emailAddress)
		TestAndUpdate(\.homeLocation, v2Object.homeLocation)
		TestAndUpdate(\.currentLocation, v2Object.currentLocation)
		TestAndUpdate(\.roomNumber, v2Object.roomNumber)

		TestAndUpdate(\.lastPhotoUpdated, v2Object.lastPhotoUpdated)
		TestAndUpdate(\.numberOfTweets, v2Object.numberOfTweets)
		TestAndUpdate(\.numberOfMentions, v2Object.numberOfMentions)
		
		if let loggedInUser = CurrentUser.shared.loggedInUser {
			var commentToUpdate = commentedUpon?.first(where: { $0.commentingUser.username == loggedInUser.username } )
			
			// Only create a comment object if there's some content to put in it
			if commentToUpdate == nil && (v2Object.comment != nil || v2Object.starred != nil) {
				commentToUpdate = CommentsAndStars(context: context)
			}
			
			commentToUpdate?.build(context: context, userCommentedOn: self, loggedInUser: loggedInUser, 
					comment: v2Object.comment, isStarred: v2Object.starred)
		}

	}


	// Extra stuff the UserAccount type has
	// role
	// lastLogin time
	// emptyPassword bool
	// unnoticed_alerts
		
	func loadUserThumbnail() {
		// Is the UIImage already built?
		if thumbPhoto != nil {
			return
		}
		
		// Can we build the photo from the CoreData cache?
		if thumbPhotoData != nil, let data = thumbPhotoData {
			thumbPhoto = UIImage(data: data)
		}
		
		let request = NetworkGovernor.buildTwittarV2Request(withPath:"/api/v2/user/photo/\(username)")
		NetworkGovernor.shared.queue(request) { (data: Data?, response: URLResponse?) in
			if let response = response as? HTTPURLResponse {
				if response.statusCode < 300, let data = data {
					DispatchQueue.main.async { 
						self.thumbPhotoData = data
						self.thumbPhoto = UIImage(data: data)
					}
				} else 
				{
					// Load failed for some reason
				}
			}
		}
	}
}

class UserManager : NSObject {
	static let shared = UserManager()
	private let container = LocalCoreData.shared.persistentContainer

		
	func user(_ userName: String) -> KrakenUser? {
		let context = container.viewContext
		var result: KrakenUser?
		context.performAndWait {
			do {
				let request = container.managedObjectModel.fetchRequestFromTemplate(withName: "FindAUser", 
						substitutionVariables: [ "username" : userName ]) as! NSFetchRequest<KrakenUser>
				let results = try request.execute()
				result = results.first
			}
			catch {
				print (error)
			}
		}
		
		return result
	}
	
	func loadUserProfile(_ username: String) -> KrakenUser? {
	
		// The background context we use to save data parsed from network calls CAN use the object ID but CANNOT reference the object
		let krakenUser = user(username)
		let krakenUserID = krakenUser?.objectID
		
		let request = NetworkGovernor.buildTwittarV2Request(withPath: "/api/v2/user/profile/\(username)", query: nil)
		NetworkGovernor.shared.queue(request) { (data: Data?, response: URLResponse?) in
			if let response = response as? HTTPURLResponse, response.statusCode < 300,
					let data = data {
//				print (String(decoding:data!, as: UTF8.self))
				let decoder = JSONDecoder()
				do {
					let profileResponse = try decoder.decode(TwitarrV2UserProfileResponse.self, from: data)
					self.updateProfile(for: krakenUserID, from: profileResponse)
				} catch 
				{
					print (error)
				} 
			}
		}
		return krakenUser
	}
	
	func updateProfile(for objectID: NSManagedObjectID?, from response: TwitarrV2UserProfileResponse) {
		guard response.status == "ok" else
		{
			return
		}
		let context = container.newBackgroundContext()
		context.perform {
			do {
				// If we have an objectID, use it to get the KrakenUser. Else we do a search.
				var krakenUser: KrakenUser?
				if let objectID = objectID {
					krakenUser = try context.existingObject(with: objectID) as? KrakenUser
				}
				else {
					let request = self.container.managedObjectModel.fetchRequestFromTemplate(withName: "FindAUser", 
								substitutionVariables: [ "username" : response.user.username ]) as! NSFetchRequest<KrakenUser>
					let results = try request.execute()
					krakenUser = results.first
				}
				if let krakenUser = krakenUser {
					krakenUser.buildFromV2UserProfile(context: context, v2Object: response.user)
					try context.save()
				}
			}
			catch
			{
				print (error)
			}
		}
	}
	
	func update(users origUsers: [ String : TwitarrV2UserInfo], inContext context: NSManagedObjectContext) {
		do {
			var users = origUsers
			let usernames = Array(users.keys)
			let request = container.managedObjectModel.fetchRequestFromTemplate(withName: "FindUsers", 
					substitutionVariables: [ "usernames" : usernames ]) as! NSFetchRequest<KrakenUser>
			let results = try request.execute()
			var resultDict = Dictionary(uniqueKeysWithValues: zip(results.map { $0.username } , results))
			
			// Perform adds and updates on users
			for user in users.values {
				let addingUser = resultDict[user.username] ?? KrakenUser(context: context)
				addingUser.buildFromV2UserInfo(context: context, v2Object: user)
				resultDict[addingUser.username] = addingUser
			}
			

			// Perform updates as necessary on any users already in CD. Remove updated users from our input array.
			for cdUser in results {
				if let user = users[cdUser.username] {
					if user.displayName != cdUser.displayName {
						cdUser.displayName = user.displayName
					}
					if user.lastPhotoUpdated != cdUser.lastPhotoUpdated {
						cdUser.lastPhotoUpdated = user.lastPhotoUpdated
					}
					users.removeValue(forKey: cdUser.username)
				}
			}
			
			// Results should now have all the users that were passed in.
			context.userInfo.setObject(resultDict, forKey: "Users" as NSString)
		}
		catch {
			print (error)
		}
	}
	
}






// Twittar API V2 UserInfo
struct TwitarrV2UserInfo: Codable {
	let username: String
	let displayName: String
	let lastPhotoUpdated: Int64
	
	enum CodingKeys: String, CodingKey {
		case username
		case displayName = "display_name"
		case lastPhotoUpdated = "last_photo_updated"
	}
}

struct TwitarrV2UserProfile: Codable {
	let username: String
	let displayName: String
	let realName: String?
	let pronouns: String?

	let emailAddress: String?
	let homeLocation: String?
	let roomNumber: String?
	let currentLocation: String?

	let lastPhotoUpdated: Int64
	let starred: Bool?
	let comment: String?
	let numberOfTweets: Int32
	let numberOfMentions: Int32
	
	
	enum CodingKeys: String, CodingKey {
		case username, pronouns, starred, comment
		case displayName = "display_name"
		case emailAddress = "email"
		case currentLocation = "current_location"
		case lastPhotoUpdated = "last_photo_updated"
		case roomNumber = "room_number"
		case realName = "real_name"
		case homeLocation = "home_location"
		case numberOfTweets = "number_of_tweets"
		case numberOfMentions = "number_of_mentions"
	}
}

struct TwitarrV2UserProfileResponse: Codable {
	let status: String
	let user: TwitarrV2UserProfile
//	let recentTweets: [TwitarrV2Post]
//	let starred: Bool?
//	let comment: String?
	
}
