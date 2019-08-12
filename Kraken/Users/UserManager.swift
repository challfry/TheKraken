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
	@NSManaged private var commentedUpon: Set<CommentsAndStars>?
	
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
		
		if let loggedInUser = CurrentUser.shared.getLoggedInUser(in: context) {
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
					self.thumbPhoto = UIImage(data: data)
					let context = LocalCoreData.shared.networkOperationContext
					context.perform {
						do {
							let objectInContext = context.object(with: self.objectID) as! KrakenUser
							objectInContext.thumbPhotoData = data
							try context.save()
						}
						catch {
							CoreDataLog.error("Couldn't save context while saving User avatar.", ["error" : error])
						}
					}
				} else 
				{
					// Load failed for some reason
				}
			}
		}
	}
}

// PotentialUser is used by POSTing classes that can create content while offline. A PotentialUser is just a username,
// although it has a link to the actual KrakenUser if one exists. A Potentialuser *might* be an actual Twitarr account,
// but it may not have been validated.
@objc(PotentialUser) public class PotentialUser : KrakenManagedObject {
	@NSManaged var username: String
	@NSManaged var actualUser: KrakenUser?
}

// MARK: - Data Manager

class UserManager : NSObject {
	static let shared = UserManager()
	private let coreData = LocalCoreData.shared

	// Gets the User object for a given username. Returns nil if CD hasn't heard of that user yet. Does not make a server call.
	func user(_ userName: String, inContext: NSManagedObjectContext? = nil) -> KrakenUser? {
		let context = inContext ?? coreData.mainThreadContext
		var result: KrakenUser?
		context.performAndWait {
			do {
				let request = coreData.persistentContainer.managedObjectModel.fetchRequestFromTemplate(withName: "FindAUser", 
						substitutionVariables: [ "username" : userName ]) as! NSFetchRequest<KrakenUser>
				let results = try request.execute()
				result = results.first
			}
			catch {
				CoreDataLog.error("Failure fetching user.", ["Error" : error])
			}
		}
		
		return result
	}
	
	// Calls /api/v2/user/profile to get info on a user. Updates CD with the returned information.
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
					NetworkLog.error("Failure loading user profile.", ["Error" : error])
				} 
			}
		}
		return krakenUser
	}
	
	func updateProfile(for objectID: NSManagedObjectID?, from response: TwitarrV2UserProfileResponse) {
		guard response.status == "ok" else { return }
		updateProfile(for: objectID, from: response.user)
	}

	func updateProfile(for objectID: NSManagedObjectID?, from profile: TwitarrV2UserProfile) {
		let context = coreData.networkOperationContext
		context.perform {
			do {			
				// If we have an objectID, use it to get the KrakenUser. Else we do a search.
				var krakenUser: KrakenUser?
				if let objectID = objectID {
					krakenUser = try context.existingObject(with: objectID) as? KrakenUser
				}
				else {
					let request = self.coreData.persistentContainer.managedObjectModel.fetchRequestFromTemplate(withName: "FindAUser", 
								substitutionVariables: [ "username" : profile.username ]) as! NSFetchRequest<KrakenUser>
					let results = try request.execute()
					krakenUser = results.first
				}
				
				let user = krakenUser ?? KrakenUser(context: context)
				user.buildFromV2UserProfile(context: context, v2Object: profile)
				try context.save()
			}
			catch {
				NetworkLog.error("Failure saving user profile data.", ["Error" : error])
			}
		}
	}
	
	// Only used to update info for logged in user.
	func updateAccount(from response: TwitarrV2CurrentUserProfileResponse) -> LoggedInKrakenUser? {
		guard response.status == "ok" else { return nil }
		
		let context = coreData.networkOperationContext
		var krakenUser: LoggedInKrakenUser?
		context.performAndWait {
			do {
				// If we have an objectID, use it to get the KrakenUser. Else we do a search.
				let request = self.coreData.persistentContainer.managedObjectModel.fetchRequestFromTemplate(withName: "FindAUser", 
							substitutionVariables: [ "username" : response.userAccount.username ]) as! NSFetchRequest<LoggedInKrakenUser>
				let results = try request.execute()
				krakenUser = results.first 
				
				if let user = krakenUser {
					user.buildFromV2UserAccount(context: context, v2Object: response.userAccount)
					try context.save()
				}
			}
			catch
			{
				CoreDataLog.error("Failure updating user info.", ["Error" : error])
			}
		}
		
		return krakenUser
	}
	
	// Updates a bunch of users at once. The array of UserInfo objects can have duplicates, but is assumed
	// to be the parsed out of a single network call. Does not save the context.
	func update(users origUsers: [TwitarrV2UserInfo], inContext context: NSManagedObjectContext) {
		do {
			// Unique all the users
			let usersDict = Dictionary(origUsers.map { ($0.username, $0) }, uniquingKeysWith: { (first,_) in first })
		
			let usernames = Array(usersDict.keys)
			let request = coreData.persistentContainer.managedObjectModel.fetchRequestFromTemplate(withName: "FindUsers", 
					substitutionVariables: [ "usernames" : usernames ]) as! NSFetchRequest<KrakenUser>
			let results = try request.execute()
			var resultDict = Dictionary(uniqueKeysWithValues: zip(results.map { $0.username } , results))
			
			// Perform adds and updates on users
			for user in usersDict.values {
				// Users in the user table must always be *created* as LoggedInKrakenUser, so that if that user
				// logs in on this device we can load them as a LoggedInKrakenUser. Generally we *search* for KrakenUsers,
				// the superclass.
				let addingUser = resultDict[user.username] ?? LoggedInKrakenUser(context: context)
				addingUser.buildFromV2UserInfo(context: context, v2Object: user)
				resultDict[addingUser.username] = addingUser
			}
						
			// Results should now have all the users that were passed in. Add the logged in user, because several
			// parsers require it.
			if let currentUser = CurrentUser.shared.loggedInUser, 
				let userInContext = try? context.existingObject(with: currentUser.objectID) as? KrakenUser {
				resultDict[currentUser.username] = userInContext
			}
			context.userInfo.setObject(resultDict, forKey: "Users" as NSString)
		}
		catch {
			CoreDataLog.error("Couldn't add users to CD.", ["Error" : error])
		}
	}
	
	// Updates CD with new users who have the given substring in their names by asking the server.
	// Calls done closure when complete. Parameter to the done closure is non-nil if the server response
	// was comprehensive for that substring.
	func autocorrectUserLookup(for partialName: String, done: @escaping (String?) -> Void) {
		guard partialName.count > 1 else { done(nil); return }
		
		// Input sanitizing:
		// URLComponents should percent escape partialName to make a valid path; we may want to remove spaces
		// manually first.
		
		let request = NetworkGovernor.buildTwittarV2Request(withPath:"/api/v2/user/ac/\(partialName)", query: nil)
		NetworkGovernor.shared.queue(request) { (data: Data?, response: URLResponse?) in
			if let error = NetworkGovernor.shared.parseServerError(data: data, response: response) {
				NetworkLog.error("Error with user autocomplete", ["error" : error])
			}
			else if let data = data {
				let decoder = JSONDecoder()
				let context = self.coreData.networkOperationContext
				context.performAndWait {
					do {
						let result = try decoder.decode(TwitarrV2UserAutocompleteResponse.self, from: data)
						UserManager.shared.update(users: result.users, inContext: context)
						try context.save()
						let doneString = result.users.count < 10 ? partialName : nil
						DispatchQueue.main.async { done(doneString) }
					}
					catch {
						NetworkLog.error("Failure parsing UserInfo.", ["Error" : error, "url" : request.url as Any])
					} 
				}
			}
		}
	}
	
}




// MARK: - Twitarr V2 API Encoding/Decoding

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

// /api/v2/user/profile/:username
struct TwitarrV2UserProfileResponse: Codable {
	let status: String
	let user: TwitarrV2UserProfile
//	let recentTweets: [TwitarrV2Post]
//	let starred: Bool?
//	let comment: String?
	
}

// /api/v2/user/profile/:username
struct TwitarrV2UserAutocompleteResponse: Codable {
	let status: String
	let users: [TwitarrV2UserInfo]
}

