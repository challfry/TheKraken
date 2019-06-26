//
//  ComposeTweetViewController.swift
//  Kraken
//
//  Created by Chall Fry on 5/20/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit
import Photos

class ComposeTweetViewController: BaseCollectionViewController {
	var parentTweet: TwitarrPost?
	var editTweet: TwitarrPost?

	let loginDataSource = FilteringDataSource()
	let composeDataSource = FilteringDataSource()
	var tweetTextCell: TextViewCellModel?
	var postButtonCell: ButtonCellModel?
	var photoSelectionCell: PhotoSelectionCellModel?

    override func viewDidLoad() {
        super.viewDidLoad()
        
        // If we have a tweet to edit, but no parent set, and the tweet we're editing is a response (that is, has a parent)
        // set that tweet as the parent.
        if editTweet != nil, parentTweet == nil, let newParent = editTweet?.parent {
        	parentTweet = newParent
        }

		loginDataSource.viewController = self
        let loginSection = LoginDataSourceSection()
        loginDataSource.appendSection(section: loginSection)
        loginSection.headerCellText = "You will need to log in before you can post to Twitarr."
        
		composeDataSource.viewController = self
//		let referenceSection = composeDataSource.appendSection(named: "ReferenceSection")
		let composeSection = composeDataSource.appendSection(named: "ComposeSection")

		let replyLabelCellModel = LabelCellModel("In response to:")
		replyLabelCellModel.shouldBeVisible = parentTweet != nil
		composeSection.append(replyLabelCellModel)
		let replySourceCellModel = TwitarrTweetCellModel(withModel: parentTweet, reuse: "tweet")
		composeSection.append(replySourceCellModel)
		
		let editSourceLabelModel = LabelCellModel("Your original post:")
		editSourceLabelModel.shouldBeVisible = editTweet != nil
		composeSection.append(editSourceLabelModel)
 		let editSourceCellModel = TwitarrTweetCellModel(withModel: editTweet, reuse: "tweet")
		composeSection.append(editSourceCellModel)

		var writingPrompt = "What do you want to say?"
		if editTweet != nil {
			writingPrompt = "What do you want to say insteead?"
		}
		else if parentTweet != nil {
			writingPrompt = "What do you want to say?"
		}
		let textCell = TextViewCellModel(writingPrompt)
        tweetTextCell = textCell
        if let editTweet = editTweet {
			textCell.editText = StringUtilities.cleanupText(editTweet.text).string
		} 
		else if let draftText = TwitarrDataManager.shared.getDraftPostText(replyingTo: parentTweet?.id) {
			textCell.editText = draftText
		}
        
		let btnCell = ButtonCellModel(title:"Post", action: postAction)
		postButtonCell = btnCell
		composeSection.append(textCell)
        composeSection.append(btnCell)
        composeSection.append(EmojiSelectionCellModel(paster: emojiButtonTapped))
        let photoCell = PhotoSelectionCellModel()
        composeSection.append(photoCell)
        photoSelectionCell = photoCell

   		CurrentUser.shared.tell(self, when: "loggedInUser") { observer, observed in
        	if observed.loggedInUser == nil {
				observer.loginDataSource.register(with: observer.collectionView, viewController: observer)
        	}
        	else {
        		observer.composeDataSource.register(with: observer.collectionView, viewController: observer)
			}
        }?.execute()        
    }
    
    override func viewDidAppear(_ animated: Bool) {
		loginDataSource.enableAnimations = true
		composeDataSource.enableAnimations = true
	}

	override func viewDidDisappear(_ animated: Bool) {
		if !didPost {
			TwitarrDataManager.shared.saveDraftPost(text: tweetTextCell?.editedText, replyingTo: parentTweet?.id)
		}
	}

// MARK: Actions    
    
    var didPost = false
    func postAction() {
    	didPost = true
    	if let tweetText = tweetTextCell?.editedText ?? tweetTextCell?.editText {
    		if let postPhotoAsset = photoSelectionCell?.getSelectedPhoto() {
				let _ = PHImageManager.default().requestImageData(for: postPhotoAsset, options: nil) { image, dataUTI, orientation, info in
					if let image = image {
	    				TwitarrDataManager.shared.queueNewPost(withText: tweetText, image: image, inReplyTo: self.parentTweet)
					}
				} 
			} else {
	    		TwitarrDataManager.shared.queueNewPost(withText: tweetText, image: nil, inReplyTo: parentTweet)
			}
		}
    }
    
    func emojiButtonTapped(withEmojiString: String?) {
    	if let emoji = withEmojiString, let range = activeTextEntry?.selectedTextRange {
    		activeTextEntry?.replace(range, withText: emoji)
    	}
    }
    
// MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
    	switch segue.identifier {
		case "UserProfile":
			if let destVC = segue.destination as? UserProfileViewController, let username = sender as? String {
				destVC.modelUserName = username
			}
		default: break 
    	}

    }

	override func shouldPerformSegue(withIdentifier identifier: String, sender: Any?) -> Bool {
		if identifier == "TweetFilter" {
			return false
		}
		
		return true
	}

}

