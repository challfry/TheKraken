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
		
		// Cached UIImages of the user avatar, keyed off the lastPhotoUpdated time they were built from.
		// When the user changes their avatar, lastPhotoUpdated will change, and we should invalidate these.
	var builtPhotoUpdateTime: Int64 = 0					
	@objc dynamic public var thumbPhoto: UIImage?
	@objc dynamic weak var fullPhoto: UIImage?
	
	// Only follow these links when parsing! This goes to all comments *others* have left, including anyone who logged into this device!
	@NSManaged private var commentedUpon: Set<UserComment>?
	@NSManaged public var commentOps: Set<PostOpUserComment>?
	
	override public func awakeFromFetch() {
		super.awakeFromFetch()
		if thumbPhotoData == nil || lastPhotoUpdated != builtPhotoUpdateTime {
			builtPhotoUpdateTime = 0
			thumbPhoto = nil
			fullPhoto = nil
		}
	}
	
	func buildFromV2UserInfo(context: NSManagedObjectContext, v2Object: TwitarrV2UserInfo)
	{
		TestAndUpdate(\.username, v2Object.username)
		TestAndUpdate(\.displayName, v2Object.displayName)
		if v2Object.lastPhotoUpdated > lastPhotoUpdated {
			invalidateUserPhoto(context)
		}
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

		if v2Object.lastPhotoUpdated > lastPhotoUpdated {
			invalidateUserPhoto(context)
		}
		TestAndUpdate(\.lastPhotoUpdated, v2Object.lastPhotoUpdated)
		TestAndUpdate(\.numberOfTweets, v2Object.numberOfTweets)
		TestAndUpdate(\.numberOfMentions, v2Object.numberOfMentions)
		
		// If we're logged in, have the logged in user process the comments and stars 
		if let loggedInUser = CurrentUser.shared.getLoggedInUser(in: context) {
			loggedInUser.parseV2UserProfileCommentsAndStars(context: context, v2Object: v2Object, targetUser: self)
		}
	}


	// Extra stuff the UserAccount type has
	// role
	// lastLogin time
	// emptyPassword bool
	// unnoticed_alerts
	
	// Note that this method gets called A LOT for user thumbnails that are already built.
	func loadUserThumbnail() {
		// Is the UIImage already built?
		if thumbPhoto != nil && builtPhotoUpdateTime == lastPhotoUpdated {
			return
		}
		
		// Can we build the photo from the CoreData cache?
		if thumbPhotoData != nil, let data = thumbPhotoData {
			thumbPhoto = UIImage(data: data)
			builtPhotoUpdateTime = lastPhotoUpdated
			return
		}
		
		let request = NetworkGovernor.buildTwittarV2Request(withPath:"/api/v2/user/photo/\(username)")
		NetworkGovernor.shared.queue(request) { (package: NetworkResponse) in
			if let error = NetworkGovernor.shared.parseServerError(package) {
				ImageLog.error(error.errorString ?? "Unknown error in /api/v2/user/photo response")
			}
			else if let data = package.data {
				self.thumbPhoto = UIImage(data: data)
				self.builtPhotoUpdateTime = self.lastPhotoUpdated
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
				ImageLog.error("/api/v2/user/photo returned no error, but also no image data.")
			}
		}
	}
	
	// Pass in context iff we're already in a context.perform() block
	func invalidateUserPhoto(_ context: NSManagedObjectContext?) {
		if let currentUsername = CurrentUser.shared.loggedInUser?.username {
			ImageManager.shared.userImageCache.invalidateImage(withKey: currentUsername)
		}

		thumbPhoto = nil
		fullPhoto = nil
		builtPhotoUpdateTime = 0
		
		if let _ = context {
			thumbPhotoData = nil
		}
		else {
			let context = LocalCoreData.shared.networkOperationContext
			context.perform {
				do {
					self.thumbPhotoData = nil
					try context.save()
				}
				catch {
					CoreDataLog.error("Couldn't save context while invalidating User avatar.", ["error" : error])
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
	func loadUserProfile(_ username: String, done: ((KrakenUser?) -> Void)? = nil) -> KrakenUser? {
	
		// The background context we use to save data parsed from network calls CAN use the object ID but 
		// CANNOT reference the object
		let krakenUser = user(username)
		let krakenUserID = krakenUser?.objectID
		
		var request = NetworkGovernor.buildTwittarV2Request(withPath: "/api/v2/user/profile/\(username)", query: nil)
		NetworkGovernor.addUserCredential(to: &request)
		NetworkGovernor.shared.queue(request) { (package: NetworkResponse) in
			if let error = NetworkGovernor.shared.parseServerError(package) {
				AppLog.error(error.errorString ?? "Unknown error in /api/v2/user/profile response")
			}
			else if let data = package.data {
//				print (String(decoding:data!, as: UTF8.self))
				let decoder = JSONDecoder()
				do {
					let profileResponse = try decoder.decode(TwitarrV2UserProfileResponse.self, from: data)
					if profileResponse.status == "ok" {
						self.updateProfile(for: krakenUserID, from: profileResponse.user, done: done)
					}
				} catch 
				{
					NetworkLog.error("Failure loading user profile.", ["Error" : error])
					done?(nil)
				} 
			}
		}
		
		// Note that we return the user object immediately, without waiting for it to be filled in. That's okay.
		// Note 2, the user may be nil. Also okay.
		return krakenUser
	}
	
	func updateProfile(for objectID: NSManagedObjectID?, from profile: TwitarrV2UserProfile, 
			done: ((KrakenUser?) -> Void)? = nil) {
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
				
				// Pretty sure we should disallow cases where the usernames don't match. That is, I don't think the
				// username of a user can be changed.
				if let ku = krakenUser, ku.username != profile.username {
					done?(nil)
					return
				}
				
				let user = krakenUser ?? KrakenUser(context: context)
				user.buildFromV2UserProfile(context: context, v2Object: profile)
				try context.save()
				done?(user)
			}
			catch {
				NetworkLog.error("Failure saving user profile data.", ["Error" : error])
				done?(nil)
			}
		}
	}
	
	// Only used to update info for logged in user.
	@discardableResult func updateLoggedInUserInfo(from userAccount: TwitarrV2UserAccount) -> LoggedInKrakenUser? {			
		let context = coreData.networkOperationContext
		var krakenUser: LoggedInKrakenUser?
		
		// Needs to be sync, to return the user. This is used by the login mechanism.
		context.performAndWait {
			do {
				if let currentUser = CurrentUser.shared.getLoggedInUser(in: context), currentUser.username == userAccount.username {
					krakenUser = currentUser
				}
				else {
					// If we have an objectID, use it to get the KrakenUser. Else we do a search.
					let request = self.coreData.persistentContainer.managedObjectModel.fetchRequestFromTemplate(withName: "FindAUser", 
							substitutionVariables: [ "username" : userAccount.username ]) as! NSFetchRequest<LoggedInKrakenUser>
					let results = try request.execute()
					krakenUser = results.first 
				}
				
				if krakenUser == nil {
					krakenUser = LoggedInKrakenUser(context: context)
				}
				
				if let user = krakenUser {
					user.buildFromV2UserAccount(context: context, v2Object: userAccount)
					try context.save()
				}
			}
			catch
			{
				CoreDataLog.error("Failure updating user info.", ["Error" : error])
			}
		}
		
		if let objectID = krakenUser?.objectID {
			return try? coreData.mainThreadContext.existingObject(with: objectID) as? LoggedInKrakenUser
		}
		
		return nil
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
		NetworkGovernor.shared.queue(request) { (package: NetworkResponse) in
			if let error = NetworkGovernor.shared.parseServerError(package) {
				NetworkLog.error("Error with user autocomplete", ["error" : error])
			}
			else if let data = package.data {
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

