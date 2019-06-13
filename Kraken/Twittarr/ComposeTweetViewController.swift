//
//  ComposeTweetViewController.swift
//  Kraken
//
//  Created by Chall Fry on 5/20/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit

class ComposeTweetViewController: BaseCollectionViewController {
	var parentTweet: TwitarrPost?
	var editTweet: TwitarrPost?

	let loginDataSource = FilteringDataSource()
//	let frcDataSource = FetchedResultsControllerDataSource<SeamailThread, SeamailThreadCell>()
	let composeDataSource = FilteringDataSource()
	var tweetTextCell: TextViewCellModel?
	var postButtonCell: ButtonCellModel?

    override func viewDidLoad() {
        super.viewDidLoad()

		loginDataSource.viewController = self
        let loginSection = LoginDataSourceSection()
        loginDataSource.appendSection(section: loginSection)
        loginSection.headerCellText = "You will need to log in before you can post to Twitarr."
        
		composeDataSource.viewController = self
//		let referenceSection = composeDataSource.appendSection(named: "ReferenceSection")
		let composeSection = composeDataSource.appendSection(named: "ComposeSection")

		let replySourceCellModel = TwitarrTweetCellModel(withModel: parentTweet, reuse: "tweet")
		composeSection.append(replySourceCellModel)
		
        let textCell = TextViewCellModel("What do you want to say?")
        tweetTextCell = textCell
		let btnCell = ButtonCellModel(title:"Post", action: postAction)
		postButtonCell = btnCell
		composeSection.append(textCell)
        composeSection.append(btnCell)
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
    	let context = LocalCoreData.shared.mainThreadContext
    	let tweetText = tweetTextCell?.editedText
    	
//    	context.perform {
//    		do {
//				let newPost = PostOperationTweet(context: context)
//				newPost.build(text, photo, parent, edit)
//				try context.save()
//			}
//			catch {
//				
//			}
//    	}
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

