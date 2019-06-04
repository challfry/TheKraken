//
//  SettingsLoginViewController.swift
//  Kraken
//
//  Created by Chall Fry on 6/2/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit

class SettingsLoginViewController: BaseCollectionViewController {
	
	let loginDataSource = FilteringDataSource()
	
	override func viewDidLoad() {
        super.viewDidLoad()
        loginDataSource.viewController = self
        let loginSection = LoginDataSourceSection()
        loginDataSource.appendSection(section: loginSection)
		
		loginSection.headerCellText = "Log in to Twitarr here."
		
        CurrentUser.shared.tell(self, when: "loggedInUser") { observer, observed in
        	if observed.loggedInUser == nil {
				observer.loginDataSource.register(with: observer.collectionView)
        	}
        	else {
       			observer.dismiss(animated: true, completion: nil)
       	}
        }?.execute()

		title = "Seamail"
    }
	
    override func viewDidAppear(_ animated: Bool) {
		loginDataSource.enableAnimations = true
	}
}
