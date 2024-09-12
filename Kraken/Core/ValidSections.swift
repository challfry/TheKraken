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
		case microKaraoke = "microkaraoke"
		case phonecall = "phonecall"
		case search = "search"
		case registration = "registration"
		case editUserProfile = "user_profile"
		case directphone = "directphone"
		case photostream = "photostream"
		case performers = "performers"
		
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
			case .performers:
				self = .performers
			case .karaoke:
				self = .karaoke
			case .microkaraoke:
				self = .microKaraoke
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
			case .photostream:
				self = .photostream
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
	@objc dynamic var mutationCount: Int = 0
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
		self.mutationCount = self.mutationCount + 1
		self.disabledSections = newDisabledSections
		self.disabledTabs = Set(newDisabledSections.flatMap { self.tabsForSection($0) })
		
		Settings.shared.useDirectVOIPConnnections = !newDisabledSections.contains(.directphone)
	}
	
	func tabsForSection(_ section: Section) -> [RootTabBarViewController.Tab] {
		switch section {
		case .forums: return [.forums]
		case .stream: return [.twitarr]
		case .seamail: return [.seamail]
		case .lfg: return [.lfg]
		case .calendar: return [.events]
		case .performers: return [.officialPerformers, .shadowPerformers]
		case .deckPlans: return [.deckPlans]
		case .games: return [.games]
		case .karaoke: return [.karaoke]
		case .microKaraoke: return [.microKaraoke]
		case .phonecall: return [.initiatePhoneCall]
		case .directphone: break
		case .search: break // return .
		case .editUserProfile: return [.editUserProfile]
		case .registration: break
		case .photostream: break
		}
		
		return [.unknown]
	}
}
