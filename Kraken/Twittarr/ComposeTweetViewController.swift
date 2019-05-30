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
	var tweetTextCell: TextViewCellModel?

    override func viewDidLoad() {
        super.viewDidLoad()

		loginDataSource.viewController = self
        let loginSection = LoginDataSourceSection()
        loginDataSource.appendSection(section: loginSection)
        loginSection.headerCellText = "You will need to log in before you can post to Twitarr."
        
		composeDataSource.viewController = self
		let composeSection = composeDataSource.appendSection(named: "ComposeSection")
        let textCell = TextViewCellModel("What do you want to say?")
        tweetTextCell = textCell
        composeSection.append(textCell)
        composeSection.append(ButtonCellModel(title:"Post", action: postAction))
        composeSection.append(EmojiSelectionCellModel(paster: emojiButtonTapped))
        composeSection.append(PhotoSelectionCellModel())
        

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
    
    func emojiButtonTapped(withEmojiString: String?) {
    	if let emoji = withEmojiString, let range = activeTextEntry?.selectedTextRange {
    		activeTextEntry?.replace(range, withText: emoji)
    	}
    }
    
    override func viewDidAppear(_ animated: Bool) {
		loginDataSource.enableAnimations = true
		composeDataSource.enableAnimations = true
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

