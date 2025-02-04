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
		case .lfg:
			tabName = "LFG"
		case .events:
			tabName = "Schedule"
		case .officialPerformers:
			tabName = "Performers"
		case .shadowPerformers:
			tabName = "Shadow Event Organizers"
		case .settings:
			tabName = "Settings"
		case .karaoke:
			tabName = "Karaoke"
		case .microKaraoke:
			tabName = "Micro Karaoke"
		case .games:
			tabName = "Games"
		case .initiatePhoneCall:
			tabName = "KrakenTalk"
		case .editUserProfile:
			tabName = "User Profile"
		case .deckPlans:
			tabName = "Deck Maps"
		case .scrapbook:
			tabName = "Scrapbook"
		case .lighter:
			tabName = "Lighter"
		case .pirateAR:
			tabName = "PirateAR"
		case .codeOfConduct:
			tabName = "Code of Conduct"
		case .twitarrHelp:
			tabName = "Help"
		case .about:
			tabName = "About"
		case .faq:
			tabName = "Cruise FAQ"
		case .serverFile:
			tabName = "Tab"
		case .privateEvent:
			tabName = "Private Event"
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
			featurePath = "/tweets"
		case .forums:
			featureName = "the Forums"
			featurePath = "/forums"
		case .seamail:
			featureName = "Seamail"
			featurePath = "/seamail"
		case .lfg:
			featureName = "Looking For Group"
			featurePath = "/lfg"
		case .events:
			featureName = "the Events Schedule"
			featurePath = "/events"
		case .officialPerformers:
			featureName = "Performers"
			featurePath = "/performers"
		case .shadowPerformers:
			featureName = "Shadow Event Organizers"
			featurePath = "/events/performers/shadow"
		case .settings:
			featureName = "the Settings Panel"
			featurePath = ""
		case .karaoke:
			featureName = "the Karaoke Song Finder"
			featurePath = "/karaoke"
		case .microKaraoke:
			featureName = "the Micro Karaoke Feature"
			featurePath = ""					// Local; not on server
		case .games:
			featureName = "the Board Games List"
			featurePath = "/boardgames"
		case .initiatePhoneCall:
			featureName = "Phone Calls"
			featurePath = ""
		case .editUserProfile:
			featureName = "User Profile"
			featurePath = "/profile/edit"
		case .deckPlans:
			featureName = "Deck Maps"
			featurePath = "/map"
		case .scrapbook:
			featureName = "Scrapbook"
			featurePath = ""
		case .lighter:
			featureName = "Lighter"
			featurePath = ""					// Local; not on server
		case .pirateAR:
			featureName = "Pirate Selfie"
			featurePath = ""					// Local; not on server
		case .codeOfConduct:
			featureName = "Code Of Conduct"
			featurePath = "/public/codeOfConduct.md"
		case .faq:
			featureName = "Cruise FAQ"
			featurePath = "/faq"
		case .twitarrHelp:
			featureName = "Help"
			featurePath = "/about"				
		case .about:
			featureName = "About Kraken"
			featurePath = ""					// Local; not on server
		case .serverFile:
			featureName =  "Server File Viewer"
			featurePath = ""
		case .privateEvent:
			featureName =  "Private Events"
			featurePath = "/privateevent"

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
