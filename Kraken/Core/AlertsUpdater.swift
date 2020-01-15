//
//  AlertsUpdater.swift
//  Kraken
//
//  Created by Chall Fry on 1/15/20.
//  Copyright © 2020 Chall Fry. All rights reserved.
//

import UIKit

class AlertsUpdater: ServerUpdater {
	init() {
		// Update every minute.
		super.init(60)
	}
	
	override func updateMethod() {
		let request = NetworkGovernor.buildTwittarV2Request(withPath:"/api/v2/alerts", query: nil)

		NetworkGovernor.shared.queue(request) { networkResponse in
			if let response = networkResponse.response as? HTTPURLResponse, response.statusCode < 300,
					let data = networkResponse.data {
//				print (String(decoding:data!, as: UTF8.self))
				let decoder = JSONDecoder()
//				do {
//					let sectionsResponse = try decoder.decode(TwitarrV2ServerSectionStatusResponse.self, from: data)
//					var newDisabledSections = Set<Section>()
//					for section in sectionsResponse.sections {
//						if section.enabled == false {
//							if let sectionEnum = Section(rawValue: section.name) {
//								newDisabledSections.insert(sectionEnum)
//							}
//						}
//					}
//					self.disabledSections = newDisabledSections
//					
//					// Tell the tab bar controller to update its disabled sections.  
//					DispatchQueue.main.async {
//						RootTabBarViewController.shared?.updateEnabledTabs(self.disabledSections)
//					}
//					
//				} catch 
//				{
//					NetworkLog.error("Failure parsing server sections response.", ["Error" : error, "URL" : request.url as Any])
//				} 
			}
			self.updateComplete(success: true)
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
