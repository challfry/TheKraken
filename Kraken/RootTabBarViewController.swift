//
//  RootTabBarViewController.swift
//  Kraken
//
//  Created by Chall Fry on 9/4/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit

// This protocol is sort of janky as it requires the caller to fill in the dict with all the steps you need to nav
// to the desired destination, but it works.
protocol GlobalNavEnabled {
	func globalNavigateTo(packet: [String : Any])
}

class RootTabBarViewController: UITabBarController, GlobalNavEnabled {
	static var shared: RootTabBarViewController? = nil

	enum Tabs {
		case Twitarr
		case Forums
		case Seamail
		case Events
		case Settings
	}
	
	override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
		super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
		RootTabBarViewController.shared = self
	}
	
	required init?(coder aDecoder: NSCoder) {
		super.init(coder: aDecoder)
		RootTabBarViewController.shared = self
	}
	
    func globalNavigateTo(packet: [String : Any]) {
    	guard let tab = packet["tab"] as? RootTabBarViewController.Tabs else { return }
    
    	var matchingViewController: UIViewController.Type
    	switch tab {
		case .Twitarr: matchingViewController = TwitarrViewController.self
		case .Forums: matchingViewController = ForumsRootViewController.self
		case .Seamail: matchingViewController = SeamailRootViewController.self
		case .Events: matchingViewController = ScheduleRootViewController.self
		case .Settings:  matchingViewController = TwitarrViewController.self
		}
		
		if let vcs = viewControllers {
			for vc in vcs {
				var vcToMatchAgainst = vc
				
				// If the root of the tab is a Nav controller, check the root of the nav controller instead.
				if let nav = vcToMatchAgainst as? UINavigationController, nav.viewControllers.count > 0 {
					vcToMatchAgainst = nav.viewControllers[0]
				}
				
				// If this is the kind of VC we're looking for, nav to there.
				if vcToMatchAgainst.isKind(of: matchingViewController) {
					selectedViewController = vc
					if let globalNav = vc as? GlobalNavEnabled {
						globalNav.globalNavigateTo(packet: packet)
					}
				}	
			}
		}
    }

}
