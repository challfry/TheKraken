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
	
	lazy var replyLabelCellModel: LabelCellModel = {
		let replyLabelCellModel = LabelCellModel("In response to:")
		replyLabelCellModel.shouldBeVisible = parentTweet != nil
		return replyLabelCellModel
	}()
	
	lazy var replySourceCellModel = TwitarrTweetCellModel(withModel: parentTweet)
	
	lazy var editSourceLabelModel: LabelCellModel = {
		let cellModel = LabelCellModel("Your original post:")
		if draftTweet != nil {
			cellModel.labelText = NSAttributedString(string:"Your original draft:")
		}
		cellModel.shouldBeVisible = editTweet != nil || draftTweet != nil
		return cellModel
	}()

	lazy var editSourceCellModel = TwitarrTweetCellModel(withModel: editTweet)
	lazy var draftSourceCellModel = TwitarrTweetOpCellModel(withModel: draftTweet)

	
	lazy var tweetTextCell: TextViewCellModel = {
		var writingPrompt = "What do you want to say?"
		if editTweet != nil || draftTweet != nil {
			writingPrompt = "What do you want to say instead?"
		}
		else if parentTweet != nil {
			writingPrompt = "What do you want to say?"
		}
		let textCell = TextViewCellModel(writingPrompt)
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
		return textCell
	}()
	
	lazy var postButtonCell: ButtonCellModel = {
		let btnCell = ButtonCellModel()
		btnCell.setupButton(2, title:"Post", action: weakify(self, ComposeTweetViewController.postAction))
		tweetTextCell.tell(btnCell, when: "editedText") { observer, observed in 
			let textString = observed.editedText ?? observed.editText
			observer.button2Enabled = !(textString?.isEmpty ?? true)
		}?.execute()
		
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
	
	lazy var postStatusCell: PostOpStatusCellModel = {
		let statusCell = PostOpStatusCellModel()
		statusCell.shouldBeVisible = false
		statusCell.showSpinner = true
		statusCell.statusText = "Posting..."
        statusCell.cancelAction = { [weak statusCell, weak self] in
        	if let cell = statusCell, let op = cell.postOp {
        		PostOperationDataManager.shared.remove(op: op)
        		cell.postOp = nil
        	}
        	if let self = self {
        		self.setPostingState(false)
        	}
        }
		return statusCell
	}()
	
	lazy var emojiSelectionCell = EmojiSelectionCellModel(paster: weakify(self, ComposeTweetViewController.emojiButtonTapped))
	lazy var photoSelectionCell = PhotoSelectionCellModel()
	
	lazy var draftImageCell: DraftImageCellModel = {
        // Only used when editing a draft, where we have a photo that's already pulled from the library and made
        // into an NSData.
		let cellModel = DraftImageCellModel()
        if let draftImage = draftTweet?.image {
        	cellModel.imageData = draftImage
        	photoSelectionCell.shouldBeVisible = false
        }
        else {
        	cellModel.shouldBeVisible = false
        }
        return cellModel
	}()
	
	var removeDraftImage: Bool = false
    var isPosting = false						// TRUE when we're attempting to assemble post and send to server.
    var postSuccess = false						// TRUE once a post has been successfully completed.

    override func viewDidLoad() {
        super.viewDidLoad()
		knownSegues = Set([.userProfile, .fullScreenCamera, .cropCamera])
        
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
		let composeSection = composeDataSource.appendFilteringSegment(named: "ComposeSection")
		composeSection.append(replyLabelCellModel)
		composeSection.append(replySourceCellModel)
		composeSection.append(editSourceLabelModel)
 		
 		// Only one of edit or draft should end up being visible (we're either editing a posted tweet or 
 		// editing a draft not yet delivered to the server)
		composeSection.append(editSourceCellModel)
		composeSection.append(draftSourceCellModel)
		composeSection.append(tweetTextCell)
        composeSection.append(postButtonCell)
        composeSection.append(postStatusCell)
		composeSection.append(emojiSelectionCell)
        composeSection.append(photoSelectionCell)
        composeSection.append(draftImageCell)
        
		// Swap between the login and compose data sources, based on whether anyone's logged in.
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
		
		if let textCell = composeDataSource.cell(forModel: tweetTextCell) as? TextViewCell {
			textCell.textView.becomeFirstResponder()
		}
	}

	override func viewDidDisappear(_ animated: Bool) {
		if !postSuccess {
			TwitarrDataManager.shared.saveDraftPost(text: tweetTextCell.editedText, replyingTo: parentTweet?.id)
		}
	}

// MARK: Actions    
    
	// When the Post button is hit, we enter 'posting' state, and disable most of the UI. This is reversible, as the 
	// user can cancel the post before it goes to the server.
	func setPostingState(_ isPosting: Bool) {
    	self.isPosting = isPosting
    	postButtonCell.button2Enabled = !isPosting
    	postButtonCell.button2Text = isPosting ? "Posting" : "Post"
    	postStatusCell.shouldBeVisible = isPosting
    	tweetTextCell.isEditable = !isPosting
	}
	
    func postAction() {
    	// No posting without text in the cell; button should be disabled so this can't happen?
    	guard let _ = tweetTextCell.editedText ?? tweetTextCell.editText else { return }
    	setPostingState(true)
    	
    	// TODO: Need to disable photo selection, too.
    	
		if photoSelectionCell.shouldBeVisible == true, let selectedPhoto = photoSelectionCell.selectedPhoto {
			ImageManager.shared.resizeImageForUpload(imageContainer: selectedPhoto, 
					progress: imageiCloudDownloadProgress) { photoData, mimeType, error in
				if let err = error {
					self.postStatusCell.errorText = err.getErrorString()
					self.setPostingState(false)
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
    
    // Queues up the PostOp object for this content.
    func post(withPhoto image: Data?, mimeType: String?) {
    	guard let tweetText = tweetTextCell.editedText ?? tweetTextCell.editText else { return }
		TwitarrDataManager.shared.queuePost(draftTweet, withText: tweetText, image: image, mimeType: mimeType, 
				inReplyTo: parentTweet, editing: self.editTweet, done: postEnqueued)    	
    }
    
    func imageiCloudDownloadProgress(_ progress: Double?, _ error: Error?, _ stopPtr: UnsafeMutablePointer<ObjCBool>, 
    		_ info: [AnyHashable : Any]?) {
		if let error = error {
			postStatusCell.errorText = error.localizedDescription
		}
		else if let resultInCloud = info?[PHImageResultIsInCloudKey] as? NSNumber, resultInCloud.boolValue == true {
			postStatusCell.statusText = "Downloading full-sized photo from iCloud"
		}
	}
    
    // Called by the DM once a post object is enqueued.
    func postEnqueued(post: PostOpTweet?) {
    	if let post = post {
			postStatusCell.postOp = post
			post.tell(self, when: "operationState") { observer, observed in 
				if observed.operationState == .callSuccess || NetworkGovernor.shared.connectionState != .canConnect {
					observer.postSuccess = true
					DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
						observer.performSegue(withIdentifier: "dismissingPostingView", sender: nil)
					}
				}
			}?.execute()
    	}
    	else {
    		postStatusCell.statusText = "Couldn't assemble a post."
			setPostingState(false)
    	}
    }
    
    func emojiButtonTapped(withEmojiString: String?) {
    	if let emoji = withEmojiString, let range = activeTextEntry?.selectedTextRange {
    		activeTextEntry?.replace(range, withText: emoji)
    	}
    }
    
    func draftImageRemoveButtonTapped() {
    	draftImageCell.shouldBeVisible = false
    	photoSelectionCell.shouldBeVisible = true
    	removeDraftImage = true
    }
    
// MARK: - Navigation

	// This is the handler for the CameraViewController's unwind segue. Pull the captured photo out of the
	// source VC to get the photo that was taken.
	@IBAction func dismissingCamera(_ segue: UIStoryboardSegue) {
		guard let sourceVC = segue.source as? CameraViewController else { return }
		if let photo = sourceVC.capturedPhoto {
			photoSelectionCell.cameraPhotos.insert(photo, at: 0)
		}
		else if let photoImage = sourceVC.capturedPhotoImage {
			photoSelectionCell.cameraPhotos.insert(photoImage, at: 0)
		}
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
