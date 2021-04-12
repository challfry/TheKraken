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
		if let currentUser = CurrentUser.shared.loggedInUser {
		
			// 
			var request = NetworkGovernor.buildTwittarRequest(withPath:"/api/v2/alerts/last_checked", query: nil)
			NetworkGovernor.addUserCredential(to: &request)
			let lastCheckTime = currentUser.lastAlertCheckTime
			let lastCheckedData = TwitarrV2AlertsLastCheckedChangeRequest(last_checked_time: lastCheckTime)
			let postData = try! JSONEncoder().encode(lastCheckedData)
			request.httpMethod = "POST"
			request.httpBody = postData
			request.setValue("application/json", forHTTPHeaderField: "Content-Type")

			NetworkGovernor.shared.queue(request) { (package: NetworkResponse) in
				if let error = NetworkGovernor.shared.parseServerError(package) {
					self.lastError = error
					self.updateComplete(success: false)
				}
				else if let data = package.data {
					let response = try? JSONDecoder().decode(TwitarrV2AlertsLastCheckedChangeResponse.self, from: data)
					if response == nil {
						NetworkLog.error("Failure parsing AlertsLastChecked response.")
					}
				}			
				self.callAlertsEndpoint()
			}
		}
		else {
			callAlertsEndpoint()
		}
	}
	
	func callAlertsEndpoint() {
	
		let queryParams: [URLQueryItem] = []
//		queryParams.append(URLQueryItem(name:"no_reset", value: "true"))		
		var request = NetworkGovernor.buildTwittarRequest(withPath:"/api/v2/alerts", query: queryParams)
		NetworkGovernor.addUserCredential(to: &request)

		NetworkGovernor.shared.queue(request) { (package: NetworkResponse) in
			if let error = NetworkGovernor.shared.parseServerError(package) {
				self.lastError = error
				self.updateComplete(success: false)
			}
			else if let data = package.data {
				do {
					self.lastError = nil
					let response = try JSONDecoder().decode(TwitarrV2AlertsResponse.self, from: data)
					self.parseAlertsResponse(response)
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
	
	func parseAlertsResponse(_ response: TwitarrV2AlertsResponse) {
	
		// Announcements
		if response.announcements.count > 0 {
			AnnouncementDataManager.shared.ingestAnnouncements(from: response.announcements)
		}
		
		// Tweets
		if let twitarrPosts = response.tweetMentions, twitarrPosts.count > 0 {
			TwitarrDataManager.shared.ingestFilterPosts(posts: twitarrPosts)
		}
		
		// Forum Threads
		if let forumThreads = response.forumMentions, forumThreads.count > 0 {
//			ForumsDataManager.shared.ingestForumThreads(from: forumThreads)
		}
		
		// Unread Seamails
		if let unreadSeamails = response.unreadSeamail, unreadSeamails.count > 0 {
//			SeamailDataManager.shared.ingestSeamailThreads(from: unreadSeamails)
		}
		
		// Events? Are we doing events this way?
		
		LocalCoreData.shared.performNetworkParsing { context in
			if let currentUser = CurrentUser.shared.getLoggedInUser(in: context) {
				currentUser.lastAlertCheckTime = response.queryTime
			}
		}
	}
	
}

// MARK: - V2 API Decoding

// GET /api/v2/alerts
struct TwitarrV2AlertsResponse: Codable {
	let status: String
	let announcements: [TwitarrV2Announcement]
	let tweetMentions: [TwitarrV2Post]?
	let forumMentions: [TwitarrV2ForumThreadMeta]?
	let unreadSeamail: [TwitarrV2SeamailThread]?
	let upcomingEvents: [TwitarrV2Event]?
	let lastCheckedTime: Int64
	let queryTime: Int64
	
	enum CodingKeys: String, CodingKey {
		case status, announcements
		case tweetMentions = "tweet_mentions"
		case forumMentions = "forum_mentions"
		case unreadSeamail = "unread_seamail"
		case upcomingEvents = "upcoming_events"
		case lastCheckedTime = "last_checked_time"
		case queryTime = "query_time"
	}
}

// POST /api/v2/alerts/last_checked
struct TwitarrV2AlertsLastCheckedChangeRequest: Codable {
	let last_checked_time: Int64
}

struct TwitarrV2AlertsLastCheckedChangeResponse: Codable {
	let status: String
	let last_checked_time: Int64
}

