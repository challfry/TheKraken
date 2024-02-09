//
//  AlertsUpdater.swift
//  Kraken
//
//  Created by Chall Fry on 1/15/20.
//  Copyright © 2020 Chall Fry. All rights reserved.
//

import UIKit

class AlertsUpdater: ServerUpdater {
	static let shared = AlertsUpdater()
	
	var lastError: ServerError?
	
	init() {
		// Update every minute.
		super.init(60)
		refreshOnLogin = true
	}
	
	override func updateMethod() {
		callAlertsEndpoint()
	}
		
	func callAlertsEndpoint() {
		var request = NetworkGovernor.buildTwittarRequest(withPath:"/api/v3/notification/global")
		NetworkGovernor.addUserCredential(to: &request)
		let currentUser = CurrentUser.shared.loggedInUser
		NetworkGovernor.shared.queue(request) { (package: NetworkResponse) in
			if let error = package.serverError {
				self.lastError = error
				self.updateComplete(success: false)
			}
			else if let data = package.data {
				do {
					self.lastError = nil
					let response = try Settings.v3Decoder.decode(TwitarrV3UserNotificationData.self, from: data)
					self.parseAlertsResponse(response, currentUser)
					self.updateComplete(success: true)
				}
				catch {
					NetworkLog.error("Failure parsing Alerts response.", ["Error" : error, "url" : request.url as Any])
					self.updateComplete(success: false)
				}
			}
			else {
				// Network error
				self.updateComplete(success: false)
			}
		}
	}
	
	func parseAlertsResponse(_ response: TwitarrV3UserNotificationData, _ currentUser: LoggedInKrakenUser?) {
		// Server Time
		ServerTime.shared.updateServerTime(response)
		
		// Disabled Features
		ValidSections.shared.updateDisabledFeatures(disabled: response.disabledFeatures)
		
		// Wifi network
		Settings.shared.onboardWifiNetowrkName = response.shipWifiSSID ?? ""
	
		// Announcements
		let actives = response.activeAnnouncementIDs.map { Int64($0) }
		AnnouncementDataManager.shared.updateAnnouncementCounts(activeIDs: actives, unseenCount: Int64(response.newAnnouncementCount))

		if let currentUser = currentUser {
			// Tweet Mentions, Forum Mentions, new LFG and Seamail msgs
			LocalCoreData.shared.performNetworkParsing { context in
				let userInContext = context.object(with: currentUser.objectID) as! LoggedInKrakenUser
				userInContext.buildFromV3NotificationInfo(context: context, notification: response)				
			}
		}
// Only valid if logged in

		// Tweet Mentions
		// Forum Mentions
		// Seamail Msgs
		// Fez Msgs?
		// Events?
		// AlertWords
		
		
		// Tweets
//		if let twitarrPosts = response.tweetMentions, twitarrPosts.count > 0 {
//			TwitarrDataManager.shared.ingestFilterPosts(posts: twitarrPosts)
	//	}
		
		// Forum Threads
//		if let forumThreads = response.forumMentions, forumThreads.count > 0 {
//			ForumsDataManager.shared.ingestForumThreads(from: forumThreads)
//		}
		
		// Unread Seamails
//		if let unreadSeamails = response.unreadSeamail, unreadSeamails.count > 0 {
//			SeamailDataManager.shared.ingestSeamailThreads(from: unreadSeamails)
//		}
		
		// Events? Are we doing events this way?
		
		LocalCoreData.shared.performNetworkParsing { context in
			if let currentUser = CurrentUser.shared.getLoggedInUser(in: context) {
				currentUser.lastAlertCheckTime = Date()
			}
		}
	}
	
	
}

// MARK: V3 API Decoding

public struct TwitarrV3UserNotificationData: Codable {
	/// Always an ISO 8601 date in UTC, like "2020-03-07T12:00:00Z"
	var serverTime: String
	/// Server Time Zone offset, in seconds from UTC. One hour before UTC is -3600. EST  timezone is -18000.
	var serverTimeOffset: Int
	/// Human-readable time zone name, like "EDT"
	var serverTimeZone: String
	/// Features that are turned off by the server. If the `appName` for a feature is `all`, the feature is disabled at the API layer.
	/// For all other appName values, the disable is just a notification that the client should not show the feature to users.
	/// If the list is empty, no features have been deisabled. 
	var disabledFeatures: [TwitarrV3DisabledFeature]
	/// The name of the shipboard Wifi network
	var shipWifiSSID: String?

	/// IDs of all active announcements 
	var activeAnnouncementIDs: [Int]
	
/// All fields below this line will be 0 or null if called when not logged in.
	
	/// Count of announcements the user has not yet seen. 0 if not logged in.
	var newAnnouncementCount: Int
	
	/// Number of twarrts that @mention the user. 0 if not logged in.
	var twarrtMentionCount: Int
	/// Number of twarrt @mentions that the user has not read (by visiting the twarrt mentions endpoint; reading twarrts in the regular feed doesn't count). 0 if not logged in.
	var newTwarrtMentionCount: Int
	
	/// Number of forum posts that @mention the user. 0 if not logged in.
	var forumMentionCount: Int
	/// Number of forum post @mentions the user has not read. 0 if not logged in.
	var newForumMentionCount: Int
	
	/// Count of # of Seamail threads with new messages. NOT total # of new messages-a single seamail thread with 10 new messages counts as 1. 0 if not logged in.
	var newSeamailMessageCount: Int
	/// Count of # of Fezzes with new messages. 0 if not logged in.
	var newFezMessageCount: Int
	
	/// The start time of the earliest event that the user has followed with a start time > now. nil if not logged in.
	var nextFollowedEventTime: Date?
	
	/// For each alertword the user has, this returns data on hit counts for that word.
	var alertWords: [TwitarrV3UserNotificationAlertwordData]
	
	/// Notification counts that are only relevant for Moderators (and TwitarrTeam).
	public struct ModeratorNotificationData: Codable {
		/// The total number of open user reports. Does not count in-process reports (reports being 'handled' by a mod already). 
		/// This value counts multiple reports on the same piece of content as separate reports. 
		var openReportCount: Int
		
		/// The number of Seamails to @moderator (more precisely, ones where @moderator is a participant) that have new messages.
		/// This value is very similar to `newSeamailMessageCount`, but for any moderator it gives the number of new seamails for @moderator.
		var newModeratorSeamailMessageCount: Int

		/// The number of Seamails to @TwitarrTeam. Nil if user isn't a member of TwitarrTeam. This is in the Moderator struct because I didn't 
		/// want to make *another* sub-struct for TwitarrTeam, just to hold one value.
		var newTTSeamailMessageCount: Int?
	}
	
	/// Will be nil for non-moderator accounts.
	var moderatorData: ModeratorNotificationData?
}

public struct TwitarrV3DisabledFeature: Codable {
	/// AppName and featureName act as a grid, allowing a specific feature to be disabled only in a specific app. If the appName is `all`, the server
	/// code for the feature may be causing the issue, requiring the feature be disabled for all clients.
	var appName: TwitarrV3SwiftarrClientApp
	/// The feature to disable. Features roughly match API controller groups. 
	var featureName: TwitarrV3SwiftarrFeature
}

public struct TwitarrV3UserNotificationAlertwordData: Codable {
	/// Will be one of the user's current alert keywords.
	var alertword: String
	/// The total number of twarrts that include this word since the first time anyone added this alertword. We record alert word hits in
	/// a single global list that unions all users' alert word lists. A search for this alertword may return more hits than this number indicates.
	var twarrtMentionCount: Int
	/// The number of twarrts that include this alertword that the user has not yet seen. Calls to view twarrts with a "?search=" parameter that matches the 
	/// alertword will mark all twarrts containing this alertword as viewed. 
	var newTwarrtMentionCount: Int
	/// The total number of forum posts that include this word since the first time anyone added this alertword.
	var forumMentionCount: Int
	/// The number of forum posts that include this alertword that the user has not yet seen.
	var newForumMentionCount: Int
}

public enum TwitarrV3SwiftarrClientApp: String, Codable, CaseIterable {
	/// The website, but NOT the API layer
	case swiftarr
	
	/// Client apps that consume the Swiftarr API					
	case cruisemonkey
	case rainbowmonkey
	case kraken

	/// A feature disabled for `all` will be turned off at the API layer , meaning that calls to that area of the API will return errors. Clients should still attempt
	/// to use disabledFeatures to indicate the cause, rather than just displaying HTTP status errors.
	case all
	
	/// For clients use. Clients need to be prepared for additional values to be added serverside. Those new values get decoded as 'unknown'.
	case unknown
	
	/// When creating ourselves from a decoder, return .unknown for cases we're not prepared to handle.
	public init(from decoder: Decoder) throws {
		guard let rawValue = try? decoder.singleValueContainer().decode(String.self) else {
			self = .unknown
			return
		}
		self = .init(rawValue: rawValue) ?? .unknown
	}
}

public enum TwitarrV3SwiftarrFeature: String, Codable, CaseIterable {
	case tweets
	case forums
	case seamail
	case schedule
	case friendlyfez
	case karaoke
	case microkaraoke
	case gameslist
	case images
	case users
	case phone
	case directphone
	case all
	
	/// For clients use. Clients need to be prepared for additional values to be added serverside. Those new values get decoded as 'unknown'.
	case unknown
	
	/// When creating ourselves from a decoder, return .unknown for cases we're not prepared to handle.
	public init(from decoder: Decoder) throws {
		guard let rawValue = try? decoder.singleValueContainer().decode(String.self) else {
			self = .unknown
			return
		}
		self = .init(rawValue: rawValue) ?? .unknown
	}
}
