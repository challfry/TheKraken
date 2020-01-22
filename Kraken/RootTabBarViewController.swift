//
//  RootTabBarViewController.swift
//  Kraken
//
//  Created by Chall Fry on 9/4/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit

class RootTabBarViewController: UITabBarController, GlobalNavEnabled {
	static var shared: RootTabBarViewController? = nil
	var disabledTabs = Set<Tab>()

	// The raw value for each tab is its restorationID, which must also be its storyboardID
	enum Tab: String {
		case daily = "DailyNavController"
		case twitarr = "TwitarrNavController"
		case forums = "ForumsNavViewController" 
		case seamail = "SeamailNavViewController"
		case events = "ScheduleNavController"
		case settings = "SettingsNavController"
		case karaoke = "KaraokeNavController"
		case deckPlans = "DeckMapNavController"
		case scrapbook = "ScrapbookNavController"
		case unknown = ""
	}
	
	override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
		super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
		RootTabBarViewController.shared = self
	}
	
	required init?(coder aDecoder: NSCoder) {
		super.init(coder: aDecoder)
		RootTabBarViewController.shared = self
	}
	
	// Nav to tabs in the tab bar if they exist; else return false
    func globalNavigateTo(packet: GlobalNavPacket) -> Bool {
		
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
    
    func updateEnabledTabs(_ disabledSections: Set<ValidSectionUpdater.Section>) {
 		// Sections is something the server models, to indicate functional areas of the service.
 		// Sections *almost* map to Tabs, but not quite, so we do some layer glue here to translate.
		var newDisabledTabs = Set<Tab>()
    	for section in disabledSections {
    		switch section {
				case .forums: newDisabledTabs.insert(.forums)
				case .stream: newDisabledTabs.insert(.twitarr)
				case .seamail: newDisabledTabs.insert(.seamail)
				case .calendar: newDisabledTabs.insert(.events)
				case .deckPlans: newDisabledTabs.insert(.deckPlans)
				case .games: break // newDisabledTabs.insert(.)
				case .karaoke: newDisabledTabs.insert(.karaoke)
				case .search: break // newDisabledTabs.insert(.)
				case .registration: break
				case .userProfile: break
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
