//
//  CurrentUser.swift
//  Kraken
//
//  Created by Chall Fry on 3/22/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import Foundation
import CoreData
import UserNotifications

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
	
	@NSManaged public var blockedUsers: Set<KrakenUser>

	@NSManaged public var userComments: Set<UserComment>?			// This set is comments the logged in user has made about *others*
	@NSManaged public var starredUsers: Set<KrakenUser>?			// Set of users the logged in user has starred.
	@NSManaged public var lastLogin: Int64
	@NSManaged public var lastAlertCheckTime: Int64
	@NSManaged public var lastSeamailCheckTime: Int64
	
	// Either a Twitarr V2 key as returned by /api/v2/user/auth, or a V3 token as returned by /api/v3/auth/login 
	// Shouldn't have collisions because one server URL can only be one or the other.
	@NSManaged public var authKey: String?
	
	// Alerts
	@NSManaged public var badgeTweets: Int32
	@NSManaged public var upToDateSeamailThreads: Set<SeamailThread>

	// Info about the current user that should not be in KrakenUser nor cached to disk.
	@objc dynamic var userRole: UserRole = .loggedOut
	
// MARK: Model Builders
	func buildFromV3UserProfile(context: NSManagedObjectContext, v3Object: TwitarrV3UserProfileData) {
		TestAndUpdate(\.username, v3Object.username)
		TestAndUpdate(\.displayName, v3Object.displayName ?? "")
		TestAndUpdate(\.realName, v3Object.realName)
		TestAndUpdate(\.pronouns, v3Object.preferredPronoun)

		TestAndUpdate(\.emailAddress, v3Object.email)
		TestAndUpdate(\.homeLocation, v3Object.homeLocation)
		TestAndUpdate(\.roomNumber, v3Object.roomNumber)

		// Need to add		
//		about
//		message
//		limitAccess

		// V2 has these; V3 doesn't
//		TestAndUpdate(\.currentLocation, v2Object.currentLocation)
//		TestAndUpdate(\.lastPhotoUpdated, v2Object.lastPhotoUpdated)
//		TestAndUpdate(\.lastLogin, v2Object.lastLogin)
//		userRole = UserRole.roleForString(str: v2Object.role) ?? .user
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

// MARK: V2	
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
	
	// This lets the logged in user set a private comment about another user, by creating a
	// PostOp to send to the server with the comment.
	func setUserComment(_ comment: String, forUser: KrakenUser) {
		LocalCoreData.shared.performNetworkParsing { context in
			context.pushOpErrorExplanation("Failure saving user note op.")
			// get foruser in context
			let selfInContext = try context.existingObject(with: self.objectID) as! LoggedInKrakenUser
			let targetUserInContext = try context.existingObject(with: forUser.objectID) as! KrakenUser
					
			// Check for existing op for this user
			let op = selfInContext.getPendingUserCommentOp(commentingOn: targetUserInContext,
					inContext: context) ?? PostOpUserComment(context: context)
			op.comment = comment
			op.userCommentedOn = targetUserInContext
			op.operationState = .readyToSend
		}
	}

	func cancelUserCommentOp(_ op: PostOpUserComment) {
		// Disallow cancelling other people's ops
		guard username == op.author.username else { return }
		PostOperationDataManager.shared.remove(op: op)
	}
	
	func ingestUserComment(from: TwitarrV3NoteData) {
		LocalCoreData.shared.performNetworkParsing { context in
			context.pushOpErrorExplanation("Failure saving user note.")
			// get foruser in context
			let selfInContext = try context.existingObject(with: self.objectID) as! LoggedInKrakenUser
			let targetUserInContext = UserManager.shared.user(from.targetUser.userID, inContext: context) ??
					KrakenUser(context: context)
			targetUserInContext.buildFromV3UserHeader(context: context, v3Object: from.targetUser)

			// Find existing comment object--only create a comment object if there's some content to put in it
			var commentToUpdate = selfInContext.userComments?.first(where: { $0.commentedOnUser.userID == targetUserInContext.userID })
			if commentToUpdate == nil && !from.note.isEmpty {
				commentToUpdate = UserComment(context: context)
			}
			// We won't ever delete the comment object once one has been created; that's okay--the comment 
			// itself should become "".
			commentToUpdate?.build(context: context, userCommentedOn: targetUserInContext, loggedInUser: selfInContext, 
					comment: from.note)
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
	// This var is widely observed via KVO. And, this should be used by the main thread only.
	@objc dynamic var loggedInUser: LoggedInKrakenUser?
	private var loggedInUserObjectID: NSManagedObjectID?
	
	// The last error we got from the server. Cleared when we start a new activity.
	@objc dynamic var isChangingLoginState: Bool = false
	@objc dynamic var lastError : Error?
	
	// This is the set of users that we are holding Twitarr auth keys for. At any time, we can swap one of these
	// users to become the loggedInUser, without asking for their password or talking to the server.
	@objc dynamic var credentialedUsers = NSMutableSet()
		
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
		guard let loggedInObjectID = loggedInUserObjectID else { return nil }
		var resultUser: LoggedInKrakenUser?
		context.performAndWait {
			do {
				resultUser = try context.existingObject(with: loggedInObjectID) as? LoggedInKrakenUser
				
//				if resultUser == nil {
//					let mom = LocalCoreData.shared.persistentContainer.managedObjectModel
//					let request = mom.fetchRequestFromTemplate(withName: "FindAUser", 
//							substitutionVariables: [ "username" : username ]) as! NSFetchRequest<KrakenUser>
//					let results = try request.execute()
//					resultUser = results.first as? LoggedInKrakenUser
//				}
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
		LocalCoreData.shared.mainThreadContext.performAndWait {
			if let userInMainContext = try? LocalCoreData.shared.mainThreadContext.existingObject(with: user.objectID) as? LoggedInKrakenUser {
				if credentialedUsers.contains(userInMainContext) {
					loggedInUser = userInMainContext
					loggedInUserObjectID = userInMainContext.objectID
					Settings.shared.activeUsername = user.username
					self.checkForNotificationPermission()
				}
			}
		}
	}
	
	func loginUser(name: String, password: String) {
		// For lots of reasons, logging in doesn't do anything immediately, nor does it return a value.
		guard !isChangingLoginState else {
			return
		}
		isChangingLoginState = true
		clearErrors()
		
		// For content-type form-data
//		let authQuery = "username=\(name)&password=\(password)".data(using: .utf8)!
		
		// Call login, and then call whoami
		let loginAPIPath = Settings.apiV3 ? "/api/v3/auth/login" : "/api/v2/user/auth"
		var request = NetworkGovernor.buildTwittarV2Request(withPath: loginAPIPath, query: nil)
		request.httpMethod = "POST"
		if Settings.apiV3 {
			let credentials = "\(name):\(password)".data(using: .utf8)!.base64EncodedString()
			request.addValue("Basic \(credentials)", forHTTPHeaderField: "Authorization")
		}
		else {
			let authStruct = TwitarrV2AuthRequestBody(username: name, password: password)
			let authData = try! JSONEncoder().encode(authStruct)
			request.httpBody = authData
			request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		}
		
		NetworkGovernor.shared.queue(request) { package in
			if let error = NetworkGovernor.shared.parseServerError(package) {
				// Login failed.
				self.lastError = error
			}
			else if let data = package.data {
				let decoder = JSONDecoder()
				if let authResponse = try? decoder.decode(TwitarrV2AuthResponse.self, from: data), authResponse.status == "ok" {
					self.loginSuccess(username: authResponse.username, authKey: authResponse.key)
				} 
				else if let loginResponse = try? decoder.decode(TwitarrV3LoginResponse.self, from: data) {
					self.loginSuccess(username: name, authKey: loginResponse.token, userID: loginResponse.userID)
				}
				else {
					self.lastError = ServerError("Unknown error")
				}
			} 
			else {
				// Login failed.
				self.lastError = package.networkError
			}
			
			self.isChangingLoginState = false
		}
	}
	
	// Only call this when a user successfully completes login auth, and moves from not-logged-in to logged in.
	// Or, when the auth token changes, such as password reset or recovery.
	// Call setActiveUser() to switch between users that have already authed.
	// On exit from this fn, the user is fully logged in
	func loginSuccess(username: String, authKey: String, userID: UUID? = nil) {
		let context = LocalCoreData.shared.networkOperationContext
		var krakenUser: LoggedInKrakenUser?
		context.performAndWait {
			do {
				krakenUser = UserManager.shared.user(username, inContext: context) as? LoggedInKrakenUser

				// Adds the user to the cache if it doesn't exist.
				if krakenUser == nil {
					krakenUser = LoggedInKrakenUser(context: context)
					krakenUser?.username = username
					if let userID = userID {
						krakenUser?.userID = userID
					}
				}
				
				if let user = krakenUser {
					user.authKey = authKey
					try context.save()
				}
			} 
			catch {
				CoreDataLog.error("Failure saving CoreData context.", ["Error" : error])
			}
		}
			
		if let networkThreadUser = krakenUser {
			DispatchQueue.main.sync {
				if let user = try? LocalCoreData.shared.mainThreadContext.existingObject(with: networkThreadUser.objectID)
						as? LoggedInKrakenUser {
						
					// Make sure the main thread context has the updated user with the authKey
					LocalCoreData.shared.mainThreadContext.refresh(user, mergeChanges: false)
					self.credentialedUsers.add(user)
					self.setActiveUser(to: user)
					
					// Login is now complete. Process after-login actions.
					self.checkForNotificationPermission()
					
					// Immediately after login, load the user's profile
					self.loadProfileInfo()
				}
			}
		}
	}
	
	func loadProfileInfo() {
		let queryParams = [URLQueryItem]()
		let profileAPIPath = Settings.apiV3 ? "/api/v3/user/profile" : "/api/v2/user/profile"
		var request = NetworkGovernor.buildTwittarV2Request(withPath:profileAPIPath, query: queryParams)
		NetworkGovernor.addUserCredential(to: &request)
		
		NetworkGovernor.shared.queue(request) { package in
			if let error = NetworkGovernor.shared.parseServerError(package) {
				// HTTP 401 error at this point means the user isn't actually logged in. This can happen if they
				// change their password from another device. 403 can happen if the user is banned.
				if error.httpStatus == 401 || error.httpStatus == 403 {
					self.logoutUser()
				}
				self.lastError = error
			}
			else if package.response == nil {
				// No response object indicates a network error of some sort (NOT a server error)
			}
			else {
				let decoder = JSONDecoder()
				if let data = package.data {
					if let profileResponse = try? decoder.decode(TwitarrV2CurrentUserProfileResponse.self, from: data) {
						// Adds the user to the cache if it doesn't exist.
						let _ = UserManager.shared.updateLoggedInUserInfo(from: profileResponse.userAccount)
					} else if let profileResponse = 
							try? decoder.decode (TwitarrV3UserProfileData.self, from: data) {
						let _ = UserManager.shared.updateLoggedInUserInfo(from: profileResponse)
					}
				}
				else {
					self.lastError = ServerError("Received a response from the server, but couldn't parse it.")
				}
			}
		}
	}
	
	// When a user logs in, we ask them for permission to send them notifications, as logged in users can get updates
	// on incoming seamails and announcements. Since we're not *immediately* posting a notification due to a user request,
	// only show the alert if the state is .notDetermined.
	func checkForNotificationPermission() {
		let center = UNUserNotificationCenter.current()
		center.getNotificationSettings { settings in
			guard settings.authorizationStatus == .notDetermined else { return }
				
			center.requestAuthorization(options: [.alert, .sound]) { (granted, error) in
				if granted {
				}
			}
		}
	}
	
	// Since this app uses auth keys instead of session cookies to maintain logins, the logout API call
	// doesn't (currently) do anything for us. In order to logout (and requre auth to log in again) we only
	// have to discard the keys.
	func logoutUser(_ passedInUser: LoggedInKrakenUser? = nil) {
//		DispatchQueue.main.async {
			// Only allow one login state change action at a time
			guard !isChangingLoginState else { return }
			guard let userToLogout = passedInUser ?? loggedInUser else { return }
			guard credentialedUsers.contains(userToLogout) else { return }
			
			isChangingLoginState = true
			clearErrors()
			
			// We send a logout request, but don't care about its result
			let logoutAPIPath = Settings.apiV3 ? "/api/v3/auth/logout" : "/api/v2/user/logout"
			let queryParams: [URLQueryItem] = []
			var request = NetworkGovernor.buildTwittarV2Request(withPath:logoutAPIPath, query: queryParams)
			NetworkGovernor.addUserCredential(to: &request)
			request.httpMethod = "POST"
			NetworkGovernor.shared.queue(request) { package in
				// The only server errors we can get are variants of "That guy wasn't logged in" or "Your token is wrong"
				let _ = NetworkGovernor.shared.parseServerError(package)
			}
			
			LocalCoreData.shared.performLocalCoreDataChange { context, currentUser in
				context.pushOpErrorExplanation("Failure saving logout to Core Data.")
				let logoutUserInContext = try context.existingObject(with: userToLogout.objectID) as! LoggedInKrakenUser
				logoutUserInContext.authKey = nil
			}

			// Throw away all login info, if there's exactly 1 other logged-in user make them active, else nobody's active.
			credentialedUsers.remove(userToLogout)
			if loggedInUser?.username == userToLogout.username {
				if credentialedUsers.count == 1, let stillThereUser = self.credentialedUsers.anyObject() as? LoggedInKrakenUser {
					// If there's exactly one credentialed user, make them active.
					setActiveUser(to: stillThereUser)
				}
				else {
					self.loggedInUser = nil
					self.loggedInUserObjectID = nil
				}
			}
			
			let cookiesToDelete = HTTPCookieStorage.shared.cookies?.filter { $0.name == "_twitarr_session" }
			for cookie in cookiesToDelete ?? [] {
				HTTPCookieStorage.shared.deleteCookie(cookie)
			}
			
			// Todo: Tell Seamail and Forums to reap for logout
			
			isChangingLoginState = false
//		}
	}
	
	func createNewAccount(name: String, password: String, displayName: String?, regCode: String?) {
		guard !isChangingLoginState else { 
			lastError = ServerError("Another login/logout action is in progress. Please retry.")
			return
		}
		isChangingLoginState = true
		clearErrors()
		
		let encoder = JSONEncoder()
		var authData: Data
		var authPath: String
		if Settings.apiV3 {
			authPath = "/api/v3/user/create"
			let authStruct = TwitarrV3CreateAccountRequest(username: name, password: password, verification: regCode)
			authData = try! encoder.encode(authStruct)
		} else {
			authPath = "/api/v2/user/new"
			guard let regCode = regCode else { return }
			let authStruct = TwitarrV2CreateAccountRequest(username: name, password: password, 
					displayName: displayName, regCode: regCode)
			authData = try! encoder.encode(authStruct)
		}
	//	print (String(decoding:authData, as: UTF8.self))
				
		// Call the login endpoint
		var request = NetworkGovernor.buildTwittarV2Request(withPath:authPath, query: nil)
		request.httpMethod = "POST"
		request.httpBody = authData
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		NetworkGovernor.shared.queue(request) { (package: NetworkResponse) in
			if let error = NetworkGovernor.shared.parseServerError(package) {
				// CreateUserAccount failed.
				self.lastError = error
				self.isChangingLoginState = false
			}
			else if Settings.apiV3 {
				let decoder = JSONDecoder()
				if let data = package.data, let createAcctResponse = try? decoder.decode(TwitarrV3CreateAccountResponse.self, 
						from: data) {
					
					// Login the user immediately after account creation
					self.isChangingLoginState = false
					self.loginUser(name: createAcctResponse.username, password: password)
				}
				else
				{
					self.lastError = ServerError("Unknown error")
					self.isChangingLoginState = false
				}
			} else {
				let decoder = JSONDecoder()
				if let data = package.data, let authResponse = try? decoder.decode(TwitarrV2CreateAccountResponse.self, 
						from: data), authResponse.status == "ok" {
						
					// In V2, /user/new both creates an account and logs it in. The result packet has the auth key.
					self.loginSuccess(username: authResponse.user.username, authKey: authResponse.key)
				}
				else
				{
					self.lastError = ServerError("Unknown error")
					self.isChangingLoginState = false
				}
			} 
		}
	}
	
	// Must be logged in to change password; resetPassword works while logged out but requires reg code.
	func changeUserPassword(currentPassword: String, newPassword: String, done: @escaping () -> Void) {
		guard !isChangingLoginState, let savedCurrentUserName = self.loggedInUser?.username else {
			return
		}
		clearErrors()
		
		let authData: Data
		let encoder = JSONEncoder()
		if Settings.apiV3 {
			let changePasswordStruct = TwitarrV3ChangePasswordRequest(password: newPassword)
			authData = try! encoder.encode(changePasswordStruct)
		}
		else {
			let changePasswordStruct = TwitarrV2ChangePasswordRequest(currentPassword: currentPassword, newPassword: newPassword)
			authData = try! encoder.encode(changePasswordStruct)
		}
				
		// Call change_password
		let path = Settings.apiV3 ? "/api/v3/user/password" : "/api/v2/user/change_password"
		var request = NetworkGovernor.buildTwittarV2Request(withPath:path, query: nil)
		request.httpMethod = "POST"
		request.httpBody = authData
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		NetworkGovernor.addUserCredential(to: &request)
		NetworkGovernor.shared.queue(request) { (package: NetworkResponse) in
			if let error = NetworkGovernor.shared.parseServerError(package) {
				self.lastError = error
			}
			else if Settings.apiV3, let response = package.response, response.statusCode == 201 {
				// Success. Resetting a V3 password doesn't change the auth token.
				done()
			}
			else if let data = package.data {
				let decoder = JSONDecoder()
				if let response = try? decoder.decode(TwitarrV2ChangePasswordResponse.self, from: data),
						response.status == "ok" && savedCurrentUserName == self.loggedInUser?.username {
					self.loginSuccess(username: savedCurrentUserName, authKey: response.key)
					done()
				}
				else
				{
					self.lastError = ServerError("Unknown error")
				}
			} 
			else {
				self.lastError = ServerError("Unknown error")
			}
		}
	}
	
	// ?? Can Reset be used when you're logged in? It doesn't send a new auth key.
	// Reset is the thing that requires a regCode, or in v3 a recovery code.
	// In V3, regCode can actually be any of: Password, Recovery Code, Registration Code.
	// V3 only allows Registration Code to be used once.
	func resetPassword(name: String, regCode: String, newPassword: String, done: @escaping () -> Void) {
		guard !isChangingLoginState else {
			return
		}
		clearErrors()
		
		let authData: Data
		let encoder = JSONEncoder()
		if Settings.apiV3 {
			let resetPasswordStruct = TwitarrV3RecoverPasswordRequest(username: name, recoveryKey: regCode)
			authData = try! encoder.encode(resetPasswordStruct)
		}
		else {
			let resetPasswordStruct = TwitarrV2ResetPasswordRequest(username: name, regCode: regCode, newPassword: newPassword)
			authData = try! encoder.encode(resetPasswordStruct)
		}
				
		// Call reset_password
		let path = Settings.apiV3 ? "/api/v3/auth/recovery" : "/api/v2/user/reset_password"
		var request = NetworkGovernor.buildTwittarV2Request(withPath: path, query: nil)
		request.httpMethod = "POST"
		request.httpBody = authData
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		NetworkGovernor.shared.queue(request) { (package: NetworkResponse) in
			if let error = NetworkGovernor.shared.parseServerError(package) {
				self.lastError = error
			}
			else if let data = package.data {
				let decoder = JSONDecoder()
				if let response = try? decoder.decode(TwitarrV2ResetPasswordResponse.self, from: data) {
					if response.status == "ok" {
						done()
					}
					else
					{
						self.lastError = ServerError("Unknown error")
					}
				}
				else if let response = try? decoder.decode(TwitarrV3RecoverPasswordResponse.self, from: data) {
					// V3 reset returns a login token. Log ourselves in with it and immediately initiate a password change
					// to the user's new password.
					self.loginSuccess(username: name, authKey: response.token)
					self.changeUserPassword(currentPassword: "", newPassword: newPassword, done: done)
				}
				else {
					self.lastError = ServerError("Unknown error")
				}
			} 
		}
	}
	
// MARK: Move these to LoggedInKrakenUser!!!
		
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
	
	// Called early on during app launch. Finds all the users who are logged in, sets up one of them as active.
	func setInitialLoginState() {
		let context = LocalCoreData.shared.mainThreadContext
		context.performAndWait {
			do {
				let request = LoggedInKrakenUser.fetchRequest()
				request.predicate = NSPredicate(format: "authKey != NIL")
				let results = try context.fetch(request) as! [LoggedInKrakenUser]
				self.credentialedUsers = NSMutableSet(array: results)
				if let activeUsername = Settings.shared.activeUsername, 
						let activeUser = results.first(where: { $0.username == activeUsername }) {
					self.setActiveUser(to: activeUser)
				}
				else if self.credentialedUsers.count == 1, let onlyUser = self.credentialedUsers.anyObject() as? LoggedInKrakenUser {
					self.setActiveUser(to: onlyUser)
				}
			}
			catch {
				CoreDataLog.error("Failure fetching logged in users.", ["Error" : error])
			}
		}
	}
}


// MARK: - Twitarr V2 API Structs

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

// MARK: - Twitarr V3 API Structs

// POST /api/v3/user/create 
struct TwitarrV3CreateAccountRequest: Codable {
	let username: String
	let password: String
    /// Optional verification code. If set, must be a valid code. On success, user will be created with .verified access level, consuming this code. See `/api/v3/user/verify`
    var verification: String?
}

struct TwitarrV3CreateAccountResponse: Codable {
	let userID: UUID
	let username: String
	let recoveryKey: String
}

struct TwitarrV3LoginResponse: Codable {
	let userID: UUID
	let token: String
}

// POST /api/v3/user/password - UserPasswordData
struct TwitarrV3ChangePasswordRequest: Codable {
	let password: String					
}

// POST /api/v3/auth/recovery - UserRecoveryData
struct TwitarrV3RecoverPasswordRequest: Codable {
	let username: String
	let recoveryKey: String						// Password OR registration key OR recovery key
}

// POST /api/v3/auth/recovery - TokenStringData
struct TwitarrV3RecoverPasswordResponse: Codable {
	let token: String
}

// GET /api/v3/user/profile
struct TwitarrV3UserProfileData: Codable {
    /// The user's username. [not editable here]
    let username: String
    /// An optional blurb about the user.
    var about: String?
    /// An optional name for display alongside the username.
    var displayName: String?
    /// An optional email address.
    var email: String?
    /// An optional home location (e.g. city).
    var homeLocation: String?
    /// An optional greeting/message to visitors of the profile.
    var message: String?
    /// An optional preferred form of address.
    var preferredPronoun: String?
    /// An optional real name of the user.
    var realName: String?
    /// An optional ship cabin number.
    var roomNumber: String?
    /// Whether display of the optional fields' data should be limited to logged in users.
    var limitAccess: Bool
}
