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

	// Specific to the logged-in user
	@NSManaged public var commentsAndStars: [CommentsAndStars]?
	@NSManaged public var lastLogin: Bool
	
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
//		TestAndUpdate(\.lastLogin, v2Object.lastLogin)
//		TestAndUpdate(\.emptyPassword, v2Object.emptyPassword)
	}
}

@objc(CommentsAndStars) public class CommentsAndStars : KrakenManagedObject {
	@NSManaged public var comment: String?
	@NSManaged public var isStarred: Bool
	@NSManaged public var commentingUser: KrakenUser
	@NSManaged public var commentedOnUser: KrakenUser

	func build(context: NSManagedObjectContext, userCommentedOn: KrakenUser, loggedInUser: KrakenUser, comment: String?, isStarred: Bool?) {
		TestAndUpdate(\.comment, comment)
		if let isStarred = isStarred {
			TestAndUpdate(\.isStarred, isStarred)
		}
		if commentingUser.username != loggedInUser.username  {
			commentingUser = loggedInUser
		}
		if commentedOnUser.username != userCommentedOn.username {
			commentedOnUser = userCommentedOn
		}
	}
}

// There is at most 1 current logged-in user at a time. That user is specified by CurrentUser.shared.loggedInUser.
@objc class CurrentUser: NSObject {
	static let shared = CurrentUser()
	
	enum UserRole: String {
		case admin
		case tho
		case moderator
		case user
		case muted
		case banned
		case loggedOut
	}
	
	@objc dynamic var loggedInUser: LoggedInKrakenUser?
	var twitarrV2AuthKey: String?
	@objc dynamic var isChangingLoginState: Bool = false
	
	// Info about the current user that should not be in KrakenUser nor cached to disk.
	var lastLogin: Int = 0
	var userRole: UserRole = .loggedOut
	
	// The last error we got from the server. Cleared when we start a new call.
	@objc dynamic var lastError : ServerError?
		
	func clearErrors() {
		lastError = nil
	}

	func isLoggedIn() -> Bool {
		return loggedInUser != nil
	}
	
	func loginUser(name: String, password: String) {
		// For lots of reasons, logging in doesn't do anything immediately, nor does it return a value.
		guard !isChangingLoginState else {
			return
		}
		isChangingLoginState = true
		clearErrors()
		
		// Build our auth call's POST data -- Docs say to do it this way for POST, but no.
		// For POST, you make a HTTP Body request that contains key=value&key=value syntax, like URL params.
//		let authStruct = TwitarrV2AuthRequestBody(username: name, password: password)
//		let encoder = JSONEncoder()
//		let authData = try! encoder.encode(authStruct)
//		print (String(decoding:authData, as: UTF8.self))
		
		let authQuery = "username=\(name)&password=\(password)".data(using: .utf8)!
		
		// Call /api/v2/user/auth, and then call whoami
		var request = NetworkGovernor.buildTwittarV2Request(withPath:"/api/v2/user/auth", query: nil)
		request.httpMethod = "POST"
		request.httpBody = authQuery
		NetworkGovernor.shared.queue(request) { (data: Data?, response: URLResponse?) in
			if let error = NetworkGovernor.shared.parseServerError(data: data, response: response) {
				// Login failed.
				self.lastError = error
				self.isChangingLoginState = false
			}
			else if let data = data {
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
		
		// Need an auth key or this won't work.
		guard let key = keyToUseDuringLogin ?? self.twitarrV2AuthKey else {
			return
		}
		
		let queryParams = [ URLQueryItem(name:"key", value:key) ]
		let request = NetworkGovernor.buildTwittarV2Request(withPath:"/api/v2/user/profile", query: queryParams)
		NetworkGovernor.shared.queue(request) { (data: Data?, response: URLResponse?) in
			if let error = NetworkGovernor.shared.parseServerError(data: data, response: response) {
				// HTTP 401 error at this point means the user isn't actually logged in. This can happen if they
				// change their password from another device.
				self.logoutUser()
				self.lastError = error
			}
			else if response == nil {
				// No response object indicates a network error of some sort (NOT a server error)
			}
			else {
				let decoder = JSONDecoder()
				if let data = data,  let profileResponse = try? decoder.decode(TwitarrV2CurrentUserProfileResponse.self, from: data) {
					
					// Adds the user to the cache if it doesn't exist.
					let krakenUser = UserManager.shared.updateAccount(from: profileResponse)
										
					// If this is a login action, set the logged in user, their key, and other values 
					if let keyUsedForLogin = keyToUseDuringLogin {
						self.loggedInUser = krakenUser
						self.lastLogin = profileResponse.userAccount.lastLogin
						self.twitarrV2AuthKey = keyUsedForLogin
						self.userRole = UserRole(rawValue: profileResponse.userAccount.role) ?? .user
						self.saveLoginCredentials()
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
	
	func logoutUser() {
		// Only allow one login state change action at a time
		guard !isChangingLoginState else {
			return
		}
		isChangingLoginState = true
		clearErrors()
		
		// We send a logout request, but don't care about its result
		let request = NetworkGovernor.buildTwittarV2Request(withPath:"/api/v2/user/logout")
		NetworkGovernor.shared.queue(request) { (data: Data?, response: URLResponse?) in
			let _ = NetworkGovernor.shared.parseServerError(data: data, response: response)
		}
		
		// Throw away all login info
		self.loggedInUser = nil
		self.lastLogin = 0
		self.twitarrV2AuthKey = nil
		self.userRole = .loggedOut
		let cookiesToDelete = HTTPCookieStorage.shared.cookies?.filter { $0.name == "_twitarr_session" }
		for cookie in cookiesToDelete ?? [] {
			HTTPCookieStorage.shared.deleteCookie(cookie)
		}
		removeLoginCredentials()
		
		// Todo: Tell Seamail and Forums to reap for logout
		
		isChangingLoginState = false
	}
	
	func createNewAccount(name: String, password: String, displayName: String?, regCode: String) {
		guard !isChangingLoginState, !isLoggedIn() else {
			return
		}
		isChangingLoginState = true
		clearErrors()
		
		let authStruct = TwitarrV2CreateAccountRequest(username: name, password: password, displayName: displayName, regCode: regCode)
		let encoder = JSONEncoder()
		let authData = try! encoder.encode(authStruct)
		print (String(decoding:authData, as: UTF8.self))
				
		// Call /api/v2/user/new, and then call whoami
		var request = NetworkGovernor.buildTwittarV2Request(withPath:"/api/v2/user/new", query: nil)
		request.httpMethod = "POST"
		request.httpBody = authData
		NetworkGovernor.shared.queue(request) { (data: Data?, response: URLResponse?) in
			if let error = NetworkGovernor.shared.parseServerError(data: data, response: response) {
				// CreateUserAccount failed.
				self.lastError = error
				self.isChangingLoginState = false
			}
			else {
				let decoder = JSONDecoder()
				if let data = data, let authResponse = try? decoder.decode(TwitarrV2CreateAccountResponse.self, from: data),
						authResponse.status == "ok" {
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
		NetworkGovernor.shared.queue(request) { (data: Data?, response: URLResponse?) in
			if let error = NetworkGovernor.shared.parseServerError(data: data, response: response) {
				self.lastError = error
			}
			else {
				let decoder = JSONDecoder()
				if  let data = data, let response = try? decoder.decode(TwitarrV2ChangePasswordResponse.self, from: data),
						response.status == "ok" && savedCurrentUserName == self.loggedInUser?.username {
					self.twitarrV2AuthKey = response.key
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
				
		// Call /api/v2/user/change_password
		var request = NetworkGovernor.buildTwittarV2Request(withPath:"/api/v2/user/reset_password", query: nil)
		request.httpMethod = "POST"
		request.httpBody = authData
		NetworkGovernor.shared.queue(request) { (data: Data?, response: URLResponse?) in
			if let error = NetworkGovernor.shared.parseServerError(data: data, response: response) {
				self.lastError = error
			}
			else {
				let decoder = JSONDecoder()
				if  let data = data, let response = try? decoder.decode(TwitarrV2ResetPasswordResponse.self, from: data) {
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
	
	// This lets the logged in user set a private comment about another user.
	func setUserComment(_ comment: String, forUser: KrakenUser, done: @escaping () -> Void) {
		guard isLoggedIn() else { return }
		clearErrors()
		
		let userCommentStruct = TwitarrV2UserCommentRequest(comment: comment)
		let encoder = JSONEncoder()
		let requestData = try! encoder.encode(userCommentStruct)
				
		// Call /api/v2/user/change_password
		var request = NetworkGovernor.buildTwittarV2Request(withPath:"/api/v2/user/profile/\(forUser.username)/personal_comment", query: nil)
		request.httpMethod = "POST"
		request.httpBody = requestData
		NetworkGovernor.shared.queue(request) { (data: Data?, response: URLResponse?) in
			if let error = NetworkGovernor.shared.parseServerError(data: data, response: response) {
				self.lastError = error
			}
			else {
				let decoder = JSONDecoder()
				if let data = data, let response = try? decoder.decode(TwitarrV2UserCommentResponse.self, from: data) {
					if response.status == "ok" {
						UserManager.shared.updateProfile(for: forUser.objectID, from: response.user)
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
}

/* Secure storage of user auth data.

	We save a single item into KeychainServices. That item is a small JSON struct containing both the username and the 
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
 		guard let user = loggedInUser, let authKey = twitarrV2AuthKey, 
 				let keyData = authKey.data(using:.utf8, allowLossyConversion: false) else { return false }
 				
		removeLoginCredentials()
 		
 		let keychainObjectKey: String = Settings.shared.baseURL.absoluteString
		let query: [String : Any] = [
				kSecClass as String: kSecClassInternetPassword as String,
				kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
				kSecAttrAccount as String: user.username,
				kSecAttrServer as String: keychainObjectKey,
				kSecAttrSecurityDomain as String: self.userRole.rawValue,	// Heh. Not what SecurityDomain is actually for.
				kSecValueData as String: keyData as NSData]

		let status: OSStatus = SecItemAdd(query as CFDictionary, nil)
		return status == noErr
	}
	
	func removeLoginCredentials() {
 		let keychainObjectKey: String = Settings.shared.baseURL.absoluteString
		let query: [String : Any] = [
				kSecClass as String: kSecClassInternetPassword as String,
				kSecAttrServer as String: keychainObjectKey,
				kSecReturnData as String: true]

        // Delete any existing items, for all accounts on this server.
        let status = SecItemDelete(query as CFDictionary)
        if (status != errSecSuccess && status != errSecItemNotFound) {
			print("Remove failed: \(status)")
        }

	}

	// Called early on during app launch.
	func setInitialLoginState() {
 		let keychainObjectKey: String = Settings.shared.baseURL.absoluteString
		let query: [String : Any] = [
				kSecClass as String : kSecClassInternetPassword,
				kSecAttrServer as String : keychainObjectKey,
				kSecReturnAttributes as String : true,
				kSecReturnData as String : true,
				kSecMatchLimit as String : kSecMatchLimitOne]

		var dataTypeRef: AnyObject?
		let status: OSStatus = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
		if status == errSecSuccess, let recordDict = dataTypeRef as? [String : Any],
   				let accountName = recordDict[kSecAttrAccount as String] as? String,
				let passwordData = recordDict[kSecValueData as String] as? Data,
    			let authKey = String(data: passwordData, encoding: String.Encoding.utf8),
    			let userRoleStr = recordDict[kSecAttrSecurityDomain as String] as? String {
    			
			//
			let krakenUser = UserManager.shared.user(accountName) as? LoggedInKrakenUser
	
			// 
			self.loggedInUser = krakenUser
			self.lastLogin = 0
			self.twitarrV2AuthKey = authKey
			self.userRole = UserRole(rawValue: userRoleStr) ?? .user

			loadProfileInfo()
		}
		else if status == errSecItemNotFound {	// errSecItemNotFound is -25300
			// No record found; this is fine. Means we're not logging in as anyone at app launch.
		}
		else {
			print("Failure loading keychain info.")
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

// /api/v2/user/profile/:username/personal_comment
struct TwitarrV2UserCommentRequest: Codable {
	let comment: String
}

struct TwitarrV2UserCommentResponse: Codable {
	let status: String
	let user: TwitarrV2UserProfile
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
	let lastLogin: Int
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
