//
//  ValidSections.swift
//  Kraken
//
//  Created by Chall Fry on 9/12/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit

@objc class ValidSections: NSObject {
	static let shared = ValidSections()
	
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
		
		init?(with v3Feature: TwitarrV3SwiftarrFeature) {
			switch v3Feature {
			case .tweets:
				self = .stream
			case .forums:
				self = .forums
			case .seamail:
				self = .seamail
			case .schedule:
				self = .calendar
			case .friendlyfez:
				return nil
			case .karaoke:
				self = .karaoke
			case .gameslist:
				self = .games
			case .images:
				return nil
			case .users:
				self = .userProfile
			case .all:
				return nil
			case .unknown:
				return nil
			}
		}
		
		static func all() -> Set<Section> {
			return Set([.forums, .stream, .seamail, .calendar, .games, .karaoke, .search, .registration, .userProfile])
		}
	}
	
	
	// All sections are assumed to be enabled, unless this call specifically says they're not.
	// This means that sections not in the response are assumed to be enabled.
	var disabledSections = Set<Section>()
	var disabledTabs = Set<RootTabBarViewController.Tab>()
	
	// Called from the Alert updater.
	func updateDisabledFeatures(disabled: [TwitarrV3DisabledFeature]) {
		var newDisabledSections = Set<Section>()
		for disabledFeature in disabled {
			if [.kraken, .all].contains(disabledFeature.appName) {
				if let sectionEnum = Section(with: disabledFeature.featureName) {
					newDisabledSections.insert(sectionEnum)
				}
				else if disabledFeature.featureName == .all {
					newDisabledSections.formUnion(Section.all())
				}
			}
		}
		self.disabledSections = newDisabledSections
		self.disabledTabs = Set(newDisabledSections.map { self.tabForSection($0) })
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
