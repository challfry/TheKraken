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

	// Tabs in this context may not be actual tabs in the tab bar, although the first group are sometimes actual tabs.
	// These enum cases describe things that could be made into tabs in the tab bar, in that they're roots of nav stacks.
	// On iPad even the first group gets nav pushed onto the stack the daily VC is on.
	// e.g. 'Forums' is a tab because 1) it's on the tab bar when there is one and 2) the `Forum Categories' VC gets pushed
	// directly onto Daily if there's no tab bar. If we're navigating to a forum thread, we'd push categories first and then the 
	// category, and then the thread.
	enum Tab: CaseIterable {
		// These are actual tabs (on phone layouts)
		case daily
		case twitarr
		case forums
		case seamail
		case lfg
		case events
		
		case officialPerformers
		case shadowPerformers
		case karaoke
		case microKaraoke
		case games
		case deckPlans
		case initiatePhoneCall
		case editUserProfile 
		case scrapbook
		case lighter
		case pirateAR

		case settings
		case about
		case codeOfConduct
		case twitarrHelp
		case faq
		case serverFile
		
		case unknown
		
		// The raw value for each tab is its restorationID, which must also be its storyboardID
		func vc() -> String {
			switch self {
				case .daily: return "DailyNavController"
				case .twitarr: return "TwitarrNavController"
				case .forums: return "ForumsNavViewController" 
				case .seamail: return "SeamailNavViewController"
				case .lfg: return "LFGNavViewController"
				case .events: return "ScheduleNavController"
				
				case .officialPerformers: return "PerformerGalleryViewController"
				case .shadowPerformers: return "PerformerGalleryViewController"
				case .karaoke: return "KaraokeNavController"
				case .microKaraoke: return "MicroKaraokeNavController"
				case .games: return "GamesListNavController"
				case .deckPlans: return "DeckMapNavController"
				case .initiatePhoneCall: return "InitiateCallViewController"
				case .editUserProfile: return "UserProfileEditViewController"
				case .scrapbook: return "ScrapbookNavController"
				case .lighter: return "RockBalladViewController"
				case .pirateAR: return "CameraViewController"

				case .settings: return "SettingsNavController"
				case .about: return "AboutViewController"
				case .codeOfConduct: return "ServerTextFileDisplay"
				case .twitarrHelp: return "ServerTextFileDisplay"
				case .faq: return "ServerTextFileDisplay"
				case .serverFile: return "ServerTextFileDisplay"
				
				case .unknown: return ""
			}
		}
		
		func presentByCovering() -> Bool {
			return [.about, .codeOfConduct, .twitarrHelp, .faq, .serverFile].contains(self)
		}
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
		if let foundVC = viewControllers?.first(where: { $0.restorationIdentifier == tab.vc() }) {
			foundVC.tabBarItem.badgeValue = badgeValue > 0 ? "\(badgeValue)" : nil
		}
	}
		
	// Nav to tabs in the tab bar if they exist; else return false
	@discardableResult func globalNavigateTo(packet: GlobalNavPacket) -> Bool {
		
		if let vcs = viewControllers {
			for vc in vcs {				
				// If this is the VC we're looking for, nav to there.
				if vc.restorationIdentifier == packet.tab.vc() {
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
				if let restoID = vc.restorationIdentifier {
					for tabID in Tab.allCases where tabID.vc() == restoID  {
						if tabsToEnable.contains(tabID) {
							newViewControllers[index] = storyboard.instantiateViewController(withIdentifier: restoID)
						}	
						if tabsToDisable.contains(tabID) {
							let replacementVC = DisabledContentViewController(forTab: tabID)
							replacementVC.restorationIdentifier = tabID.vc()
							newViewControllers[index] = replacementVC
						}
					}
				}	
			}
			
			// Replace the viewcontrollers with a new array
			viewControllers = newViewControllers
    		disabledTabs = newDisabledTabs
    	}
    }

}
