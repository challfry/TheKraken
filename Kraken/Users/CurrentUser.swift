//
//  CurrentUser.swift
//  Kraken
//
//  Created by Chall Fry on 3/22/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import Foundation
import CoreData

@objc(LoggedInKrakenUser) public class LoggedInKrakenUser: KrakenUser {

	@objc enum UserRole: Int {
		case admin
		case tho
		case moderator
		case user
		case muted
		case banned
		case loggedOut
		
		// Done this dumb way because we need to be @objc, therefore Int-backed, not string-backed.
		static func roleForString(str: String) -> UserRole? {
			switch str {
			case "admin": return .admin
			case "tho": return .tho
			case "moderator": return .moderator
			case "user": return .user
			case "muted": return .muted
			case "banned": return .banned
			case "loggedOut": return .loggedOut
			default: return nil
			}
		}
		static func stringForRole(role: UserRole) -> String {
			switch role {
			case .admin: return "admin"
			case .tho: return "tho"
			case .moderator: return "moderator"
			case .user: return "user"
			case .muted: return "muted"
			case .banned: return "banned"
			case .loggedOut: return "loggedOut"
			}
		}
	}
	
	// Specific to the logged-in user
	@NSManaged public var postOps: Set<PostOperation>?

	@NSManaged public var userComments: Set<UserComment>?			// This set is comments the logged in user has made about *others*
	@NSManaged public var starredUsers: Set<KrakenUser>?			// Set of users the logged in user has starred.
	@NSManaged public var lastLogin: Int64
	@NSManaged public var lastAlertCheckTime: Int64
	@NSManaged public var lastSeamailCheckTime: Int64
	
	var twitarrV2AuthKey: String?
	
	// Alerts
	@NSManaged public var badgeTweets: Int32
	@NSManaged public var upToDateSeamailThreads: Set<SeamailThread>

	// Info about the current user that should not be in KrakenUser nor cached to disk.
	@objc dynamic var userRole: UserRole = .loggedOut
	
	func buildFromV2UserAccount(context: NSManagedObjectContext, v2Object: TwitarrV2UserAccount) {
		TestAndUpdate(\.username, v2Object.username)
		TestAndUpdate(\.displayName, v2Object.displayName)
		TestAndUpdate(\.realName, v2Object.realName)
		TestAndUpdate(\.pronouns, v2Object.pronouns)

		TestAndUpdate(\.emailAddress, v2Object.emailAddress)
		TestAndUpdate(\.homeLocation, v2Object.homeLocation)
		TestAndUpdate(\.currentLocation, v2Object.currentLocation)
		TestAndUpdate(\.roomNumber, v2Object.roomNumber)

		TestAndUpdate(\.lastPhotoUpdated, v2Object.lastPhotoUpdated)
		TestAndUpdate(\.lastLogin, v2Object.lastLogin)
		userRole = UserRole.roleForString(str: v2Object.role) ?? .user
//		TestAndUpdate(\.emptyPassword, v2Object.emptyPassword)
	}
	
	func getPendingUserCommentOp(commentingOn: KrakenUser, inContext: NSManagedObjectContext) -> PostOpUserComment? {
		if let ops = postOps {
			for op in ops {
				if let commentOp = op as? PostOpUserComment, let userCommentedOn = commentOp.userCommentedOn,
						userCommentedOn.username == commentingOn.username {
					let commentOpInContext = try? inContext.existingObject(with: commentOp.objectID) as? PostOpUserComment
					return commentOpInContext
				}
			}
		}
		return nil
	}
	
	func getPendingUserFavoriteOp(forUser: KrakenUser, inContext: NSManagedObjectContext) -> PostOpUserFavorite? {
		if let ops = postOps {
			for op in ops {
				if let userStarOp = op as? PostOpUserFavorite, let userBeingFavorited = userStarOp.userBeingFavorited,
						userBeingFavorited.username == forUser.username {
					let starOpInContext = try? inContext.existingObject(with: userStarOp.objectID) as? PostOpUserFavorite
					return starOpInContext
				}
			}
		}
		return nil
	}
	
	func getPendingProfileEditOp(inContext: NSManagedObjectContext = LocalCoreData.shared.mainThreadContext) -> PostOpUserProfileEdit? {
		if let ops = postOps {
			for op in ops {
				if let profileEditOp = op as? PostOpUserProfileEdit,
						profileEditOp.author.username == username {
					let opInContext = try? inContext.existingObject(with: profileEditOp.objectID) as? PostOpUserProfileEdit
					return opInContext
				}
			}
		}
		return nil
	}
	
	func getPendingPhotoEditOp(inContext: NSManagedObjectContext = LocalCoreData.shared.mainThreadContext) -> PostOpUserPhoto? {
		if let ops = postOps {
			for op in ops {
				if let profileEditOp = op as? PostOpUserPhoto,
						profileEditOp.author.username == username {
					let opInContext = try? inContext.existingObject(with: profileEditOp.objectID) as? PostOpUserPhoto
					return opInContext
				}
			}
		}
		return nil
	}
	
	// The v2Object in this instance is NOT (generally) the logged-in user. It's another userProfile where
	// it contains data specific to the logged-in user's POV--user comments and stars.
	func parseV2UserProfileCommentsAndStars(context: NSManagedObjectContext, v2Object: TwitarrV2UserProfile,
			targetUser: KrakenUser) {
		guard self == CurrentUser.shared.getLoggedInUser(in: context) else {
			CoreDataLog.debug("parseV2UserProfileCommentsAndStars can only be called on the current logged in user.")
			return
		}
		
		var commentToUpdate = userComments?.first(where: { $0.commentedOnUser.username == v2Object.username } )
		
		// Only create a comment object if there's some content to put in it
		if commentToUpdate == nil && v2Object.comment != nil {
			commentToUpdate = UserComment(context: context)
		}
		
		// We won't ever delete the comment object once one has been created; that's okay--the comment 
		// itself should become "".
		commentToUpdate?.build(context: context, userCommentedOn: targetUser, loggedInUser: self, 
				comment: v2Object.comment)
	
		updateUserStar(context: context, targetUser: targetUser, newState: v2Object.starred)			
	}
	
	func updateUserStar(context: NSManagedObjectContext, targetUser: KrakenUser, newState: Bool?) {
		//
		if let isStarred = newState {
			let currentlyStarred = starredUsers?.contains(targetUser) ?? false
			if isStarred && !currentlyStarred {
				starredUsers?.insert(targetUser)
			}
			else {
				starredUsers?.remove(targetUser)
			}
		}
	}
	
	// Photo should be resized for upload and should be a mime type the server can understand.
	// Puts the photo data into a postOp.
	func setUserProfilePhoto(photoData: Data?, mimeType: String) {
		guard username == CurrentUser.shared.loggedInUser?.username else { return }
		
		let context = LocalCoreData.shared.networkOperationContext
		context.perform {
			do {
				// Check for existing photo update op for this user
				let op = self.getPendingPhotoEditOp(inContext: context) ?? PostOpUserPhoto(context: context)
				if let p = photoData {
					op.image = p as NSData
				}
				else {
					op.image = nil
				}
				op.imageMimetype = mimeType
				op.operationState = .readyToSend
			
				try context.save()
			}
			catch {
				CoreDataLog.error("Couldn't save context.", ["error" : error])
			}
		}

	}

    
}

@objc(UserComment) public class UserComment : KrakenManagedObject {
	@NSManaged public var comment: String?
	@NSManaged public var commentingUser: KrakenUser
	@NSManaged public var commentedOnUser: KrakenUser

	func build(context: NSManagedObjectContext, userCommentedOn: KrakenUser, loggedInUser: KrakenUser, comment: String?) {
		TestAndUpdate(\.comment, comment)
		if commentingUser.username != loggedInUser.username  {
			commentingUser = loggedInUser
		}
		if commentedOnUser.username != userCommentedOn.username {
			commentedOnUser = userCommentedOn
		}
	}
}

// There is at most 1 *current* logged-in user at a time. That user is specified by CurrentUser.shared.loggedInUser.
// We may store the login token for multiple users, but only one of them is *active* at a time.
@objc class CurrentUser: NSObject {
	static let shared = CurrentUser()
	
	// This var, right here, is what the whole app looks at to see if someone is logged in, and if so--who.
	// If nil, the whole app sees 'nobody is logged in'.
	// This var is widely observed via KVO.
	@objc dynamic var loggedInUser: LoggedInKrakenUser?
	
	// The last error we got from the server. Cleared when we start a new activity.
	@objc dynamic var isChangingLoginState: Bool = false
	@objc dynamic var lastError : ServerError?
	
	// This is the set of users that we are holding Twitarr auth keys for. At any time, we can swap one of these
	// users to become the loggedInUser, without asking for their password or talking to the server.
	@objc dynamic var credentialedUsers = Set<LoggedInKrakenUser>()
		
	func clearErrors() {
		lastError = nil
	}

	func isLoggedIn() -> Bool {
		return loggedInUser != nil
	}
	
	// TRUE iff multiple users are credentialed. If true, we put info cells in posting views telling the user
	// which account is active (i.e. "This tweet will be posted by @james").
	func isMultiUser() -> Bool {
		return credentialedUsers.count > 1
	}
	
	func getLoggedInUser(in context: NSManagedObjectContext) -> LoggedInKrakenUser? {
		guard let loggedInObjectID = loggedInUser?.objectID, let username = loggedInUser?.username else { return nil }
		var resultUser: LoggedInKrakenUser?
		context.performAndWait {
			do {
				resultUser = try context.existingObject(with: loggedInObjectID) as? LoggedInKrakenUser
				
				if resultUser == nil {
					let mom = LocalCoreData.shared.persistentContainer.managedObjectModel
					let request = mom.fetchRequestFromTemplate(withName: "FindAUser", 
							substitutionVariables: [ "username" : username ]) as! NSFetchRequest<KrakenUser>
					let results = try request.execute()
					resultUser = results.first as? LoggedInKrakenUser
				}
			}
			catch {
				CoreDataLog.error("Error while getting logged in user for context.", ["error" : error])
			}
		}
		return resultUser
	}
	
	// Sets the active user to one of the credentialed users. 'Active' means the user the app treats as being logged
	// in in the classic one-user-at-a-time sense. Seamails, likes, reactions, all the user-specific content will 
	// be shown from the POV and permissions of this user. Note that this fn does not call the server, and can't 
	// be used to switch to a user that hasn't entered their credentials (that is, logged in).
	func setActiveUser(to user: LoggedInKrakenUser) {
		if credentialedUsers.contains(user) {
			loggedInUser = user
			Settings.shared.activeUsername = user.username
		}
	}
	
	func loginUser(name: String, password: String) {
		// For lots of reasons, logging in doesn't do anything immediately, nor does it return a value.
		guard !isChangingLoginState else {
			return
		}
		isChangingLoginState = true
		clearErrors()
		
		let authStruct = TwitarrV2AuthRequestBody(username: name, password: password)
		let authData = try! JSONEncoder().encode(authStruct)
		
		// For content-type form-data
//		let authQuery = "username=\(name)&password=\(password)".data(using: .utf8)!
		
		// Call /api/v2/user/auth, and then call whoami
		var request = NetworkGovernor.buildTwittarV2Request(withPath:"/api/v2/user/auth", query: nil)
		request.httpMethod = "POST"
		request.httpBody = authData
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		NetworkGovernor.shared.queue(request) { package in
			if let error = NetworkGovernor.shared.parseServerError(package) {
				// Login failed.
				self.lastError = error
				self.isChangingLoginState = false
			}
			else if let data = package.data {
				let decoder = JSONDecoder()
				if let authResponse = try? decoder.decode(TwitarrV2AuthResponse.self, from: data) {
					if authResponse.status == "ok" {
						self.loadProfileInfo(keyToUseDuringLogin: authResponse.key)
					}
					else
					{
						self.lastError = ServerError("Unknown error")
						self.isChangingLoginState = false
					}
				}
			} 
			else {
				// Login failed.
				self.isChangingLoginState = false
			}
		}
	}
	
	// Loads the profile info for the logged-in user. During login, this is called both to get 
	// initial profile info and to validate the login key. Note that if this call fails during login, the user
	// doesn't log in.
	func loadProfileInfo(keyToUseDuringLogin: String? = nil) {
		
		// Need an auth key or this won't work. If we're mid-login, loggedInUser will be nil.
		guard let key = keyToUseDuringLogin ?? self.loggedInUser?.twitarrV2AuthKey else {
			return
		}
		
		// If we're not logged in, addUserCredential will do nothing. If we are logged in, addUserCredential
		// will replace 'key' in the query with the logged in user's key.
		var queryParams = [ URLQueryItem(name:"key", value:key) ]
		if keyToUseDuringLogin != nil {
			queryParams.append(URLQueryItem(name: "key", value: keyToUseDuringLogin))
		}
		else {
			// Make sure we pull the auth key from the main thread
			let mainContext = LocalCoreData.shared.mainThreadContext
			var authKey: String?
			mainContext.performAndWait {
				authKey = CurrentUser.shared.loggedInUser?.twitarrV2AuthKey
			}
			if let authKey = authKey {
				queryParams.append(URLQueryItem(name: "key", value: authKey))
			}
		}
		let request = NetworkGovernor.buildTwittarV2Request(withPath:"/api/v2/user/profile", query: queryParams)
		
		NetworkGovernor.shared.queue(request) { package in
			if let error = NetworkGovernor.shared.parseServerError(package) {
				// HTTP 401 error at this point means the user isn't actually logged in. This can happen if they
				// change their password from another device.
				self.logoutUser()
				self.lastError = error
			}
			else if package.response == nil {
				// No response object indicates a network error of some sort (NOT a server error)
			}
			else {
				let decoder = JSONDecoder()
				if let data = package.data,  let profileResponse = try? decoder.decode(TwitarrV2CurrentUserProfileResponse.self, from: data) {
					
					// Adds the user to the cache if it doesn't exist.
					let krakenUser = UserManager.shared.updateLoggedInUserInfo(from: profileResponse.userAccount)
										
					// If this is a login action, set the logged in user, their key, and other values 
					if let keyUsedForLogin = keyToUseDuringLogin, let user = krakenUser {
						self.credentialedUsers.insert(user)
						self.loggedInUser = user
						user.twitarrV2AuthKey = keyUsedForLogin
						self.saveLoginCredentials()
						Settings.shared.activeUsername = user.username
					}
				}
				else {
					self.lastError = ServerError("Received a response from the server, but couldn't parse it.")
				}
			}
			
			// Success or failure, we are no longer trying to log in (if we had been).
			if keyToUseDuringLogin != nil {
				self.isChangingLoginState = false
			}
		}
	}
	
	// Since this app uses auth keys instead of session cookies to maintain logins, the logout API call
	// doesn't (currently) do anything for us. In order to logout (and requre auth to log in again) we only
	// have to discard the keys.
	func logoutUser(_ passedInUser: LoggedInKrakenUser? = nil) {
		// Only allow one login state change action at a time
		guard !isChangingLoginState else {
			return
		}
		var user = passedInUser
		if user == nil {
			user = loggedInUser
		}
		guard let userToLogout = user else  { return }
		guard credentialedUsers.contains(userToLogout) else { return }
		
		isChangingLoginState = true
		clearErrors()
		
		// We send a logout request, but don't care about its result
		let queryParams = [ URLQueryItem(name: "key", value: userToLogout.twitarrV2AuthKey) ]
		let request = NetworkGovernor.buildTwittarV2Request(withPath:"/api/v2/user/logout", query: queryParams)
		NetworkGovernor.shared.queue(request) { package in
			let _ = NetworkGovernor.shared.parseServerError(package)
		}
		
		// Throw away all login info
		credentialedUsers.remove(userToLogout)
		if loggedInUser?.username == userToLogout.username {
			if credentialedUsers.count == 1, let stillThereUser = credentialedUsers.first {
				// If there's exactly one credentialed user, make them active.
				setActiveUser(to: stillThereUser)
			}
			else {
				self.loggedInUser = nil
			}
		}
		
		let cookiesToDelete = HTTPCookieStorage.shared.cookies?.filter { $0.name == "_twitarr_session" }
		for cookie in cookiesToDelete ?? [] {
			HTTPCookieStorage.shared.deleteCookie(cookie)
		}
		removeLoginCredentials(for: userToLogout.username)
		
		// Todo: Tell Seamail and Forums to reap for logout
		
		isChangingLoginState = false
	}
	
	func createNewAccount(name: String, password: String, displayName: String?, regCode: String) {
		guard !isChangingLoginState else {
			return
		}
		isChangingLoginState = true
		clearErrors()
		
		let authStruct = TwitarrV2CreateAccountRequest(username: name, password: password, displayName: displayName, regCode: regCode)
		let encoder = JSONEncoder()
		let authData = try! encoder.encode(authStruct)
//		print (String(decoding:authData, as: UTF8.self))
				
		// Call /api/v2/user/new, and then call whoami
		var request = NetworkGovernor.buildTwittarV2Request(withPath:"/api/v2/user/new", query: nil)
		request.httpMethod = "POST"
		request.httpBody = authData
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		NetworkGovernor.shared.queue(request) { (package: NetworkResponse) in
			if let error = NetworkGovernor.shared.parseServerError(package) {
				// CreateUserAccount failed.
				self.lastError = error
				self.isChangingLoginState = false
			}
			else {
				let decoder = JSONDecoder()
				if let data = package.data, let authResponse = try? decoder.decode(TwitarrV2CreateAccountResponse.self, 
						from: data), authResponse.status == "ok" {
					self.loadProfileInfo(keyToUseDuringLogin: authResponse.key)
				}
				else
				{
					self.lastError = ServerError("Unknown error")
					self.isChangingLoginState = false
				}
			} 
		}
	}
	
	// Must be logged in to change password; resetPassword works while logged but requres reg code.
	func changeUserPassword(currentPassword: String, newPassword: String, done: @escaping () -> Void) {
		guard !isChangingLoginState, let savedCurrentUserName = self.loggedInUser?.username else {
			return
		}
		clearErrors()
		
		let changePasswordStruct = TwitarrV2ChangePasswordRequest(currentPassword: currentPassword, newPassword: newPassword)
		let encoder = JSONEncoder()
		let authData = try! encoder.encode(changePasswordStruct)
				
		// Call /api/v2/user/change_password
		var request = NetworkGovernor.buildTwittarV2Request(withPath:"/api/v2/user/change_password", query: nil)
		request.httpMethod = "POST"
		request.httpBody = authData
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		NetworkGovernor.addUserCredential(to: &request)
		NetworkGovernor.shared.queue(request) { (package: NetworkResponse) in
			if let error = NetworkGovernor.shared.parseServerError(package) {
				self.lastError = error
			}
			else {
				let decoder = JSONDecoder()
				if  let data = package.data, let response = try? decoder.decode(TwitarrV2ChangePasswordResponse.self, from: data),
						response.status == "ok" && savedCurrentUserName == self.loggedInUser?.username {
					self.loggedInUser?.twitarrV2AuthKey = response.key
					self.saveLoginCredentials()
					done()
				}
				else
				{
					self.lastError = ServerError("Unknown error")
				}
			} 
		}
	}
	
	// ?? Can Reset be used when you're logged in? It doesn't send a new auth key.
	func resetPassword(name: String, regCode: String, newPassword: String, done: @escaping () -> Void) {
		guard !isChangingLoginState else {
			return
		}
		clearErrors()
		
		let resetPasswordStruct = TwitarrV2ResetPasswordRequest(username: name, regCode: regCode, newPassword: newPassword)
		let encoder = JSONEncoder()
		let authData = try! encoder.encode(resetPasswordStruct)
				
		// Call /api/v2/user/reset_password
		var request = NetworkGovernor.buildTwittarV2Request(withPath:"/api/v2/user/reset_password", query: nil)
		request.httpMethod = "POST"
		request.httpBody = authData
		NetworkGovernor.shared.queue(request) { (package: NetworkResponse) in
			if let error = NetworkGovernor.shared.parseServerError(package) {
				self.lastError = error
			}
			else {
				let decoder = JSONDecoder()
				if  let data = package.data, let response = try? decoder.decode(TwitarrV2ResetPasswordResponse.self, from: data) {
					if response.status == "ok" {
						done()
					}
					else
					{
						self.lastError = ServerError("Unknown error")
					}
				}
			} 
		}
	}
	
// MARK: Move these to LoggedInKrakenUser!!!
	
	// This lets the logged in user set a private comment about another user.
	func setUserComment(_ comment: String, forUser: KrakenUser) {
		clearErrors()
		let context = LocalCoreData.shared.networkOperationContext
		guard let loggedInUser = self.getLoggedInUser(in: context) else { return }
		
		context.performAndWait {
			do {
				// get foruser in context
				let userInContext = try context.existingObject(with: forUser.objectID) as! KrakenUser
					
				// Check for existing op for this user
				let op = loggedInUser.getPendingUserCommentOp(commentingOn: userInContext, inContext: context) ?? PostOpUserComment(context: context)
				op.comment = comment
				op.userCommentedOn = userInContext
				op.operationState = .readyToSend

			
				try context.save()
			}
			catch {
				CoreDataLog.error("Couldn't save context.", ["error" : error])
			}
		}
	}
	
	func cancelUserCommentOp(_ op: PostOpUserComment) {
		// Disallow cancelling other people's ops
		guard let currentUser = loggedInUser, currentUser.username == op.author.username else { return }
		
		PostOperationDataManager.shared.remove(op: op)
	}
	
	// This lets the logged in user favorite another user.
	func setFavoriteUser(forUser: KrakenUser, to newState: Bool) {
		guard let loggedInUser = loggedInUser else { return }
		clearErrors()
		
		let context = LocalCoreData.shared.networkOperationContext
		context.performAndWait {
			do {
				// get user in context
				let userInContext = try context.existingObject(with: forUser.objectID) as! KrakenUser
					
				// Check for existing op for this user
				let op = loggedInUser.getPendingUserFavoriteOp(forUser: forUser, inContext: context) ?? 
						PostOpUserFavorite(context: context)
				op.isFavorite = newState
				op.userBeingFavorited = userInContext
				op.operationState = .readyToSend
			
				try context.save()
			}
			catch {
				CoreDataLog.error("Couldn't save context.", ["error" : error])
			}
		}
	}
	
	// 
	func changeUserProfileFields(displayName: String?, realName: String?, pronouns: String?, email: String?, 
			homeLocation: String?, roomNumber: String?) {
		guard let loggedInUser = loggedInUser else { return }
		
		let context = LocalCoreData.shared.networkOperationContext
		context.perform {
			do {
				// Check for existing op for this user
				let op = loggedInUser.getPendingProfileEditOp(inContext: context) ?? 
						PostOpUserProfileEdit(context: context)
				op.displayName = displayName
				op.realName = realName
				op.pronouns = pronouns
				op.email = email
				op.homeLocation = homeLocation
				op.roomNumber = roomNumber
				op.operationState = .readyToSend
			
				try context.save()
			}
			catch {
				CoreDataLog.error("Couldn't save context.", ["error" : error])
			}
		}
	}
	
	
}

/* Secure storage of user auth data.

	We save a single item into KeychainServices. That item is a small struct containing both the username and the 
	auth key--not the password--of the logged-in user. The auth key comes from the server. The item is stored in the 
	keychain dictionary with a key that contains the base URL of the server that user was logged in to.
	
	This means that the app can support being 'logged in' to multiple servers at once, with different credentials, in
	that the auth key comes from the server and doesn't really time out. The app still only supports talking to a single
	server per launch. But, for a particular server URL, we can save only one login credential at a time; that of the 
	logged-in user.
	
	Also--we don't track previous values of the base URL, so we don't have a way to know if switching the baseURL to point
	to another server will cause a user to be logged in at next app launch.
*/
extension CurrentUser {
	
	// Only save login creds as a result of successful server reponse to login.
 	@discardableResult public func saveLoginCredentials() -> Bool {
 		guard let user = loggedInUser, let authKey = user.twitarrV2AuthKey, 
 				let keyData = authKey.data(using:.utf8, allowLossyConversion: false) else { return false }
 				
		// Keychain won't let us 'add' creds that already exist--have to either 'update' instead, or delete and re-add.
		removeLoginCredentials(for: user.username)
 		
 		let keychainObjectKey: String = Settings.shared.baseURL.absoluteString
		let query: [String : Any] = [
				kSecClass as String: kSecClassInternetPassword as String,
				kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
				kSecAttrAccount as String: user.username,
				kSecAttrServer as String: keychainObjectKey,
				kSecAttrSecurityDomain as String: LoggedInKrakenUser.UserRole.stringForRole(role: user.userRole),	// Heh. Not what SecurityDomain is actually for.
				kSecValueData as String: keyData as NSData]

		let status: OSStatus = SecItemAdd(query as CFDictionary, nil)
		KeychainLog.assert(status == noErr, "Failure to save login creds.", ["status" : status])
		return status == noErr
	}
	
	// loggedInUser may already be nil when this is called, or this may get used to remove creds for users
	// not the currently logged in user.
	func removeLoginCredentials(for username: String) {
 		let keychainObjectKey: String = Settings.shared.baseURL.absoluteString
		let query: [String : Any] = [
				kSecClass as String: kSecClassInternetPassword as String,
				kSecAttrServer as String: keychainObjectKey,
				kSecAttrAccount as String: username,
				kSecReturnData as String: true]

        // Delete any existing items, for all accounts on this server.
        let status = SecItemDelete(query as CFDictionary)
		KeychainLog.assert(status == errSecSuccess || status == errSecItemNotFound, 
				"Keychain credential remove failed.", ["status" : status])

	}

	// Called early on during app launch. Finds all the users who are logged in, sets up one of them as active.
	func setInitialLoginState() {
 		let keychainObjectKey: String = Settings.shared.baseURL.absoluteString
		let query: [String : Any] = [
				kSecClass as String : kSecClassInternetPassword,
				kSecAttrServer as String : keychainObjectKey,
				kSecReturnAttributes as String : true,
				kSecReturnData as String : true,
				kSecMatchLimit as String : kSecMatchLimitAll]

		var dataTypeRef: AnyObject?
		let status: OSStatus = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
		if status == errSecSuccess, let recordArray = dataTypeRef as? [[String : Any]] {
			var usersWithCreds = Set<LoggedInKrakenUser>()
			for recordDict in recordArray {
				if let accountName = recordDict[kSecAttrAccount as String] as? String,
						let passwordData = recordDict[kSecValueData as String] as? Data,
						let authKey = String(data: passwordData, encoding: String.Encoding.utf8),
						let userRoleStr = recordDict[kSecAttrSecurityDomain as String] as? String {

					// In the future (post-2020 cruise?), we should use the creationDate key to find and remove
					// old passwords.

					//
					if let krakenUser = UserManager.shared.user(accountName) as? LoggedInKrakenUser {
						krakenUser.twitarrV2AuthKey = authKey
						krakenUser.userRole = LoggedInKrakenUser.UserRole.roleForString(str: userRoleStr) ?? .user
						usersWithCreds.insert(krakenUser)
					}
				}
			}
			credentialedUsers = usersWithCreds

			if let activeUsername = Settings.shared.activeUsername,
					let activeUser = usersWithCreds.first(where: { $0.username == activeUsername }) {
				// 
				loggedInUser = activeUser
				loadProfileInfo()
				KeychainLog.debug("Logging in as a user at app launch")
			}
			else if usersWithCreds.count == 1, let activeUser = usersWithCreds.first {
				loggedInUser = activeUser
				loadProfileInfo()
				Settings.shared.activeUsername = activeUser.username
				KeychainLog.debug("Logging in default credentialed user at app launch")
			}
			else {
				KeychainLog.debug("Found \(credentialedUsers.count) users with creds, but launching inactive.")
			}
		}
		else if status == errSecItemNotFound {	// errSecItemNotFound is -25300
			// No record found; this is fine. Means we're not logging in as anyone at app launch.
			KeychainLog.debug("App launching with no logged in user.")
		}
		else {
			KeychainLog.error("Failure loading keychain info at app launch.", ["status" : status])
		}
	}
}


// MARK: - Twitarr V2 API Structs

struct TwitarrV2ErrorResponse: Codable {
	let status: String
	let error: String
}

struct TwitarrV2ErrorsResponse: Codable {
	let status: String
	let errors: [String]
}

struct TwitarrV2ErrorDictionaryResponse: Codable {
	let status: String
	let errors: [String : [String]]
}

// POST /api/v2/user/new 
struct TwitarrV2CreateAccountRequest: Codable {
	let username: String
	let password: String
	let displayName: String?
	let regCode: String
	
	enum CodingKeys: String, CodingKey {
		case username = "new_username"
		case password = "new_password"
		case displayName = "display_name"
		case regCode = "registration_code"
	}
}

struct TwitarrV2CreateAccountResponse: Codable {
	let status: String
	let user: TwitarrV2UserAccount
	let key: String
}


// /api/v2/user/auth
struct TwitarrV2AuthRequestBody: Codable {
	let username: String
	let password: String
}

struct TwitarrV2AuthResponse: Codable {
	let status: String
	let username: String
	let key: String
}

// /api/v2/user/change_password
struct TwitarrV2ChangePasswordRequest: Codable {
	let currentPassword: String
	let newPassword: String

	enum CodingKeys: String, CodingKey {
		case currentPassword = "current_password"
		case newPassword = "new_password"
	}
}

struct TwitarrV2ChangePasswordResponse: Codable {
	let status: String
	let key: String
}

// /api/v2/user/reset_password
struct TwitarrV2ResetPasswordRequest: Codable {
	let username: String
	let regCode: String
	let newPassword: String

	enum CodingKeys: String, CodingKey {
		case username = "username"
		case regCode = "registration_code"
		case newPassword = "new_password"
	}
}

struct TwitarrV2ResetPasswordResponse: Codable {
	let status: String
	let message: String
}

// /api/v2/user/profile
struct TwitarrV2CurrentUserProfileResponse: Codable {
	let status: String
	let userAccount: TwitarrV2UserAccount
	let needPasswordChange: Bool
	
	enum CodingKeys: String, CodingKey {
		case status
		case userAccount = "user"
		case needPasswordChange = "need_password_change"
	}
}

// This is the User type that is only returned for the current logged in user. The other variant is TwitarrV2UserProfile.
struct TwitarrV2UserAccount: Codable {
	let username: String
	let role: String
	let emailAddress: String?
	let displayName: String
	let currentLocation: String?
	let lastLogin: Int64
	let emptyPassword: Bool
	let lastPhotoUpdated: Int64
	let roomNumber: String?
	let realName: String?
	let pronouns: String?
	let homeLocation: String?
	let unnoticedAlerts: Bool?
	
	enum CodingKeys: String, CodingKey {
		case username, role, pronouns
		case displayName = "display_name"
		case emailAddress = "email"
		case currentLocation = "current_location"
		case lastLogin = "last_login"
		case emptyPassword = "empty_password"
		case lastPhotoUpdated = "last_photo_updated"
		case roomNumber = "room_number"
		case realName = "real_name"
		case homeLocation = "home_locations"
		case unnoticedAlerts = "unnoticed_alerts"
	}
}
