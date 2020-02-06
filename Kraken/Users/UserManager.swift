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
	
	@NSManaged public var reactions: Set<Reaction>?
		
		// Cached UIImages of the user avatar, keyed off the lastPhotoUpdated time they were built from.
		// When the user changes their avatar, lastPhotoUpdated will change, and we should invalidate these.
	var builtPhotoUpdateTime: Int64 = 0					
	@objc dynamic public var thumbPhoto: UIImage?
	@objc dynamic weak var fullPhoto: UIImage?
	
	// Only follow these links when parsing! This goes to all comments *others* have left, including anyone who logged into this device!
	@NSManaged private var commentedUpon: Set<UserComment>?
	@NSManaged public var commentOps: Set<PostOpUserComment>?
	
	@NSManaged public var seamailParticipant: Set<SeamailThread>
	@NSManaged public var upToDateAnnouncements: Set<Announcement>
	
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
				LocalCoreData.shared.performNetworkParsing { context in
					context.pushOpErrorExplanation("Couldn't save context while saving User avatar.")
					let userInNetworkContext = context.object(with: self.objectID) as! KrakenUser
					userInNetworkContext.thumbPhotoData = data
					try context.save()
					
					// Now load the main context and set the thumbnail photo
					let mainContext = LocalCoreData.shared.mainThreadContext
					mainContext.perform {
						let userInMainContext = mainContext.object(with: self.objectID) as! KrakenUser
						userInMainContext.thumbPhoto = UIImage(data: data)
						userInMainContext.builtPhotoUpdateTime = self.lastPhotoUpdated
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
	// Invalidates the user images cached for this user.
	func invalidateUserPhoto(_ context: NSManagedObjectContext?) {
		ImageManager.shared.userImageCache.invalidateImage(withKey: username)

		// 
		let mainContext = LocalCoreData.shared.mainThreadContext
		mainContext.perform {
			if let mainContextSelf = mainContext.registeredObject(for: self.objectID) as? KrakenUser, !mainContextSelf.isFault {
				mainContextSelf.thumbPhoto = nil
				mainContextSelf.fullPhoto = nil
				mainContextSelf.builtPhotoUpdateTime = 0
			}
		}
		
		// If a context is passed in, we're already in a perform block and someone else is going to save.
		if let _ = context {
			thumbPhotoData = nil
		}
		else {
			LocalCoreData.shared.performLocalCoreDataChange { netowrkContext, currentUser in
				netowrkContext.pushOpErrorExplanation("Couldn't save context while invalidating User avatar.")
				self.thumbPhotoData = nil
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
		LocalCoreData.shared.performNetworkParsing { context in
			context.pushOpErrorExplanation("Failure saving user profile data.")
			LocalCoreData.shared.setAfterSaveBlock(for: context, block: {_ in done?(nil) } )

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
				return
			}
				
			let user = krakenUser ?? KrakenUser(context: context)
			user.buildFromV2UserProfile(context: context, v2Object: profile)
			try context.save()
			LocalCoreData.shared.setAfterSaveBlock(for: context, block: {_ in 
				if let userInMainContext = LocalCoreData.shared.mainThreadContext.object(with: user.objectID) as? KrakenUser {
					done?(userInMainContext) 
				}
			})
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
			CoreDataLog.error("Couldn't add users to Core Data.", ["Error" : error])
		}
	}
	
	// Autocomplete variables for minimizing calls to /api/v2/user/ac.
	fileprivate var recentAutocorrectSearches = [String]()
	var autocorrectCallDelayTimer: Timer?
	var autocorrectCallInProgress: Bool = false
	var delayedAutocorrectSearchString: String?
	var delayedAutocorrectCompletion: ((String?) -> Void)?

	func clearRecentAutocorrectSearches() {
		recentAutocorrectSearches.removeAll()
	}
	
	// UI level code can call this repeatedly, for every character the user types. This method waits .5 seconds
	// before calling the server, resets that timer every time this fn is called, checks the search string against
	// recent strings (and won't re-ask the server with a string it's already used), and limits to one call in flight 
	// at a time.
	// Only calls completion routine if we talked to server and (maybe) got new usernames
	func autocorrectUserLookup(for partialName: String, done: @escaping (String?) -> Void) {
		guard partialName.count >= 1 else { done(nil); return }

		// 1. Kill any timer that's going
		autocorrectCallDelayTimer?.invalidate()
		
		// 2. Don't call the server with the same string twice (in a short period of time)
		if !recentAutocorrectSearches.contains(partialName) {
		
			// 3. Only have one call in flight--and one call on deck Newer on-deck calls just replace older ones.
			if autocorrectCallInProgress {
				delayedAutocorrectSearchString = partialName
				delayedAutocorrectCompletion = done
			}
			else {
				// 4. Wait half a second, see if the user types more. If not, talk to the server.
				autocorrectCallDelayTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { timer in
					self.internalAutocorrectUserLookup(for: partialName, done: done)
				}
			}
		}
	}
		
	// Updates CD with new users who have the given substring in their names by asking the server.
	// Calls done closure when complete. Parameter to the done closure is non-nil if the server response
	// was comprehensive for that substring.
	func internalAutocorrectUserLookup(for partialName: String, done: @escaping (String?) -> Void) {
		guard partialName.count >= 1 else { done(nil); return }
		autocorrectCallInProgress = true
		
		// Input sanitizing:
		// URLComponents should percent escape partialName to make a valid path; we may want to remove spaces
		// manually first.
		
		let request = NetworkGovernor.buildTwittarV2Request(withPath:"/api/v2/user/ac/\(partialName)", query: nil)
		NetworkGovernor.shared.queue(request) { (package: NetworkResponse) in
			self.autocorrectCallInProgress = false
			if let error = NetworkGovernor.shared.parseServerError(package) {
				NetworkLog.error("Error with user autocomplete", ["error" : error])
			}
			else if let data = package.data {
				LocalCoreData.shared.performNetworkParsing { context in
					context.pushOpErrorExplanation("Failure parsing UserInfo from Autocomplete response.")
					let result = try JSONDecoder().decode(TwitarrV2UserAutocompleteResponse.self, from: data)
					UserManager.shared.update(users: result.users, inContext: context)
					
					LocalCoreData.shared.setAfterSaveBlock(for: context) { success in
						if success {
							let doneString = result.users.count < 10 ? partialName : nil
							DispatchQueue.main.async { 
								self.recentAutocorrectSearches.append(partialName)
								done(doneString) 
							}
						}
					}
				}
			}
			
			// If there's a search that we delayed until this search completes, time to run it.
			if let nextStr = self.delayedAutocorrectSearchString, let nextDone = self.delayedAutocorrectCompletion {
				self.internalAutocorrectUserLookup(for: nextStr, done: nextDone)
				self.delayedAutocorrectSearchString = nil
				self.delayedAutocorrectCompletion = nil
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

