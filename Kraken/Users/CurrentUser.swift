//
//  CurrentUser.swift
//  Kraken
//
//  Created by Chall Fry on 3/22/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import Foundation
import CoreData

class LoggedInKrakenUser: KrakenUser {

	// Specific to the logged-in user
	@NSManaged public var commentsAndStars: [CommentsAndStars]?
	
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
class CurrentUser: NSObject {
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
	
	var loggedInUser: LoggedInKrakenUser?
	var twitarrV2AuthKey: String?
	var isChangingLoginState: Bool = false
	
	// Info about the current user that should not be in KrakenUser nor cached to disk.
	var lastLogin: Int = 0
	var userRole: UserRole = .loggedOut
	
	// The last error we got from the server. Cleared when we start a new call.
	var lastError : Error?
	struct CurrentUserError: Error {
		let httpStatus: Int
		let errorString: String
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
		
		// Build our auth call's POST data -- Docs say to do it this way for POST, but no.
		// For POST, you make a HTTP Body request that contains key=value&key=value syntax, like URL params.
//		let authStruct = TwitarrV2AuthRequestBody(username: name, password: password)
//		let encoder = JSONEncoder()
//		let authData = try! encoder.encode(authStruct)
//		print (String(decoding:authData, as: UTF8.self))
		
		let authQuery = "username=james&password=james".data(using: .utf8)!
		
		// Call /api/v2/user/auth, and then call whoami
		var request = NetworkGovernor.buildTwittarV2Request(withPath:"/api/v2/user/auth", query: nil)
		request.httpMethod = "POST"
		request.httpBody = authQuery
		NetworkGovernor.shared.queue(request) { (data: Data?, response: URLResponse?) in
			if !self.handledNetworkError(data: data, response: response),
					let data = data {
				let decoder = JSONDecoder()
				if let authResponse = try? decoder.decode(TwitarrV2AuthResponse.self, from: data) {
					self.loadProfileInfo(keyToUseDuringLogin: authResponse.key)
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
			if !self.handledNetworkError(data: data, response: response),
					let data = data {
				let decoder = JSONDecoder()
				if let profileResponse = try? decoder.decode(TwitarrV2ProfileResponse.self, from: data) {
					
					// Adds the user to the cache if it doesn't exist.
//					let krakenUser = UserManager.shared.updateUser(profileResponse.userAccount.username,
//							displayName: profileResponse.userAccount.displayName, 
//							lastPhotoUpdated: profileResponse.userAccount.lastPhotoUpdated)
//					
//					// KrakenUser is separate from TwitarrV2UserAccount for a very good reason!
//					krakenUser.emailAddress = profileResponse.userAccount.email
//					krakenUser.currentLocation = profileResponse.userAccount.currentLocation
//					krakenUser.roomNumber = profileResponse.userAccount.roomNumber
//					krakenUser.realName = profileResponse.userAccount.realName
//					krakenUser.pronouns = profileResponse.userAccount.pronouns
//					krakenUser.homeLocation = profileResponse.userAccount.homeLocation
//					
					// If this is a login action, set the logged in user, their key, and other values 
					if let keyUsedForLogin = keyToUseDuringLogin {
//						self.loggedInUser = krakenUser
						self.lastLogin = profileResponse.userAccount.lastLogin
						self.twitarrV2AuthKey = keyUsedForLogin
						
						self.userRole = UserRole(rawValue: profileResponse.userAccount.role) ?? .user
					}
				}
			}
			else if keyToUseDuringLogin != nil {
				// Login failed.
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
		
		// We send a logout request, but don't care about its result
		let request = NetworkGovernor.buildTwittarV2Request(withPath:"/api/v2/user/logout")
		NetworkGovernor.shared.queue(request) { (data: Data?, response: URLResponse?) in
			self.handledNetworkError(data: data, response: response) 
		}
		
		// Throw away all login info
		self.loggedInUser = nil
		self.lastLogin = 0
		self.twitarrV2AuthKey = nil
		self.userRole = .loggedOut
		
		// Todo: Tell Seamail and Forums to reap for logout
		
		isChangingLoginState = false
	}
	
	func createUser(name: String, password: String, displayName: String?, regCode: String) {
		
	}
	
	func setUserComment(_ comment: String, forUser: KrakenUser) {
		if let currentUser = loggedInUser {
			
		}
	}
	
	// Returns TRUE if a network error occurred.
	@discardableResult private func handledNetworkError(data: Data?, response: URLResponse?) -> Bool {
		var result = true
		if let response = response as? HTTPURLResponse {
			if response.statusCode >= 300 {
				self.lastError = nil
				if let data = data {
					print (String(decoding:data, as: UTF8.self))
					let decoder = JSONDecoder()
					if let errorInfo = try? decoder.decode(TwitarrV2ErrorResponse.self, from: data) {
						
						// todo: add support for errors (the multiple error array)
					
						self.lastError = CurrentUserError(httpStatus: response.statusCode, 
								errorString: errorInfo.error ?? "Unknown error")
					}
				}
				
				if self.lastError == nil {
					self.lastError = CurrentUserError(httpStatus: response.statusCode, 
							errorString: "HTTP error \(response.statusCode).")
				}
			}
			else {
				result = false
			}
		}
		
		return result
	}
	
}


struct TwitarrV2AuthRequestBody: Codable {
	let username: String
	let password: String
}

struct TwitarrV2ErrorResponse: Codable {
	let status: String
	let error: String?
	let errors: [String]?
}

struct TwitarrV2AuthResponse: Codable {
	let status: String
	let username: String
	let key: String
}

struct TwitarrV2ProfileResponse: Codable {
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
	let email: String?
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
		case username, role, email, pronouns
		case displayName = "display_name"
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
