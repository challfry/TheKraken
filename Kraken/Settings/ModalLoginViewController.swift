//
//  ModalLoginViewController.swift
//  Kraken
//
//  Created by Chall Fry on 6/2/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit

class ModalLoginViewController: BaseCollectionViewController {
	
	let loginDataSource = KrakenDataSource()
	var segueData: LoginSegueWithAction?
	
	override func viewDidLoad() {
        super.viewDidLoad()
        loginDataSource.viewController = self
        let loginSection = LoginDataSourceSegment()
		loginDataSource.append(segment: loginSection)
        
        if let segueData = segueData {
			loginSection.headerCellText = segueData.promptText
		}
		else {
			loginSection.headerCellText = "Log in to Twitarr here."
		}
		
		loginDataSource.register(with: collectionView, viewController: self)

		// Note that this observation dismisses the VC if the user enters the logged in state *for any reason*, including
		// if they somehow managed to open a second login window (via another tab, perhaps) and log in there.
        CurrentUser.shared.tell(self, when: "credentialedUsers") { observer, observed in
//        	if observed.loggedInUser == nil {
//				observer.loginDataSource.register(with: observer.collectionView, viewController: self)
//        	}
//        	else {
       			observer.dismiss(animated: true, completion: nil)
				if let segueData = observer.segueData {
					segueData.loginSuccessAction?()
				}
//    		}
        }
    }
	
    override func viewDidAppear(_ animated: Bool) {
		loginDataSource.enableAnimations = true
	}
}

// MARK: Segue Packages

struct LoginSegueWithAction {
	var promptText: String
	
	// This VC doesn't actually execute either of these. Generally modal login acts as an interstitial for some 
	// other action the user wants to perform, and these closures let that action continue happening after the user
	// logs in. But, any UI from those actions should happen in the VC they started in, not the login VC.
	// So, the presenting VC should grab the closure from the login VC during the unwind segue, and run it there.
	//
	// Also: I'm choosing not to differentiate between "User entered creds in this VC and successfully logged in" from
	// "User transitioned to the logged in state, via any mechanism." So, check CurrentUser to see if someone's logged in.
	var loginSuccessAction: (() -> Void)?
	var loginFailureAction: (() -> Void)?
}
