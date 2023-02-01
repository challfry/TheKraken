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
		case lfg = "lfg"
		case calendar = "calendar"
		case deckPlans = "deck_plans"
		case games = "games"
		case karaoke = "karaoke"
		case phonecall = "phonecall"
		case search = "search"
		case registration = "registration"
		case editUserProfile = "user_profile"
		case directphone = "directphone"
		
		init?(with v3Feature: TwitarrV3SwiftarrFeature) {
			switch v3Feature {
			case .tweets:
				self = .stream
			case .forums:
				self = .forums
			case .seamail:
				self = .seamail
			case .friendlyfez:
				self = .lfg
			case .schedule:
				self = .calendar
			case .karaoke:
				self = .karaoke
			case .gameslist:
				self = .games
			case .images:
				return nil
			case .users:
				self = .editUserProfile
			case .phone:
				self = .phonecall
			case .directphone:
				self = .directphone
			case .all:
				return nil
			case .unknown:
				return nil
			}
		}
		
		static func all() -> Set<Section> {
			return Set([.forums, .stream, .seamail, .lfg, .calendar, .deckPlans, .games, .karaoke, .phonecall,
					.search, .registration, .editUserProfile])
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
		
		Settings.shared.useDirectVOIPConnnections = !newDisabledSections.contains(.directphone)
	}
	
	func tabForSection(_ section: Section) -> RootTabBarViewController.Tab {
		switch section {
		case .forums: return .forums
		case .stream: return .twitarr
		case .seamail: return .seamail
		case .lfg: return .lfg
		case .calendar: return .events
		case .deckPlans: return .deckPlans
		case .games: return .games
		case .karaoke: return .karaoke
		case .phonecall: return .initiatePhoneCall
		case .directphone: break
		case .search: break // return .
		case .editUserProfile: return .editUserProfile
		case .registration: break
		}
		
		return .unknown
	}
}
