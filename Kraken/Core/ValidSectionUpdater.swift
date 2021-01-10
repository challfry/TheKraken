//
//  ValidSectionUpdater.swift
//  Kraken
//
//  Created by Chall Fry on 9/12/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit

@objc class ValidSectionUpdater: ServerUpdater {
	static let shared = ValidSectionUpdater()
	
	enum Section: String {
		case forums = "forums"
		case stream = "stream"
		case seamail = "seamail"
		case calendar = "calendar"
		case deckPlans = "deck_plans"
		case games = "games"
		case karaoke = "karaoke"
		case search = "search"
		case registration = "registration"
		case userProfile = "user_profile"
	}
	
	
	// All sections are assumed to be enabled, unless this call specifically says they're not.
	// This means that sections not in the response are assumed to be enabled.
	var disabledSections = Set<Section>()
	var disabledTabs = Set<RootTabBarViewController.Tab>()
	
	init() {
		// Update every 15 minutes.
		super.init(15 * 60)
		
	}

	override func updateMethod() {
		let request = NetworkGovernor.buildTwittarV2Request(withPath:"/api/v2/admin/sections", query: nil)
		NetworkGovernor.shared.queue(request) { networkResponse in
			if let response = networkResponse.response, response.statusCode < 300,
					let data = networkResponse.data {
//				print (String(decoding:data!, as: UTF8.self))
				let decoder = JSONDecoder()
				do {
					let sectionsResponse = try decoder.decode(TwitarrV2ServerSectionStatusResponse.self, from: data)
					var newDisabledSections = Set<Section>()
					for section in sectionsResponse.sections {
						if section.enabled == false {
							if let sectionEnum = Section(rawValue: section.name) {
								newDisabledSections.insert(sectionEnum)
							}
							if section.name.hasPrefix("Kraken_") {
								let nameSuffix = section.name.dropFirst(7)
								if let sectionEnum = Section(rawValue: String(nameSuffix)) {
									newDisabledSections.insert(sectionEnum)
								}

							}
						}
					}
					self.disabledSections = newDisabledSections
					self.disabledTabs = Set(newDisabledSections.map { self.tabForSection($0) })
										
				} catch 
				{
					NetworkLog.error("Failure parsing server sections response.", ["Error" : error, "URL" : request.url as Any])
				} 
			}
			self.updateComplete(success: true)
		}
	}
	
	func tabForSection(_ section: Section) -> RootTabBarViewController.Tab {
		switch section {
		case .forums: return .forums
		case .stream: return .twitarr
		case .seamail: return .seamail
		case .calendar: return .events
		case .deckPlans: return .deckPlans
		case .games: break // return .
		case .karaoke: return .karaoke
		case .search: break // return .
		case .registration: break
		case .userProfile: break
		}
		
		return .unknown
	}
}

// MARK: - V2 API Decoding

struct TwitarrV2ServerSectionStatus: Codable {
	let name: String
	let enabled: Bool
}

// GET /api/v2/admin/sections
struct TwitarrV2ServerSectionStatusResponse: Codable {
	let status: String
	let sections: [TwitarrV2ServerSectionStatus]
}
