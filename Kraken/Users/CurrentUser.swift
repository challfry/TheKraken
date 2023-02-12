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

	@objc enum AccessLevel: Int32 {
		case unverified
		case banned
		case quarantined
		case verified
		case client
		case moderator
		case tho
		case admin
		
		// Done this dumb way because we need to be @objc, therefore Int-backed, not string-backed.
		static func roleForString(str: String) -> AccessLevel? {
			switch str {
			case "admin": return .admin
			case "tho": return .tho
			case "moderator": return .moderator
			case "client": return .client
			case "verified": return .verified
			case "quarantined": return .quarantined
			case "banned": return .banned
			case "unverified": return .unverified
			default: return nil
			}
		}
		static func stringForRole(role: AccessLevel) -> String {
			switch role {
			case .admin: return "admin"
			case .tho: return "tho"
			case .moderator: return "moderator"
			case .client: return "client"
			case .verified: return "verified"
			case .quarantined: return "quarantined"
			case .banned: return "banned"
			case .unverified: return "unverified"
			}
		}
	}
	
	// Specific to the logged-in user
	@NSManaged public var postOps: Set<PostOperation>?
	
	// new tweet mentions and new forum mentions. We may not actually have the underlying data loaded.
	@NSManaged public var tweetMentions: Int32
	@NSManaged public var forumMentions: Int32
	@NSManaged public var newSeamailMessages: Int32		// # of msg threads with new seamail messages.
	@NSManaged public var newLFGMessages: Int32			// # of joined LFGs with new messages.
	

	@NSManaged public var userComments: Set<UserComment>?			// This set is comments the logged in user has made about *others*
	@NSManaged public var favoriteUsers: Set<KrakenUser>			// Set of users the logged in user has favorited.
	@NSManaged public var mutedUsers: Set<KrakenUser>				// Set of users the logged in user has muted.
	@NSManaged public var blockedUsers: Set<KrakenUser>				// Set of users the logged in user has chosen to block -- does not
																	// include incoming blocks from others! 
	@NSManaged public var lastLogin: Int64
	@NSManaged public var lastAlertCheckTime: Date
	@NSManaged public var lastSeamailCheckTime: Int64
	
	// V3 token as returned by /api/v3/auth/login 
	@NSManaged public var authKey: String?
	
	// Alerts
	@NSManaged public var upToDateSeamailThreads: Set<SeamailThread>

	// Info about the current user that should not be in KrakenUser.
	@NSManaged var accessLevel: AccessLevel
	
// MARK: Model Builders
	func buildFromV3TokenStringInfo(context: NSManagedObjectContext, v3Object: TwitarrV3TokenStringData, username: String) {
		TestAndUpdate(\.username, username)
		TestAndUpdate(\.userID, v3Object.userID)
		TestAndUpdate(\.authKey, v3Object.token)
		TestAndUpdate(\.accessLevel, AccessLevel.roleForString(str: v3Object.accessLevel.rawValue) ?? .unverified)
	}
	
	func buildFromV3NotificationInfo(context: NSManagedObjectContext, notification: TwitarrV3UserNotificationData) {
		TestAndUpdate(\.tweetMentions, Int32(notification.newTwarrtMentionCount))
		TestAndUpdate(\.forumMentions, Int32(notification.newForumMentionCount))
		TestAndUpdate(\.newSeamailMessages, Int32(notification.newSeamailMessageCount))
		TestAndUpdate(\.newLFGMessages, Int32(notification.newFezMessageCount))
	}
	
	// Assumes targets is a comprehensive current list of all users with the given relation--Removes relation for any
	// users not in the targets list.
	func buildFromV3RelationInfo(context: NSManagedObjectContext, type: UserRelationType, targets: [TwitarrV3UserHeader]) {
		let dict = UserManager.shared.update(users: targets, inContext: context, includeCurrentUser: false)
		switch type {
			case .favorite: favoriteUsers = Set(dict.values)
			case .mute: mutedUsers = Set(dict.values)
			case .block: blockedUsers = Set(dict.values)
		}
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
	
	func getPendingUserRelationOp(type: UserRelationType, forUser: KrakenUser, inContext: NSManagedObjectContext) -> PostOpUserRelation? {
		if let ops = postOps {
			for op in ops {
				if let relationOp = op as? PostOpUserRelation, relationOp.relationType == type, let targetUser = relationOp.targetUser,
						targetUser.userID == forUser.userID {
					let opInContext = try? inContext.existingObject(with: relationOp.objectID) as? PostOpUserRelation
					return opInContext
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

@objc public enum UserRelationType: Int32 {
	case favorite
	case mute
	case block
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
		let loginAPIPath = "/api/v3/auth/login"
		var request = NetworkGovernor.buildTwittarRequest(withPath: loginAPIPath, query: nil)
		request.httpMethod = "POST"
		let credentials = "\(name):\(password)".data(using: .utf8)!.base64EncodedString()
		request.addValue("Basic \(credentials)", forHTTPHeaderField: "Authorization")
		
		NetworkGovernor.shared.queue(request) { package in
			if let error: Error = (package.serverError ?? package.networkError) {
				// Login failed.
				self.lastError = error
			}
			else if let data = package.data {
				if let loginResponse = try? Settings.v3Decoder.decode(TwitarrV3TokenStringData.self, from: data) {
					self.loginSuccess(username: name, tokenResponse: loginResponse)
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
	func loginSuccess(username: String, tokenResponse: TwitarrV3TokenStringData) {
		LocalCoreData.shared.performNetworkParsing { context in
			context.pushOpErrorExplanation("Failure adding logged in user to Core Data.")
			let krakenUser: LoggedInKrakenUser = (UserManager.shared.user(username, inContext: context) as? LoggedInKrakenUser) ??
					LoggedInKrakenUser(context: context)
			krakenUser.buildFromV3TokenStringInfo(context: context, v3Object: tokenResponse, username: username)
			try context.save()
			
			DispatchQueue.main.sync {
				if let user = try? LocalCoreData.shared.mainThreadContext.existingObject(with: krakenUser.objectID)
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
		let profileAPIPath = "/api/v3/user/profile"
		var request = NetworkGovernor.buildTwittarRequest(withPath:profileAPIPath, query: queryParams)
		NetworkGovernor.addUserCredential(to: &request)
		
		NetworkGovernor.shared.queue(request) { package in
			if let error = package.serverError {
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
				if let data = package.data {
					if let profileResponse = try? Settings.v3Decoder.decode (TwitarrV3ProfilePublicData.self, from: data) {
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
	func logoutUser(_ passedInUser: LoggedInKrakenUser? = nil, sendLogoutMsg: Bool = true) {
//		DispatchQueue.main.async {
			// Only allow one login state change action at a time
			guard !isChangingLoginState else { return }
			guard let userToLogout = passedInUser ?? loggedInUser else { return }
			guard credentialedUsers.contains(userToLogout) else { return }
			
			isChangingLoginState = true
			clearErrors()
			
			// If the server tells us we're no longer authenticated, don't send back a logout, as we'll infinite-loop.
			if sendLogoutMsg {
				// We send a logout request, but don't care about its result
				let queryParams: [URLQueryItem] = []
				var request = NetworkGovernor.buildTwittarRequest(withPath:"/api/v3/auth/logout", query: queryParams)
				NetworkGovernor.addUserCredential(to: &request)
				request.httpMethod = "POST"
				NetworkGovernor.shared.queue(request) { package in
					// The only server errors we can get are variants of "That guy wasn't logged in" or "Your token is wrong"
				}
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
		
		let authStruct = TwitarrV3CreateAccountRequest(username: name, password: password, verification: regCode)
		let authData = try! Settings.v3Encoder.encode(authStruct)
	//	print (String(decoding:authData, as: UTF8.self))
				
		// Call the login endpoint
		var request = NetworkGovernor.buildTwittarRequest(withPath: "/api/v3/user/create", query: nil)
		request.httpMethod = "POST"
		request.httpBody = authData
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		NetworkGovernor.shared.queue(request) { (package: NetworkResponse) in
			self.isChangingLoginState = false
			if let error = package.serverError {
				// CreateUserAccount failed.
				self.lastError = error
			}
			else if let error = package.networkError {
				self.lastError = error
			}
			else if let data = package.data, let createAcctResponse = try? Settings.v3Decoder.decode(TwitarrV3CreateAccountResponse.self, 
					from: data) {
					
				// Login the user immediately after account creation
				self.loginUser(name: createAcctResponse.username, password: password)
			}
			else
			{
				self.lastError = ServerError("Couldn't decode server response to createNewAccount request.")
			}
		}
	}
	
	// Must be logged in to change password; resetPassword works while logged out but requires reg code.
	func changeUserPassword(currentPassword: String, newPassword: String, done: @escaping () -> Void) {
		guard !isChangingLoginState else {
			return
		}
		clearErrors()
		let changePasswordStruct = TwitarrV3ChangePasswordRequest(password: newPassword)
		let authData = try! Settings.v3Encoder.encode(changePasswordStruct)

		// Call change_password
		var request = NetworkGovernor.buildTwittarRequest(withPath: "/api/v3/user/password", query: nil)
		request.httpMethod = "POST"
		request.httpBody = authData
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		NetworkGovernor.addUserCredential(to: &request)
		NetworkGovernor.shared.queue(request) { (package: NetworkResponse) in
			if let error = package.serverError {
				self.lastError = error
			}
			else if let response = package.response, response.statusCode == 201 {
				// Success. Resetting a V3 password doesn't change the auth token.
				done()
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
		let resetPasswordStruct = TwitarrV3RecoverPasswordRequest(username: name, recoveryKey: regCode, newPassword: newPassword)
		let authData = try! Settings.v3Encoder.encode(resetPasswordStruct)
				
		// Call reset_password
		var request = NetworkGovernor.buildTwittarRequest(withPath: "/api/v3/auth/recovery", query: nil)
		request.httpMethod = "POST"
		request.httpBody = authData
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		NetworkGovernor.shared.queue(request) { (package: NetworkResponse) in
			if let error = package.serverError {
				self.lastError = error
			}
			else if let data = package.data {
				if let response = try? Settings.v3Decoder.decode(TwitarrV3TokenStringData.self, from: data) {
					// V3 reset returns a login token. Log ourselves in with it and immediately initiate a password change
					// to the user's new password.
					self.loginSuccess(username: name, tokenResponse: response)
					self.changeUserPassword(currentPassword: "", newPassword: newPassword, done: done)
				}
				else {
					self.lastError = ServerError("Unknown error")
				}
			} 
		}
	}
	
// MARK: Move these to LoggedInKrakenUser!!!
			
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
	
// MARK: Favorite, Mute, Block
	// Creates an op to set the indicated relation. Current user is always acting user.
	func setRelation(type: UserRelationType, forUser: KrakenUser, to newState: Bool) {
		guard let loggedInUser = loggedInUser else { return }
		clearErrors()
		
		LocalCoreData.shared.performNetworkParsing { context in
			context.pushOpErrorExplanation("Failure saving User \(type) change to Core Data. (the network call succeeded, but we couldn't save the change).")
					
			// Check for existing op for this user
			let op = loggedInUser.getPendingUserRelationOp(type: type, forUser: forUser, inContext: context) ?? PostOpUserRelation(context: context)
			op.relationType = type
			op.isActive = newState
			op.targetUser = UserManager.shared.user(forUser, inContext: context)
			op.operationState = .readyToSend
		}
	}

	// Called when an op succeeds or the server has otherwise changed the given relation. updates CD.
	func updatedUserRelation(type: UserRelationType, actingUser: KrakenUser, targetUser: KrakenUser, newState: Bool) {
		LocalCoreData.shared.performNetworkParsing { context in
			context.pushOpErrorExplanation("Failure saving User \(type) change to Core Data. (the network call succeeded, but we couldn't save the change).")
			if let authorInContext = context.object(with: actingUser.objectID) as? LoggedInKrakenUser,
					let targetInContext = context.object(with: targetUser.objectID) as? KrakenUser {
				switch (type, newState) {
					case (.favorite, true):  authorInContext.favoriteUsers.insert(targetInContext)
					case (.favorite, false): authorInContext.favoriteUsers.remove(targetInContext)
					case (.mute, true):  authorInContext.mutedUsers.insert(targetInContext)
					case (.mute, false): authorInContext.mutedUsers.remove(targetInContext)
					case (.block, true):  authorInContext.blockedUsers.insert(targetInContext)
					case (.block, false): authorInContext.blockedUsers.remove(targetInContext)
				}
			}
		}
	}
	
	func updateUserRelations(type: UserRelationType, actingUser: KrakenUser? = CurrentUser.shared.loggedInUser) {
		guard let actingUser = actingUser else { return }
		var path: String
		switch type {
			case .favorite: path = "/api/v3/users/favorites"
			case .mute: path = "/api/v3/users/mutes"
			case .block: path = "/api/v3/users/blocks"
		}
		var request = NetworkGovernor.buildTwittarRequest(withEscapedPath: path, query: nil)
		NetworkGovernor.addUserCredential(to: &request)
		NetworkGovernor.shared.queue(request) { (package: NetworkResponse) in
			if let data = package.data {
				do {
					let headers = try Settings.v3Decoder.decode([TwitarrV3UserHeader].self, from: data)
					LocalCoreData.shared.performNetworkParsing { context in
						context.pushOpErrorExplanation("Failure adding user \(type) to Core Data.")
						if let userInContext = UserManager.shared.user(actingUser, inContext: context) as? LoggedInKrakenUser {
							userInContext.buildFromV3RelationInfo(context: context, type: type, targets: headers)
						}
					}
				} catch 
				{
					NetworkLog.error("Failure loading user favorites.", ["Error" : error])
				} 
			}
		}
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

struct TwitarrV3TokenStringData: Codable {
    /// The user ID of the newly logged in user. 
    var userID: UUID
    /// The user's access level.
	var accessLevel: TwitarrV3UserAccessLevel
    /// The token string.
    let token: String

}

// POST /api/v3/user/password - UserPasswordData
struct TwitarrV3ChangePasswordRequest: Codable {
	let password: String					
}

// POST /api/v3/auth/recovery - UserRecoveryData
struct TwitarrV3RecoverPasswordRequest: Codable {
    /// The user's username.
    var username: String
    /// The string to use – any one of: password / registration key / recovery key.
    var recoveryKey: String
    /// The new password to set for the account.
    var newPassword: String
}

public enum TwitarrV3UserAccessLevel: String, Codable {
    /// A user account that has not yet been activated. [read-only, limited]
    case unverified
    /// A user account that has been banned. [cannot log in]
    case banned
    /// A `.verified` user account that has triggered Moderator review. [read-only]
    case quarantined
    /// A user account that has been activated for full read-write access.
    case verified
    /// A special class of account for registered API clients. [see `ClientController`]
    case client
    /// An account whose owner is part of the Moderator Team.
    case moderator
    /// Twitarr devs should have their accounts elevated to this level to help handle seamail to 'twitarrteam'
	case twitarrteam
    /// An account officially associated with Management, has access to all `.moderator`
    /// and a subset of `.admin` functions (the non-destructive ones). Can ban users.
    case tho
    /// An Administrator account, unrestricted access.
    case admin
}
