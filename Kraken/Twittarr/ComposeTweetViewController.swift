//
//  ComposeTweetViewController.swift
//  Kraken
//
//  Created by Chall Fry on 5/20/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit
import Photos
import MobileCoreServices

class ComposeTweetViewController: BaseCollectionViewController {
	var parentTweet: TwitarrPost?			// If we're composing a reply, the parent
	var editTweet: TwitarrPost?				// If we're editing a posted tweet, the original
	var draftTweet: PostOpTweet?			// If we're editing a draft, the draft

	let loginDataSource = KrakenDataSource()
	let composeDataSource = KrakenDataSource()
	var tweetTextCell: TextViewCellModel?
	var postButtonCell: ButtonCellModel?
	var postStatusCell: OperationStatusCellModel?
	var photoSelectionCell: PhotoSelectionCellModel?
	var draftImageCell: DraftImageCellModel?
	var removeDraftImage: Bool = false

    override func viewDidLoad() {
        super.viewDidLoad()
        
        // If we have a tweet to edit, but no parent set, and the tweet we're editing is a response (that is, has a parent)
        // set that tweet as the parent.
        if parentTweet == nil, let newParent = editTweet?.parent ?? draftTweet?.parent {
        	parentTweet = newParent
        }

		loginDataSource.viewController = self
        let loginSection = LoginDataSourceSegment()
        loginDataSource.append(segment: loginSection)
        loginSection.headerCellText = "You will need to log in before you can post to Twitarr."
        
		composeDataSource.viewController = self
//		let referenceSection = composeDataSource.appendSection(named: "ReferenceSection")
		let composeSection = composeDataSource.appendFilteringSegment(named: "ComposeSection")

		let replyLabelCellModel = LabelCellModel("In response to:")
		replyLabelCellModel.shouldBeVisible = parentTweet != nil
		composeSection.append(replyLabelCellModel)
		let replySourceCellModel = TwitarrTweetCellModel(withModel: parentTweet, reuse: "tweet")
		composeSection.append(replySourceCellModel)
		
		let editSourceLabelModel = LabelCellModel("Your original post:")
		if draftTweet != nil {
			editSourceLabelModel.labelText = NSAttributedString(string:"Your original draft:")
		}
		editSourceLabelModel.shouldBeVisible = editTweet != nil || draftTweet != nil
		composeSection.append(editSourceLabelModel)
 		let editSourceCellModel = TwitarrTweetCellModel(withModel: editTweet, reuse: "tweet")
 		if draftTweet != nil {
 			editSourceCellModel.model = draftTweet
 		}
		composeSection.append(editSourceCellModel)

		var writingPrompt = "What do you want to say?"
		if editTweet != nil || draftTweet != nil {
			writingPrompt = "What do you want to say instead?"
		}
		else if parentTweet != nil {
			writingPrompt = "What do you want to say?"
		}
		let textCell = TextViewCellModel(writingPrompt)
        tweetTextCell = textCell
        if let editTweet = editTweet {
			textCell.editText = StringUtilities.cleanupText(editTweet.text).string
		} 
		else if let draftTweet = draftTweet {
			// This is from a draft tweet not yet sent to the server; waiting in the PostOp queue
			textCell.editText = StringUtilities.cleanupText(draftTweet.text).string
		}
		else if let draftText = TwitarrDataManager.shared.getDraftPostText(replyingTo: parentTweet?.id) {
			// This is from our cache of uncompleted tweets, where user typed something but didn't post.
			textCell.editText = draftText
		}
        
		let btnCell = ButtonCellModel()
		btnCell.setupButton(2, title:"Post", action: weakify(self, ComposeTweetViewController.postAction))
		postButtonCell = btnCell
		tweetTextCell?.tell(btnCell, when: "editedText") { observer, observed in 
			let textString = observed.editedText ?? observed.editText
			observer.button2Enabled = !(textString?.isEmpty ?? true)
		}?.execute()
 
        let statusCell = OperationStatusCellModel()
        statusCell.shouldBeVisible = false
        statusCell.showSpinner = true
        statusCell.statusText = "Posting..."
        postStatusCell = statusCell

		composeSection.append(textCell)
        composeSection.append(btnCell)
        composeSection.append(statusCell)
		composeSection.append(EmojiSelectionCellModel(paster: weakify(self, ComposeTweetViewController.emojiButtonTapped)))
		
        let photoCell = PhotoSelectionCellModel()
        composeSection.append(photoCell)
        photoSelectionCell = photoCell
        
        // Only used when editing a draft, where we have a photo that's already pulled from the library and made
        // into an NSData.
        if let draftImage = draftTweet?.image {
        	draftImageCell = DraftImageCellModel()
        	draftImageCell!.imageData = draftImage
        	composeSection.append(draftImageCell!)
        	photoSelectionCell?.shouldBeVisible = false
        }

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
		
		if let cellModel = tweetTextCell, let textCell = composeDataSource.cell(forModel: cellModel) as? TextViewCell {
			textCell.textView.becomeFirstResponder()
		}
	}

	override func viewDidDisappear(_ animated: Bool) {
		if !didPost {
			TwitarrDataManager.shared.saveDraftPost(text: tweetTextCell?.editedText, replyingTo: parentTweet?.id)
		}
	}

// MARK: Actions    
    
    var didPost = false
    func postAction() {
    	// No posting without text in the cell; button should be disabled so this can't happen?
    	guard let _ = tweetTextCell?.editedText ?? tweetTextCell?.editText else { return }
    
    	didPost = true
    	postButtonCell?.button2Enabled = false
    	postButtonCell?.button2Text = "Posting"
    	postStatusCell?.shouldBeVisible = true
    	tweetTextCell?.isEditable = false
    	
    	// TODO: Need to disable photo selection, too.
    	
		if photoSelectionCell?.shouldBeVisible == true, let selectedPhoto = photoSelectionCell?.selectedPhoto {
			ImageManager.shared.resizeImageForUpload(imageContainer: selectedPhoto, 
					progress: imageiCloudDownloadProgress) { photoData, mimeType, error in
				if let err = error {
					self.postStatusCell?.errorText = err.getErrorString()
				}
				else {
					self.post(withPhoto: photoData, mimeType: mimeType)
				}
			}
		} else {
			var image: Data?
			var mimeType: String?
			
			// If editing a draft (as yet undelivered to server) post, we already have the photo to attach
			// saved as an NSData, not a PHImage in the photos library. So, we handle it a bit differently.
			// (also, delivering a post with an attached image should work even if the user disables photo access
			// after tapping Post).
			if !removeDraftImage {
				image = draftTweet?.image as Data?
				mimeType = draftTweet?.imageMimetype
			}
			post(withPhoto: image, mimeType: mimeType)
		}
    }
    
    func post(withPhoto image: Data?, mimeType: String?) {
    	guard let tweetText = tweetTextCell?.editedText ?? tweetTextCell?.editText else { return }
		TwitarrDataManager.shared.queuePost(draftTweet, withText: tweetText, image: image, mimeType: mimeType, 
				inReplyTo: parentTweet, editing: self.editTweet, done: postEnqueued)    	
    }
    
    func imageiCloudDownloadProgress(_ progress: Double?, _ error: Error?, _ stopPtr: UnsafeMutablePointer<ObjCBool>, 
    		_ info: [AnyHashable : Any]?) {
		if let error = error {
			postStatusCell?.errorText = error.localizedDescription
		}
		else if let resultInCloud = info?[PHImageResultIsInCloudKey] as? NSNumber, resultInCloud.boolValue == true {
			postStatusCell?.statusText = "Downloading full-sized photo from iCloud"
		}
	}
    
    func postEnqueued(post: PostOpTweet?) {
    	if post == nil {
    		postStatusCell?.statusText = "Couldn't assemble a post."
    	}
    	else {
    		postStatusCell?.statusText = "Sending post to server."
		}
    }
    
    func emojiButtonTapped(withEmojiString: String?) {
    	if let emoji = withEmojiString, let range = activeTextEntry?.selectedTextRange {
    		activeTextEntry?.replace(range, withText: emoji)
    	}
    }
    
    func draftImageRemoveButtonTapped() {
    	draftImageCell?.shouldBeVisible = false
    	photoSelectionCell?.shouldBeVisible = true
    	removeDraftImage = true
    }
    
// MARK: - Navigation

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
    	switch segue.identifier {
		case "UserProfile":
			if let destVC = segue.destination as? UserProfileViewController, let username = sender as? String {
				destVC.modelUserName = username
			}
		case "Camera":
			break
		default: break 
    	}

    }

	// This is the handler for the CameraViewController's unwind segue. Pull the captured photo out of the
	// source VC to get the photo that was taken.
	@IBAction func dismissingCamera(_ segue: UIStoryboardSegue) {
		guard let sourceVC = segue.source as? CameraViewController else { return }
		if let photo = sourceVC.capturedPhoto {
			photoSelectionCell?.cameraPhotos.insert(photo, at: 0)
		}
	}	

	override func shouldPerformSegue(withIdentifier identifier: String, sender: Any?) -> Bool {
		if identifier == "TweetFilter" {
			return false
		}
		
		return true
	}

}

@objc protocol DraftImageCellProtocol {
	@objc dynamic var imageData: NSData? { get set }
}

@objc class DraftImageCellModel: BaseCellModel, DraftImageCellProtocol {	
	private static let validReuseIDs = [ "DraftImageCell" : DraftImageCell.self ]
	override class var validReuseIDDict: [String: BaseCollectionViewCell.Type ] { return validReuseIDs }
	
	@objc dynamic var imageData: NSData? {
		didSet {
			shouldBeVisible = imageData != nil
		}
	}

	init() {
		super.init(bindingWith: DraftImageCellProtocol.self)
	}
	
}

class DraftImageCell: BaseCollectionViewCell, DraftImageCellProtocol {
	@IBOutlet var imageView: UIImageView!

	private static let cellInfo = [ "DraftImageCell" : PrototypeCellInfo("DraftImageCell") ]
	override class var validReuseIDDict: [ String: PrototypeCellInfo ] { return cellInfo }

	var imageData: NSData? {
		didSet {
			if let image = imageData {
				imageView.image = UIImage(data: image as Data)
			}
		}
	}
	
	@IBAction func removeButtonTapped() {
		if let vc = viewController as? ComposeTweetViewController {
			vc.draftImageRemoveButtonTapped()
		}
	}
}
