//
//  ComposeTweetViewController.swift
//  Kraken
//
//  Created by Chall Fry on 5/20/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit

class ComposeTweetViewController: BaseCollectionViewController {
	let loginDataSource = FilteringDataSource()
	let frcDataSource = FetchedResultsControllerDataSource<SeamailThread, SeamailThreadCell>()
	let composeDataSource = FilteringDataSource()

    override func viewDidLoad() {
        super.viewDidLoad()

		loginDataSource.viewController = self
        let loginSection = LoginDataSourceSection()
        loginDataSource.appendSection(section: loginSection)
        loginSection.headerCellText = "You will need to log in before you can post to Twitarr."
        
        let composeSection = composeDataSource.appendSection(named: "ComposeSection")
        composeSection.append(TextViewCellModel("Tweet"))
        composeSection.append(ButtonCellModel(title:"Post", action: postAction))
        composeSection.append(EmojiSelectionCellModel())
        

   		CurrentUser.shared.tell(self, when: "loggedInUser") { observer, observed in
        	if observed.loggedInUser == nil {
				observer.loginDataSource.register(with: observer.collectionView)
//				observer.dataManager.removeDelegate(observer.frcDataSource)
        	}
        	else {
        		observer.composeDataSource.register(with: observer.collectionView)
			}
        }?.execute()        
    }
    
    func postAction() {
    	print("Got to posting")
    }
    
    override func viewDidAppear(_ animated: Bool) {
		loginDataSource.enableAnimations = true
	}

    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destination.
        // Pass the selected object to the new view controller.
    }
    */

}

