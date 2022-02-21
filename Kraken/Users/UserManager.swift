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
	@NSManaged public var userID: UUID
	@NSManaged public var username: String
	@NSManaged public var displayName: String
	@NSManaged public var realName: String?
	@NSManaged public var pronouns: String?
	
	@NSManaged public var emailAddress: String?
	@NSManaged public var currentLocation: String?
	@NSManaged public var roomNumber: String?
	@NSManaged public var homeLocation: String?
	@NSManaged public var aboutMessage: String?
	@NSManaged public var profileMessage: String?
	
	@NSManaged public var lastPhotoUpdated: Int64
	@NSManaged public var userImageName: String?
	@NSManaged public var thumbPhotoData: Data?
	
	@NSManaged public var reactions: Set<Reaction>?
	@NSManaged public var blockedGlobally: Bool
	@NSManaged public var limitProfileAccess: Bool			// TRUE if user wants to not show profile to anon users
		
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
	
	// KrakenUser has more relationships in the datamodel that aren't declared here.
	@NSManaged public var forumThreads: Set<ForumThread>
	@NSManaged public var tweets: Set<TwitarrPost>
	
	override public func awakeFromInsert() {
		super.awakeFromInsert()
		userID = UUID()
	}

	override public func awakeFromFetch() {
		super.awakeFromFetch()
		if thumbPhotoData == nil  {
			builtPhotoUpdateTime = 0
			thumbPhoto = nil
		}
	}
	
	func buildFromV3UserHeader(context: NSManagedObjectContext, v3Object: TwitarrV3UserHeader) {
		TestAndUpdate(\.username, v3Object.username)
		TestAndUpdate(\.userID, v3Object.userID)
		TestAndUpdate(\.displayName, v3Object.displayName ?? v3Object.username)
		buildFromV3ImageInfo(context: context, newFilename: v3Object.userImage)
	}
	
	func buildFromV3Profile(context: NSManagedObjectContext, v3Object: TwitarrV3ProfilePublicData) {
		buildFromV3UserHeader(context: context, v3Object: v3Object.header)
		TestAndUpdate(\.aboutMessage, v3Object.about)
		TestAndUpdate(\.profileMessage, v3Object.message)
		TestAndUpdate(\.emailAddress, v3Object.email)
		TestAndUpdate(\.homeLocation, v3Object.homeLocation)
		TestAndUpdate(\.pronouns, v3Object.preferredPronoun)
		TestAndUpdate(\.realName, v3Object.realName)
		TestAndUpdate(\.roomNumber, v3Object.roomNumber)

		// Not handled: Note
	}
		
	func buildFromV3ImageInfo(context: NSManagedObjectContext, newFilename: String?) {
		if newFilename != userImageName {
			invalidateUserPhoto(context)
		}
		TestAndUpdate(\.userImageName, newFilename)
	}
	
	func buildFromV2UserInfo(context: NSManagedObjectContext, v2Object: TwitarrV2UserInfo) {
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
//		TestAndUpdate(\.numberOfTweets, v2Object.numberOfTweets)
//		TestAndUpdate(\.numberOfMentions, v2Object.numberOfMentions)
		
	}
	
	// Note that this method gets called A LOT for user thumbnails that are already built.
	func loadUserThumbnail() {
		// Is the UIImage already built?
		if thumbPhoto != nil {
			return
		}
		
		// Can we build the photo from the CoreData cache?
		if thumbPhotoData != nil, let data = thumbPhotoData {
			thumbPhoto = UIImage(data: data)
			builtPhotoUpdateTime = lastPhotoUpdated
			return
		}
		
		// Input sanitizing: URLComponents should percent escape username to make a valid path; 
		// but the username could still have "/" in it. 
		var path: String
		if Settings.apiV3, let imageFilename = userImageName, !imageFilename.isEmpty {
			path = "api/v3/image/thumb/\(imageFilename)"
		}
		else if !Settings.apiV3, let encodedUsername = username.addingPathComponentPercentEncoding() {
			path = "/api/v2/user/photo/\(encodedUsername)"
		}
		else {
			thumbPhoto = UIImage(named: "NoAvatarUser")
			builtPhotoUpdateTime = self.lastPhotoUpdated
			return
		}

		let request = NetworkGovernor.buildTwittarRequest(withEscapedPath: path)
		NetworkGovernor.shared.queue(request) { (package: NetworkResponse) in
			if let error = NetworkGovernor.shared.parseServerError(package) {
				ImageLog.error(error.errorString)
			}
			else if let data = package.data {
				LocalCoreData.shared.performNetworkParsing { context in
					context.pushOpErrorExplanation("Couldn't save context while saving User avatar.")
					let userInNetworkContext = context.object(with: self.objectID) as! KrakenUser
					userInNetworkContext.thumbPhotoData = data
//					userInNetworkContext.builtPhotoUpdateTime = self.lastPhotoUpdated
				}
			} else 
			{
				// Load failed for some reason
				ImageLog.error("/api/v2/user/photo returned no error, but also no image data.")
			}
		}
			
//		// Now load the main context and set the thumbnail photo
//		let mainContext = LocalCoreData.shared.mainThreadContext
//		mainContext.perform {
//			let userInMainContext = mainContext.object(with: self.objectID) as! KrakenUser
//			if let photoData = userInMainContext.thumbPhotoData {
//				// rcf Not sure thumbPhotoData will be actually be updated here. May need to call context.refresh(user).
//				userInMainContext.thumbPhoto = UIImage(data: photoData)
//			}
//			else {
//				// If we have a photo but no photo data, the blank avatar will continue until the user
//				// changes their pic, which forces a reload. Will also re-ask the server on app restart.
//				userInMainContext.thumbPhoto = UIImage(named: "NoAvatarUser")
//			}
//			userInMainContext.builtPhotoUpdateTime = self.lastPhotoUpdated
//		}
	}
	
	// Observe fullPhoto to get updated.
	func loadUserFullPhoto() {
		guard self.managedObjectContext	== LocalCoreData.shared.mainThreadContext else {
			CoreDataLog.error("Must be on main thread context to load images.")
			return
		}
		guard let imageName = userImageName else {
			thumbPhoto = UserManager.shared.noAvatarImage
			fullPhoto = UserManager.shared.noAvatarImage
			builtPhotoUpdateTime = self.lastPhotoUpdated
			return
		}
		// Is the UIImage already built?
		if fullPhoto != nil {
			return
		}
		
		ImageManager.shared.image(withSize: .full, forKey: imageName) { image in
			self.fullPhoto = image
		}
	}
	
	// Pass in context iff we're already in a context.perform() block
	// Invalidates the user images cached for this user.
	func invalidateUserPhoto(_ context: NSManagedObjectContext?) {
		ImageManager.shared.userImageCache.invalidateImage(withKey: userImageName ?? username)

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
	
	// V2 has a field for # of authored tweets in its profile data struct; V3 doesn't. Our local cache DB is not 
	// authoritative, but better than nothing.
	func getAuthoredTweetCount() -> Int {
		return tweets.count
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
	let noAvatarImage = UIImage(named: "NoAvatarUser")


// MARK: Getting users from CD
	// Gets the User object for a given username. Returns nil if CD hasn't heard of that user yet. Does not make a server call.
	// Can be called from inside other CD perform() blocks--be sure to send in the context.
	func user(_ userName: String, inContext: NSManagedObjectContext? = nil) -> KrakenUser? {
		let context = inContext ?? coreData.mainThreadContext
		var result: KrakenUser?
		context.performAndWait {
			do {
				let request = NSFetchRequest<KrakenUser>(entityName: "KrakenUser")
				request.predicate = NSPredicate(format: "username == %@", userName)
				let results = try request.execute()
				result = results.first
			}
			catch {
				CoreDataLog.error("Failure fetching user.", ["Error" : error])
			}
		}
		
		return result
	}
	
	// Gets the User object for a given userID (NOT CD ObjectID!). Returns nil if CD hasn't heard of that user yet.
	// Does not make a server call. Can be called from inside other CD perform() blocks--be sure to send in the context.
	func user(_ userID: UUID, inContext: NSManagedObjectContext? = nil) -> KrakenUser? {
		let context = inContext ?? coreData.mainThreadContext
		var result: KrakenUser?
		context.performAndWait {
			do {
				let request = NSFetchRequest<KrakenUser>(entityName: "KrakenUser")
				request.predicate = NSPredicate(format: "userID == %@", userID as CVarArg)
				let results = try request.execute()
				result = results.first
			}
			catch {
				CoreDataLog.error("Failure fetching user.", ["Error" : error])
			}
		}
		
		return result
	}
	
// MARK: Loading user info from server
	func loadUser(_ username: String, inContext: NSManagedObjectContext? = nil, done: @escaping ((KrakenUser?) -> Void)) {
		// The background context we use to save data parsed from network calls CAN use the object ID but 
		// CANNOT reference the object
		if let krakenUser = user(username, inContext: inContext) {
			done(krakenUser)
		}
		
		// Input sanitizing: URLComponents should percent escape username to make a valid path; 
		// but the username could still have "/" in it. 
		let encodedUsername = username.addingPathComponentPercentEncoding() ?? ""
		var request = NetworkGovernor.buildTwittarRequest(withEscapedPath: "/api/v3/users/find/\(encodedUsername)", query: nil)
		NetworkGovernor.addUserCredential(to: &request)
		NetworkGovernor.shared.queue(request) { (package: NetworkResponse) in
			if let error = NetworkGovernor.shared.parseServerError(package) {
				AppLog.error(error.errorString)
				done(nil)	// Didn't find any user with that name
			}
			else if let data = package.data {
//				print (String(decoding:data!, as: UTF8.self))
				do {
					let profileResponse = try Settings.v3Decoder.decode(TwitarrV3UserHeader.self, from: data)
					self.updateUserHeader(for: nil, from: profileResponse, done: done)
				} catch 
				{
					NetworkLog.error("Failure loading user profile.", ["Error" : error])
					done(nil)
				} 
			}
		}
	}
	
	// Calls /api/v3/users/:userID/profile to get info on a user. Updates CD with the returned information.
	func loadUserProfile(_ username: String, done: ((KrakenUser?) -> Void)? = nil) -> KrakenUser? {
	
		let userFound = { (user: KrakenUser?) in 
			guard let user = user else {
				done?(nil)
				return
			}
			
			var request = NetworkGovernor.buildTwittarRequest(withEscapedPath: "/api/v3/users/\(user.userID)/profile", query: nil)
			NetworkGovernor.addUserCredential(to: &request)
			NetworkGovernor.shared.queue(request) { (package: NetworkResponse) in
				if let error = NetworkGovernor.shared.parseServerError(package) {
					AppLog.error(error.errorString)
					done?(nil)
				}
				else if let data = package.data {
	//				print (String(decoding:data!, as: UTF8.self))
					do {
						let profileResponse = try Settings.v3Decoder.decode(TwitarrV3ProfilePublicData.self, from: data)
						self.updateV3Profile(for: user, from: profileResponse, done: done)
					} catch 
					{
						NetworkLog.error("Failure loading user profile.", ["Error" : error])
						done?(nil)
					} 
				}
			}
		}
		
		// Attempt to find the user in our local CD database. Call loadUser if we can't find them.
		let krakenUser = user(username)		
		if krakenUser == nil {
			loadUser(username, done: userFound)
		}
		else {
			userFound(krakenUser)
		}
		return krakenUser
	}
	
// MARK: Updating user info from responses
	func updateUserHeader(for mainThreadUser: KrakenUser?, from header: TwitarrV3UserHeader, done: ((KrakenUser?) -> Void)? = nil) {
		LocalCoreData.shared.performNetworkParsing { context in
			context.pushOpErrorExplanation("Failure saving user profile data.")
			LocalCoreData.shared.setAfterSaveBlock(for: context, block: {_ in done?(nil) } )

			// If we have an objectID, use it to get the KrakenUser. Else we do a search.
			var krakenUser: KrakenUser?
			if let ku = mainThreadUser {
				krakenUser = try context.existingObject(with: ku.objectID) as? KrakenUser
			}
			else {
				krakenUser = self.user(header.userID, inContext: context)
			}
			
			let user = krakenUser ?? KrakenUser(context: context)
			user.buildFromV3UserHeader(context: context, v3Object: header)
			try context.save()
			LocalCoreData.shared.setAfterSaveBlock(for: context, block: {_ in 
				if let userInMainContext = LocalCoreData.shared.mainThreadContext.object(with: user.objectID) as? KrakenUser {
					done?(userInMainContext) 
				}
			})
		}
	}
	
	func updateV3Profile(for user: KrakenUser, from profile: TwitarrV3ProfilePublicData, done: ((KrakenUser?) -> Void)? = nil) {
		LocalCoreData.shared.performNetworkParsing { context in
			context.pushOpErrorExplanation("Failure saving user profile data.")
			LocalCoreData.shared.setAfterSaveBlock(for: context, block: {_ in 
				if let userInMainContext = LocalCoreData.shared.mainThreadContext.object(with: user.objectID) as? KrakenUser {
					done?(userInMainContext) 
				}
				else {
					done?(nil)
				}
			})

			if let userInContext = try context.existingObject(with: user.objectID) as? KrakenUser {	
				userInContext.buildFromV3Profile(context: context, v3Object: profile)
			}
		}
	}
		
	// Updates a bunch of users at once. The array of TwitarrV3UserHeader objects can have duplicates, but is assumed
	// to be the parsed out of a single network call (i.e. duplicate IDs will have all fields equal). Does not save the context.
	func update(users origUsers: [TwitarrV3UserHeader], inContext context: NSManagedObjectContext) {
		do {
			// Unique all the users
			let usersDict = Dictionary(origUsers.map { ($0.userID, $0) }, uniquingKeysWith: { (first,_) in first })
		
			let userIDs = Array(usersDict.keys)
			let request = NSFetchRequest<KrakenUser>(entityName: "KrakenUser")
			request.predicate = NSPredicate(format: "userID IN %@", userIDs)
			let results = try request.execute()
			var resultDict: [UUID : KrakenUser] = Dictionary(uniqueKeysWithValues: zip(results.map { $0.userID } , results))
			
			// Perform adds and updates on users
			for user in usersDict.values {
				// Users in the user table must always be *created* as LoggedInKrakenUser, so that if that user
				// logs in on this device we can load them as a LoggedInKrakenUser. Generally we *search* for KrakenUsers,
				// the superclass.
				let addingUser = resultDict[user.userID] ?? LoggedInKrakenUser(context: context)
				addingUser.buildFromV3UserHeader(context: context, v3Object: user)
				resultDict[addingUser.userID] = addingUser
			}
						
			// Results should now have all the users that were passed in. Add the logged in user, because several
			// parsers require it.
			if let currentUser = CurrentUser.shared.loggedInUser, 
				let userInContext = try? context.existingObject(with: currentUser.objectID) as? KrakenUser {
				resultDict[currentUser.userID] = userInContext
			}
			context.userInfo.setObject(resultDict, forKey: "Users" as NSString)
		}
		catch {
			CoreDataLog.error("Couldn't add users to Core Data.", ["Error" : error])
		}
	}
	
	func updateUserImageInfo(user: KrakenUser, newFilename: String?) {
		LocalCoreData.shared.performNetworkParsing { context in
			context.pushOpErrorExplanation("Failure updating user info.")
			if let userInContext = try context.existingObject(with: user.objectID) as? KrakenUser {
				userInContext.buildFromV3ImageInfo(context: context, newFilename: newFilename)
			}
		}
	}
		
// MARK: V2
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
	func updateLoggedInUserInfo(from profile: TwitarrV3ProfilePublicData) {			
		LocalCoreData.shared.performNetworkParsing { context in
			context.pushOpErrorExplanation("Failure updating user info.")
			if let currentUser = CurrentUser.shared.getLoggedInUser(in: context), currentUser.username == profile.header.username {
				currentUser.buildFromV3Profile(context: context, v3Object: profile)
			}
		}
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
	

	
// MARK: Username Autocomplete Searches
	// Autocomplete variables for minimizing calls to /api/v2/user/ac.
	fileprivate var recentAutocorrectSearches = Set<String>()
	// Autocomplete searches that returned fewer than 10 results--meaning strings with these prefixes can't give us anything new
	fileprivate var recentFullResultSearches = Set<String>()
	var autocorrectCallDelayTimer: Timer?
	var autocorrectCallInProgress: Bool = false
	var delayedAutocorrectSearchString: String?
	var delayedAutocorrectCompletion: ((String?) -> Void)?

	func clearRecentAutocorrectSearches() {
		recentAutocorrectSearches.removeAll()
		recentFullResultSearches.removeAll()
	}
	
	// UI level code can call this repeatedly, for every character the user types. This method waits .5 seconds
	// before calling the server, resets that timer every time this fn is called, checks the search string against
	// recent strings (and won't re-ask the server with a string it's already used), and limits to one call in flight 
	// at a time.
	// Only calls completion routine if we talked to server and (maybe) got new usernames
	func autocorrectUserLookup(for partialName: String, done: @escaping (String?) -> Void) {
		// 1. Don't call the server with 1 char strings, with the same string twice, or with a string containing a substring
		// we already tried IF that substring returned fewer than 10 matches (that is, we got a 'complete' result on the substring).
		let matchesRecentSearch = recentFullResultSearches.contains { partialName.contains($0) }
		guard partialName.count > 1, !recentAutocorrectSearches.contains(partialName), !matchesRecentSearch else { done(nil); return }
		
		// 2. Kill any timer that's going
		autocorrectCallDelayTimer?.invalidate()
				
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
		
	// Updates CD with new users who have the given substring in their names by asking the server.
	// Calls done closure when complete. Parameter to the done closure is non-nil if the server response
	// was comprehensive for that substring.
	private func internalAutocorrectUserLookup(for partialName: String, done: @escaping (String?) -> Void) {
		guard partialName.count > 1 else { done(nil); return }
		autocorrectCallInProgress = true
		
		// Input sanitizing: URLComponents should percent escape partialName to make a valid path; 
		// but the username could still have "/" in it. 
		let encodedUsername = partialName.addingPathComponentPercentEncoding() ?? ""

		var request = NetworkGovernor.buildTwittarRequest(withEscapedPath:"/api/v3/users/match/allnames/\(encodedUsername)", query: nil)
		NetworkGovernor.addUserCredential(to: &request)
		NetworkGovernor.shared.queue(request) { (package: NetworkResponse) in
			self.autocorrectCallInProgress = false
			if let error = NetworkGovernor.shared.parseServerError(package) {
				NetworkLog.error("Error with user autocomplete", ["error" : error])
			}
			else if let data = package.data {
				LocalCoreData.shared.performNetworkParsing { context in
					context.pushOpErrorExplanation("Failure parsing UserInfo from Autocomplete response.")
					let result = try JSONDecoder().decode([TwitarrV3UserHeader].self, from: data)
					UserManager.shared.update(users: result, inContext: context)
					
					LocalCoreData.shared.setAfterSaveBlock(for: context) { success in
						if success {
							let doneString = result.count < 10 ? partialName : nil
							DispatchQueue.main.async { 
								self.recentAutocorrectSearches.insert(partialName)
								if result.count < 10 {
									self.recentFullResultSearches.insert(partialName)
								}
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
	
	func userIsBlocked(_ user: KrakenUser?) -> Bool {
		guard let user = user else { return false }
		if let currentUser = CurrentUser.shared.loggedInUser, currentUser.blockedUsers.contains(user) {
			return true		
		}
		else if user.blockedGlobally {
			return true
		} else {
			return false		
		}	
	}
	
    func setupBlockOnUser(_ user: KrakenUser, isBlocked: Bool) {
		LocalCoreData.shared.performNetworkParsing { context in
			context.pushOpErrorExplanation("Failed to setup block on user.")
			if let userToBlock = context.object(with: user.objectID) as? KrakenUser {
				if let currentUser = CurrentUser.shared.getLoggedInUser(in: context) {
					if isBlocked {
						currentUser.blockedUsers.insert(userToBlock)
					}
					else {
						currentUser.blockedUsers.remove(userToBlock)
						
						// If you block someone while logged out, you shouldn't have to log out again
						// just to unblock them.
						userToBlock.blockedGlobally = false
					}
				}
				else {
					userToBlock.blockedGlobally = isBlocked
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

// MARK: - Twitarr V3 API Encoding/Decoding


struct TwitarrV3UserHeader: Codable {
    /// The user's ID.
    var userID: UUID
    /// The user's username.
    var username: String
    /// The user's displayName.
    var displayName: String?
    /// The user's profile image.
    var userImage: String?
}

/// Used to return a user's public profile contents.
///
/// Returned by: `GET /api/v3/users/ID/profile`
///
struct TwitarrV3ProfilePublicData: Codable {
    /// Basic info about the user--their ID, username, displayname, and avatar image.
    var header: TwitarrV3UserHeader

    /// An optional blurb about the user.
    var about: String
    /// An optional email address for the user.
    var message: String
    /// An optional preferred pronoun or form of address.
    var email: String
    /// An optional home location for the user.
    var homeLocation: String
    /// An optional greeting/message to visitors of the profile.
    var preferredPronoun: String
    /// An optional real world name of the user.
    var realName: String
    /// An optional cabin number for the user.
    var roomNumber: String
    /// A UserNote owned by the visiting user, about the profile's user (see `UserNote`).
    var note: String?
}

struct TwitarrV3NoteData: Codable {
    /// Timestamp of the note's creation.
    let createdAt: Date
    /// Timestamp of the note's last update.
    let updatedAt: Date
    /// The user the note is written about. The target user does not get to see notes written about them.
    let targetUser: TwitarrV3UserHeader
    /// The text of the note.
    var note: String
}
