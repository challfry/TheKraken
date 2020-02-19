//
//  DisabledContentViewController.swift
//  Kraken
//
//  Created by Chall Fry on 9/13/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit

class DisabledContentViewController: UIViewController {
	@IBOutlet weak var disabledLabel: UILabel!
	@IBOutlet weak var linkExplanationLabel: UILabel!
	@IBOutlet weak var linkButton: UIButton!
	
	var tabBeingReplaced: RootTabBarViewController.Tab?
	var linkURL: URL?
	
	init(forTab: RootTabBarViewController.Tab) {
		tabBeingReplaced = forTab
		super.init(nibName: nil, bundle: nil)

    	var tabName: String
		switch (tabBeingReplaced ?? .unknown) {
		case .daily:
			tabName = "Daily"
		case .twitarr:
			tabName = "Twitarr"
		case .forums:
			tabName = "Forums"
		case .seamail:
			tabName = "Seamail"
		case .events:
			tabName = "Schedule"
		case .settings:
			tabName = "Settings"
		case .karaoke:
			tabName = "Karaoke"
		case .games:
			tabName = "Games"
		case .deckPlans:
			tabName = "Deck Maps"
		case .scrapbook:
			tabName = "Scrapbook"
		case .lighter:
			tabName = "Lighter"
		case .twitarrHelp:
			tabName = "Help"
		case .about:
			tabName = "About"
		case .unknown:
			tabName = "Tab"
		}
		
		tabBarItem.title = tabName
		tabBarItem.image = UIImage(named: "Disabled")
	}
    	
	required init?(coder aDecoder: NSCoder) {
		super.init(coder: aDecoder)
	}
	
    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
    	var featureName: String
    	var featurePath: String
		switch (tabBeingReplaced ?? .unknown) {
		case .daily:
			featureName = "the Daily Information panel"
			featurePath = ""
		case .twitarr:
			featureName = "the Twittar posting stream"
			featurePath = "/#/stream"
		case .forums:
			featureName = "the Forums"
			featurePath = "/#/forums"
		case .seamail:
			featureName = "Seamail"
			featurePath = "/#/seamail"
		case .events:
			featureName = "the Events Schedule"
			featurePath = "/#/events"
		case .settings:
			featureName = "the Settings Panel"
			featurePath = ""
		case .karaoke:
			featureName = "the Karaoke Song Finder"
			featurePath = ""
		case .games:
			featureName = "the Board Games List"
			featurePath = ""
		case .deckPlans:
			featureName = "Deck Maps"
			featurePath = ""
		case .scrapbook:
			featureName = "Scrapbook"
			featurePath = ""
		case .lighter:
			featureName = "Lighter"
			featurePath = ""
		case .twitarrHelp:
			featureName = "Help"
			featurePath = ""
		case .about:
			featureName = "About Kraken"
			featurePath = ""
		case .unknown:
			featureName = "this feature"
			featurePath = ""

		}
		
		disabledLabel.text = "The Twitarr Team has disabled \(featureName)"
		
		if featurePath.count > 0 {
			let linkString = Settings.shared.baseURL.absoluteString.appending(featurePath)
			linkURL = URL(string: linkString)
			linkButton.setTitle(linkString, for: .normal)
			linkExplanationLabel.isHidden = false
			linkButton.isHidden = false
		}
		else {
			linkExplanationLabel.isHidden = true
			linkButton.isHidden = true
		}
	}
    

	@IBAction func linkButtonTapped(_ sender: Any) {
		if let urlToOpen = linkURL {
			UIApplication.shared.open(urlToOpen, options: [:], completionHandler: nil)
		}
	}
}
