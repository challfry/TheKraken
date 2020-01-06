//
//  ForumComposeViewController.swift
//  Kraken
//
//  Created by Chall Fry on 12/31/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit
import Photos
import MobileCoreServices

/*
	Reference
		Thread Title				-- Unless it's a new thread
		original Post				-- If it's an edit
		origional Draft				-- If it's a draft (a postOp)
		last Post in Thread			-- If it's a new post

	Composition
		Subject						-- new threads only
		Text						-- post text
		Post Button					-- 
		Author Info Cell			-- Shows up when there's multiple logins.
		Emoji						-- Helps out the text cell.
		Photos						-- Attach multiple photos
	
	
*/

@objc class ForumComposeViewController: BaseCollectionViewController {

	// Set by caller during segue
	var thread: ForumThread?			
	var editPost: ForumPost?				// If we're editing a post, the original
	var draftPost: PostOpForumPost?			// If we're editing a draft, the draft

	let loginDataSource = KrakenDataSource()
	let composeDataSource = KrakenDataSource()
	var didPost = false
	
	lazy var threadTitleReferenceCell: LabelCellModel = {
		var titleString = ""
		if let forumThread = thread {
			titleString = "In thread \"\(forumThread.subject)\""
		}
		let cell = LabelCellModel(titleString)
		if thread == nil && editPost == nil && draftPost == nil {
			cell.shouldBeVisible = false
		}
		return cell
	}()
	
	@objc dynamic lazy var threadTitleEditCell: TextViewCellModel = {
		var writingPrompt = "Title of your Forum Thread:"
		//		if editTweet != nil || draftTweet != nil {
		//			writingPrompt = "What do you want to say instead?"
		//		}
		//		else if parentTweet != nil {
		//			writingPrompt = "What do you want to say?"
		//		}
		
		let cell =  TextViewCellModel(writingPrompt)
		if thread != nil || editPost != nil || draftPost != nil {
			cell.shouldBeVisible = false
		}
		return cell
	}()
	
	@objc dynamic lazy var postTextCell: TextViewCellModel = {
		var writingPrompt = "What do you want to say?"
		//		if editTweet != nil || draftTweet != nil {
		//			writingPrompt = "What do you want to say instead?"
		//		}
		//		else if parentTweet != nil {
		//			writingPrompt = "What do you want to say?"
		//		}
		return TextViewCellModel(writingPrompt)
	}()
	
	lazy var postButtonCell: ButtonCellModel = {
		let btnCell = ButtonCellModel()
		btnCell.setupButton(2, title:"Post", action: weakify(self, ForumComposeViewController.postAction))
		
		CurrentUser.shared.tell(btnCell, when: ["loggedInUser", "credentialedUsers"]) { observer, observed in
			if CurrentUser.shared.isMultiUser(), let currentUser = CurrentUser.shared.loggedInUser,
					let posterFont = UIFont(name:"Georgia-Italic", size: 14),
					let posterColor = UIColor(named: "Kraken Secondary Text") {	
				let textAttrs: [NSAttributedString.Key : Any] = [ .font : posterFont, .foregroundColor : posterColor ]
				observer.infoText = NSAttributedString(string: "Posting as: \(currentUser.username)", attributes: textAttrs)
			}
			else {
				observer.infoText = nil
			}
		}?.execute()
		
		return btnCell
	}()
	
	lazy var statusCell: OperationStatusCellModel = {
		let cell = OperationStatusCellModel()
		cell.shouldBeVisible = false
        cell.showSpinner = true
        cell.statusText = "Posting..."
        return cell
	}()
	
	lazy var emojiCell: EmojiSelectionCellModel = 
		EmojiSelectionCellModel(paster: weakify(self, ForumComposeViewController.emojiButtonTapped))
	
    override func viewDidLoad() {
        super.viewDidLoad()
		knownSegues = Set([.userProfile, .fullScreenCamera, .cropCamera])
		title = "New Post"

		// We have 2 data sources and we swap between them. First up is the Login DS.
		loginDataSource.viewController = self
        let loginSection = LoginDataSourceSegment()
        loginDataSource.append(segment: loginSection)
        loginSection.headerCellText = "You will need to log in before you can make Forum posts."

		// Then the Compose DS, which hosts all the 'main' content.
		composeDataSource.viewController = self
		let composeSection = composeDataSource.appendFilteringSegment(named: "ComposeSection")
		composeSection.append(threadTitleReferenceCell)

		composeSection.append(threadTitleEditCell)
		composeSection.append(postTextCell)
        composeSection.append(postButtonCell)
        composeSection.append(statusCell)
        composeSection.append(emojiCell)

		// And this switches between them.
   		CurrentUser.shared.tell(self, when: "loggedInUser") { observer, observed in
     	  	if observed.loggedInUser == nil {
				observer.loginDataSource.register(with: observer.collectionView, viewController: observer)
        	}
        	else {
        		observer.composeDataSource.register(with: observer.collectionView, viewController: observer)
			}
        }?.execute()  
        
        // Enable the post button when: There's post text, AND either a thread to post in or a subject for a new thread.
		self.tell(self, when: ["threadTitleEditCell.editedText", "postTextCell.editedText"]) { observer, observed in 
			let titleString = observed.threadTitleEditCell.editedText ?? observed.threadTitleEditCell.editText ?? ""
			let contentString = observed.postTextCell.editedText ?? observed.postTextCell.editText ?? ""
			observer.postButtonCell.button2Enabled = (observer.thread != nil || !titleString.isEmpty) &&
					!contentString.isEmpty
		}?.execute()
	}
	
    func postAction() {
    	// No posting without text in the cell; button should be disabled so this can't happen?
    	guard let _ = postTextCell.editedText ?? postTextCell.editText else { return }

    	didPost = true
    	postButtonCell.button2Enabled = false
    	postButtonCell.button2Text = "Posting"
    	statusCell.shouldBeVisible = true
    	threadTitleEditCell.isEditable = false
    	postTextCell.isEditable = false
	}
	
    func emojiButtonTapped(withEmojiString: String?) {
    	if let emoji = withEmojiString, let range = activeTextEntry?.selectedTextRange {
    		activeTextEntry?.replace(range, withText: emoji)
    	}
    }
    
	// MARK: - Navigation
    
	// This is the handler for the CameraViewController's unwind segue. Pull the captured photo out of the
	// source VC to get the photo that was taken.
	@IBAction func dismissingCamera(_ segue: UIStoryboardSegue) {
		guard let sourceVC = segue.source as? CameraViewController else { return }
		if let photo = sourceVC.capturedPhoto {
//			photoSelectionCell?.cameraPhotos.insert(photo, at: 0)
		}
	}	
}
