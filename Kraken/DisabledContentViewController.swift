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
		case .social:
			tabName = "Social"
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
    	var featureName: String
    	var featurePath: String
		switch (tabBeingReplaced ?? .unknown) {
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
		case .social:
			featureName = "all Social Media"
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