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
@objc(KrakenUser) public class KrakenUser : KrakenManagedObject, MaybeUser {
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
	
	@NSManaged public var userImageName: String?			// userHeader.userImage
	@NSManaged public var thumbPhotoData: Data?				// UNUSED
	
	@NSManaged public var reactions: Set<Reaction>?
	@NSManaged public var limitProfileAccess: Bool			// TRUE if user wants to not show profile to anon users
		
		// Cached UIImages of the user avatar, keyed off the userImageName they were built from.
		// When the user changes their avatar, userImageName will change, and we should invalidate thumb and full photo.
		// NOT saved to CoreData. ONLY MAIN THREAD CONTEXT HAS THESE FILLED IN.
	var builtImageName: String?				
	@objc dynamic public var thumbPhoto: UIImage?
	@objc dynamic weak var fullPhoto: UIImage?
	
	// Only follow these links when parsing! This goes to all comments *others* have left, including anyone who logged into this device!
	@NSManaged private var commentedUpon: Set<UserComment>?
	@NSManaged public var commentOps: Set<PostOpUserComment>?
	
	@NSManaged public var seamailParticipant: Set<SeamailThread>
	@NSManaged public var seamailReadCounts: Set<SeamailReadCount>	
	@NSManaged public var upToDateAnnouncements: Set<Announcement>
	
	// KrakenUser has more relationships in the datamodel that aren't declared here.
	@NSManaged public var forumThreads: Set<ForumThread>
	@NSManaged public var tweets: Set<TwitarrPost>
	
	// MaybeUser protocol
	var actualUser: KrakenUser? { self }
	
// MARK: Methods
	override public func awakeFromInsert() {
		super.awakeFromInsert()
		userID = UUID()
	}

	override public func awakeFromFetch() {
		super.awakeFromFetch()
		builtImageName = nil
		thumbPhoto = nil
	}
	
	func buildFromV3UserHeader(context: NSManagedObjectContext, v3Object: TwitarrV3UserHeader) {
		TestAndUpdate(\.username, v3Object.username)
		TestAndUpdate(\.userID, v3Object.userID)
		TestAndUpdate(\.displayName, v3Object.displayName ?? v3Object.username)
		TestAndUpdate(\.userImageName, v3Object.userImage)
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
		
	// Note that this method gets called A LOT for user thumbnails that are already built.
	func loadUserThumbnail() {
		guard self.managedObjectContext	== LocalCoreData.shared.mainThreadContext else {
			CoreDataLog.error("Must be on main thread context to load images.")
			return
		}
		if builtImageName != userImageName {
			thumbPhoto = nil
			fullPhoto = nil
			builtImageName = userImageName
		}
		guard let imageName = userImageName, !imageName.isEmpty else {
			thumbPhoto = UserManager.shared.noAvatarImage
			fullPhoto = UserManager.shared.noAvatarImage
			return
		}
		
		// Is the UIImage already built?
		if thumbPhoto != nil {
			return
		}
		
		
		ImageManager.shared.image(withSize: .full, forKey: imageName) { image in
			self.thumbPhoto = image
		}

//		// Can we build the photo from the CoreData cache?
//		if thumbPhotoData != nil, let data = thumbPhotoData {
//			thumbPhoto = UIImage(data: data)
//			return
//		}

//		let request = NetworkGovernor.buildTwittarRequest(withEscapedPath: "api/v3/image/thumb/\(imageName)")
//		NetworkGovernor.shared.queue(request) { (package: NetworkResponse) in
//			if let error = NetworkGovernor.shared.parseServerError(package) {
//				ImageLog.error(error.errorString)
//			}
//			else if let data = package.data {
//				LocalCoreData.shared.performNetworkParsing { context in
//					context.pushOpErrorExplanation("Couldn't save context while saving User avatar.")
//					let userInNetworkContext = context.object(with: self.objectID) as! KrakenUser
//					userInNetworkContext.thumbPhotoData = data
//					
//					// After saving from the network thread, have the main thread build the thumb image and save it into
//					// the main thread's CD object.
//					LocalCoreData.shared.setAfterSaveBlock(for: context) { saveSuccess in 
//						DispatchQueue.main.async {
//							self.thumbPhoto = UIImage(data: data)
//							print("New thumb photo")
//						}
//					}
//				}
//			} else 
//			{
//				// Load failed for some reason
//				ImageLog.error("/api/v3/image/thumb returned no error, but also no image data.")
//			}
//		}
	}
	
	// Observe fullPhoto to get updated.
	func loadUserFullPhoto() {
		guard self.managedObjectContext	== LocalCoreData.shared.mainThreadContext else {
			CoreDataLog.error("Must be on main thread context to load images.")
			return
		}
		if builtImageName != userImageName {
			thumbPhoto = nil
			fullPhoto = nil
			builtImageName = userImageName
		}

		guard let imageName = userImageName else {
			thumbPhoto = UserManager.shared.noAvatarImage
			fullPhoto = UserManager.shared.noAvatarImage
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
		
	// V2 has a field for # of authored tweets in its profile data struct; V3 doesn't. Our local cache DB is not 
	// authoritative, but better than nothing.
	func getAuthoredTweetCount() -> Int {
		return tweets.count
	}
}

// PotentialUser is used by POSTing classes that can create content while offline. A PotentialUser is just a username,
// although it has a link to the actual KrakenUser if one exists. A Potentialuser *might* be an actual Twitarr account,
// but it may not have been validated.
@objc(PotentialUser) public class PotentialUser : KrakenManagedObject, MaybeUser {
	@NSManaged var username: String
	@NSManaged var actualUser: KrakenUser?
}

@objc protocol MaybeUser {
	var username: String { get }
	var actualUser: KrakenUser? { get }
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
	
	// Gets a KrakenUser object in a specific context
	func user(_ user: KrakenUser, inContext: NSManagedObjectContext) -> KrakenUser? {
		do {
			return try inContext.existingObject(with: user.objectID) as? KrakenUser
		}
		catch {
			CoreDataLog.error("Failure fetching user.", ["Error" : error])
		}
		return nil
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
	@discardableResult func update(users origUsers: [TwitarrV3UserHeader], inContext context: NSManagedObjectContext,
			includeCurrentUser: Bool = true) -> [UUID : KrakenUser] {
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
			if includeCurrentUser, let currentUser = CurrentUser.shared.loggedInUser, 
				let userInContext = try? context.existingObject(with: currentUser.objectID) as? KrakenUser {
				resultDict[currentUser.userID] = userInContext
			}
			context.userInfo.setObject(resultDict, forKey: "Users" as NSString)
			return resultDict
		}
		catch {
			CoreDataLog.error("Couldn't add users to Core Data.", ["Error" : error])
		}
		return [:]
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
					let result = try Settings.v3Decoder.decode([TwitarrV3UserHeader].self, from: data)
					UserManager.shared.update(users: result, inContext: context)
					
					LocalCoreData.shared.setAfterSaveBlock(for: context) { success in
						if success {
							let doneString = result.count < 10 ? partialName : nil
							self.recentAutocorrectSearches.insert(partialName)
							if result.count < 10 {
								self.recentFullResultSearches.insert(partialName)
							}
							done(doneString) 
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
