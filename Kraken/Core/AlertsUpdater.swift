//
//  AlertsUpdater.swift
//  Kraken
//
//  Created by Chall Fry on 1/15/20.
//  Copyright © 2020 Chall Fry. All rights reserved.
//

import UIKit

@objc(Announcement) public class Announcement: KrakenManagedObject {
    @NSManaged public var id: String?
    @NSManaged public var text: String?
    @NSManaged public var displayUntil: Int64
    @NSManaged public var author: KrakenUser?
    
	func buildFromV2(context: NSManagedObjectContext, v2Object: TwitarrV2Announcement) {
		TestAndUpdate(\.id, v2Object.id)
		TestAndUpdate(\.text, v2Object.text)
		TestAndUpdate(\.displayUntil, v2Object.timestamp)	// Yes, the timestamp on an Announcement is its displayUntil date,
															// not its post date.
		
		// Set the author
		if author?.username != v2Object.author.username {
			let userPool: [String : KrakenUser ] = context.userInfo.object(forKey: "Users") as! [String : KrakenUser] 
			if let cdAuthor = userPool[v2Object.author.username] {
				author = cdAuthor
			}
		}
	}

	func displayUntilDate() -> Date {
		return Date(timeIntervalSince1970: Double(displayUntil) / 1000.0)
	}
	
}


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
			var request = NetworkGovernor.buildTwittarV2Request(withPath:"/api/v2/alerts/last_checked", query: nil)
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
		var queryParams: [URLQueryItem] = []
		queryParams.append(URLQueryItem(name:"no_reset", value: "true"))		
		var request = NetworkGovernor.buildTwittarV2Request(withPath:"/api/v2/alerts", query: queryParams)
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
			ingestAnnouncements(from: response.announcements)
		}
		
		// Tweets
		if let twitarrPosts = response.tweetMentions, twitarrPosts.count > 0 {
			TwitarrDataManager.shared.ingestFilterPosts(posts: twitarrPosts)
		}
		
		// Forum Threads
		if let forumThreads = response.forumMentions, forumThreads.count > 0 {
			ForumsDataManager.shared.ingestForumThreads(from: forumThreads)
		}
		
		// Unread Seamails
		if let unreadSeamails = response.unreadSeamail, unreadSeamails.count > 0 {
			SeamailDataManager.shared.ingestSeamailThreads(from: unreadSeamails)
		}
		
		// Events? Are we doing events this way?
		
		LocalCoreData.shared.performNetworkParsing { context in
			if let currentUser = CurrentUser.shared.getLoggedInUser(in: context) {
				currentUser.lastAlertCheckTime = response.queryTime
			}
		}
	}
	
	func ingestAnnouncements(from announcements: [TwitarrV2Announcement]) {
		LocalCoreData.shared.performNetworkParsing { context in
			context.pushOpErrorExplanation("Failure adding announcements to Core Data.")
			
			// This populates "Users" in our context's userInfo to be a dict of [username : KrakenUser]
			let authors = announcements.map { $0.author }
			UserManager.shared.update(users: authors, inContext: context)

			// Get all the Announcement objects already in Core Data whose IDs match those of the announcements we're merging in.
			let newAnnouncementIDs = announcements.map { $0.id }
			let request = LocalCoreData.shared.persistentContainer.managedObjectModel.fetchRequestFromTemplate(withName: "AnnouncementsWithIDs", 
					substitutionVariables: [ "ids" : newAnnouncementIDs ]) as! NSFetchRequest<Announcement>
			let cdAnnouncements = try request.execute()
			let cdAnnouncementsDict = Dictionary(cdAnnouncements.map { ($0.id, $0) }, uniquingKeysWith: { (first,_) in first })

			for ann in announcements {
				let cdAnnouncement = cdAnnouncementsDict[ann.id] ?? Announcement(context: context)
				cdAnnouncement.buildFromV2(context: context, v2Object: ann)
			}
			
			// Note that we don't have a good way to know if an announcement has been deleted. There's an admin call
			// to do it, so it could happen. We could ask for all announcements that are active, and merge-delete any
			// not in the results set. 
		}
	}
}

// MARK: - V2 API Decoding

struct TwitarrV2Announcement: Codable {
    let id: String
	let author: TwitarrV2UserInfo
	let text: String
    let timestamp: Int64
}

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

