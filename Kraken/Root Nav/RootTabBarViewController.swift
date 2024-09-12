//
//  RootTabBarViewController.swift
//  Kraken
//
//  Created by Chall Fry on 9/4/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit

class RootTabBarViewController: UITabBarController, GlobalNavEnabled {
	var disabledTabs = Set<Tab>()

	// The raw value for each tab is its restorationID, which must also be its storyboardID
	enum Tab: String {
		case daily = "DailyNavController"
		case twitarr = "TwitarrNavController"
		case forums = "ForumsNavViewController" 
		case seamail = "SeamailNavViewController"
		case lfg = "LFGNavViewController"
		case events = "ScheduleNavController"
		
		case officialPerformers = "PerformerGalleryViewController"
		case shadowPerformers = "PerformerGalleryViewController2"
		case karaoke = "KaraokeNavController"
		case microKaraoke = "MicroKaraokeNavController"
		case games = "GamesListNavController"
		case deckPlans = "DeckMapNavController"
		case initiatePhoneCall = "InitiateCallViewController"
		case editUserProfile = "UserProfileEditViewController"
		case scrapbook = "ScrapbookNavController"
		case lighter = "RockBalladViewController"
		case pirateAR = "CameraViewController"

		case settings = "SettingsNavController"
		case twitarrHelp = "ServerTextFileDisplay"
		case about = "AboutViewController"
		case unknown = ""
	}
	
	override func awakeFromNib() {
		AlertsUpdater.shared.tell(self, when: "lastUpdateTime") {observer, observed in
			observer.updateEnabledTabs(ValidSections.shared.disabledSections)
		}?.execute()
	}
	
	override func viewDidLoad() {
		super.viewDidLoad()
	}
	
	func setBadge(for tab: Tab, to badgeValue: Int) {
		if let foundVC = viewControllers?.first(where: { $0.restorationIdentifier == tab.rawValue }) {
			foundVC.tabBarItem.badgeValue = badgeValue > 0 ? "\(badgeValue)" : nil
		}
	}
		
	// Nav to tabs in the tab bar if they exist; else return false
	@discardableResult func globalNavigateTo(packet: GlobalNavPacket) -> Bool {
		
		if let vcs = viewControllers {
			for vc in vcs {				
				// If this is the VC we're looking for, nav to there.
				if vc.restorationIdentifier == packet.tab.rawValue {
					selectedViewController = vc
					if let globalNav = vc as? GlobalNavEnabled {
						globalNav.globalNavigateTo(packet: packet)
					}
					return true
				}	
			}
		}
		return false
    }
    
    func updateEnabledTabs(_ disabledSections: Set<ValidSections.Section>) {
 		// Sections is something the server models, to indicate functional areas of the service.
 		// Sections *almost* map to Tabs, but not quite, so we do some layer glue here to translate.
		var newDisabledTabs = Set<Tab>()
    	for section in disabledSections {
    		switch section {
				case .stream: newDisabledTabs.insert(.twitarr)
				
				case .forums: newDisabledTabs.insert(.forums)
				case .seamail: newDisabledTabs.insert(.seamail)
				case .lfg: newDisabledTabs.insert(.lfg)
				case .calendar: newDisabledTabs.insert(.events)
				
				case .performers: newDisabledTabs.insert(.officialPerformers)
					newDisabledTabs.insert(.shadowPerformers)
				case .deckPlans: newDisabledTabs.insert(.deckPlans)
				case .games: break // newDisabledTabs.insert(.)
				case .karaoke: newDisabledTabs.insert(.karaoke)
				case .microKaraoke: newDisabledTabs.insert(.microKaraoke)
				case .phonecall: newDisabledTabs.insert(.initiatePhoneCall)
				case .directphone: break
				case .editUserProfile: newDisabledTabs.insert(.editUserProfile)
				case .search: break // newDisabledTabs.insert(.)
				case .photostream: break
				case .registration: break
			}
    	}
    	
    	let tabsToEnable = disabledTabs.subtracting(newDisabledTabs)
    	let tabsToDisable = newDisabledTabs.subtracting(disabledTabs)
    	if !tabsToEnable.isEmpty || !tabsToDisable.isEmpty, let vcs = viewControllers {
			let storyboard = UIStoryboard(name: "Main", bundle: nil)
   			var newViewControllers = vcs
			for (index, vc) in vcs.enumerated() {	
				if let restoID = vc.restorationIdentifier, let thisTabID = Tab(rawValue: restoID) {
					if tabsToEnable.contains(thisTabID) {
						newViewControllers[index] = storyboard.instantiateViewController(withIdentifier: restoID)
					}	
					if tabsToDisable.contains(thisTabID) {
						let replacementVC = DisabledContentViewController(forTab: thisTabID)
						replacementVC.restorationIdentifier = thisTabID.rawValue
						newViewControllers[index] = replacementVC
					}
				}	
			}
			
			// Replace the viewcontrollers with a new array
			viewControllers = newViewControllers
    		disabledTabs = newDisabledTabs
    	}
    }

}
