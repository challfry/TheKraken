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
	var thread: ForumThread?				// If it's a post in an existing thread
	var category: ForumCategory?			// If it's a new thread in this category
	var editPost: ForumPost?				// If we're editing a post, the original
	var draftPost: PostOpForumPost?			// If we're editing a draft, the draft
	var inProgressOp: PostOpForumPost?		// Post in progress

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
	
	lazy var editSourceCell: LabelCellModel = {
		var labelText = "Your original post:"
		if draftPost != nil {
			labelText = "Your original draft:"
		}
		let cell = LabelCellModel(labelText)
		cell.shouldBeVisible = editPost != nil || draftPost != nil
		return cell
	}()
	
	lazy var originalPostCell: ForumPostCellModel = {
		let cell = ForumPostCellModel(withModel: editPost)
		cell.isInteractive = false
		return cell
	}()
	
	lazy var originalDraftCell: ForumPostOpCellModel = {
		let cell = ForumPostOpCellModel(withModel: draftPost)
		cell.isInteractive = false
		return cell
	}()
	
	@objc dynamic lazy var threadTitleEditCell: TextViewCellModel = {
		var writingPrompt = "Title of your Forum Thread:"		
		let cell =  TextViewCellModel(writingPrompt)
		cell.purpose = .twitarr
		
		// Show the thread title edit field if: This is not a post in an existing thread, not an edit to 
		// an existing post, and either not a draft or a draft edit where the draft is a draft of a new thread.
		if thread != nil || editPost != nil || draftPost?.thread != nil {
			cell.shouldBeVisible = false
		}
		
		if let draft = draftPost {
			cell.editText = draft.subject
		}
		return cell
	}()
	
	@objc dynamic lazy var postTextCell: TextViewCellModel = {
		var writingPrompt = "What do you want to say?"
		if editPost != nil || draftPost != nil {
			writingPrompt = "What do you want to say instead?"
		}
		let cell = TextViewCellModel(writingPrompt)
		if let edit = editPost {
			cell.editText = edit.text
		}
		else if let draft = draftPost {
			cell.editText = draft.text
		}
		cell.purpose = .twitarr
		return cell
	}()
	
	lazy var userSuggestionsCell: UserListCoreDataCellModel = {
		let cell = UserListCoreDataCellModel(withTitle: "@ Username Completions")
		cell.selectionCallback = suggestedUserTappedAction
		return cell
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
	
	lazy var statusCell: PostOpStatusCellModel = {
		let cell = PostOpStatusCellModel()
		cell.shouldBeVisible = false
        cell.showSpinner = true
        cell.statusText = "Posting..."
        
        cell.cancelAction = { [weak cell, weak self] in
        	if let cell = cell, let op = cell.postOp {
        		PostOperationDataManager.shared.remove(op: op)
        		cell.postOp = nil
        	}
        	if let self = self {
        		self.setPostingState(false)
        	}
        }
        return cell
	}()
	
	lazy var emojiCell: EmojiSelectionCellModel = 
		EmojiSelectionCellModel(paster: weakify(self, ForumComposeViewController.emojiButtonTapped))
		
	lazy var photoCell = PhotoSelectionCellModel()
	
// MARK: Methods
	
    override func viewDidLoad() {
        super.viewDidLoad()
		knownSegues = Set([.userProfile, .fullScreenCamera, .cropCamera])
		
		var viewTitle = "New Thread"
		if draftPost != nil {
			viewTitle = "Edit Draft"
		}
		else if editPost != nil {
			viewTitle = "Edit Post"
		}
		else if thread != nil {
			viewTitle = "New Post"
		}
		title = viewTitle
		
		if let dr = draftPost {
			thread = dr.thread
		}
		else if let edit = editPost {
			thread = edit.thread
		}

		// We have 2 data sources and we swap between them. First up is the Login DS.
		loginDataSource.viewController = self
        let loginSection = LoginDataSourceSegment()
        loginDataSource.append(segment: loginSection)
        loginSection.headerCellText = "You will need to log in before you can make Forum posts."

		// Then the Compose DS, which hosts all the 'main' content.
		composeDataSource.viewController = self
		let composeSection = composeDataSource.appendFilteringSegment(named: "ComposeSection")
		composeSection.append(threadTitleReferenceCell)
		composeSection.append(editSourceCell)
		composeSection.append(originalPostCell)
		composeSection.append(originalDraftCell)

		composeSection.append(threadTitleEditCell)
		composeSection.append(postTextCell)
		composeSection.append(userSuggestionsCell)
        composeSection.append(postButtonCell)
        composeSection.append(statusCell)
        composeSection.append(emojiCell)
        composeSection.append(photoCell)

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
			observer.postButtonCell.button2Enabled = (observer.thread != nil || observer.draftPost?.thread != nil ||
					!titleString.isEmpty) && !contentString.isEmpty
		}?.execute()
		
		// Let the userSuggestion cell know about changes made to the post text field
		postTextCell.tell(userSuggestionsCell, when: "editedText") { observer, observed in 
			if let text = observed.getText(), !text.isEmpty, let lastAtSign = text.lastIndex(of: "@") {
				let partialUsername = String(text.suffix(from: lastAtSign).dropFirst())
				if !partialUsername.contains(" "), partialUsername.count > 0 {
					observer.usePredicate = true
					observer.predicate = NSPredicate(format: "username CONTAINS[cd] %@", partialUsername)
					observer.shouldBeVisible = true
				 
					// Ask the server for name completions
					UserManager.shared.autocorrectUserLookup(for: partialUsername, done: self.userCompletionsCompletion)
				}
				else {
					observer.shouldBeVisible = false
				}
			}
			else {
				observer.shouldBeVisible = false
			}
		}?.execute()

	}
	
    override func viewDidAppear(_ animated: Bool) {
    	super.viewDidAppear(animated)
		loginDataSource.enableAnimations = true
		composeDataSource.enableAnimations = true
		
		if let textCell = composeDataSource.cell(forModel: postTextCell) as? TextViewCell {
			textCell.textView.becomeFirstResponder()
		}
	}

    func postAction() {
    	// No posting without text in the cell; button should be disabled so this can't happen?
    	guard let _ = postTextCell.editedText ?? postTextCell.editText else { return }
    	setPostingState(true)
    	    	
		if photoCell.shouldBeVisible, let selectedPhoto = photoCell.selectedPhoto {
			ImageManager.shared.resizeImageForUpload(imageContainer: selectedPhoto, 
					progress: imageiCloudDownloadProgress) { photoData, error in
				if let err = error {
					self.statusCell.errorText = err.getCompleteError()
				}
				else if let container = photoData {
					self.postWithPreparedImages([container])
				}
				else {
					self.postWithPreparedImages(nil)
				}
			}
		} else {
//			var image: Data?
//			var mimeType: String?
			
			// If editing a draft (as yet undelivered to server) post, we already have the photo to attach
			// saved as an NSData, not a PHImage in the photos library. So, we handle it a bit differently.
			// (also, delivering a post with an attached image should work even if the user disables photo access
			// after tapping Post).
//			if !removeDraftImage {
//				image = draftTweet?.image as Data?
//				mimeType = draftTweet?.imageMimetype
//			}
			self.postWithPreparedImages(nil)
		}
	}
	
    func imageiCloudDownloadProgress(_ progress: Double?, _ error: Error?, _ stopPtr: UnsafeMutablePointer<ObjCBool>, 
    		_ info: [AnyHashable : Any]?) {
		if let error = error {
			statusCell.errorText = error.localizedDescription
		}
		else if let resultInCloud = info?[PHImageResultIsInCloudKey] as? NSNumber, resultInCloud.boolValue == true {
			statusCell.statusText = "Downloading full-sized photo from iCloud"
		}
	}
	
	// When the Post button is hit, we enter 'posting' state, and disable most of the UI. This is reversible, as the 
	// user can cancel the post before it goes to the server.
	func setPostingState(_ isPosting: Bool) {
    	didPost = isPosting
    	postButtonCell.button2Enabled = !isPosting
    	postButtonCell.button2Text = isPosting ? "Posting" : "Post"
    	statusCell.shouldBeVisible = isPosting
    	threadTitleEditCell.isEditable = !isPosting
    	postTextCell.isEditable = !isPosting

	}
	
    func postWithPreparedImages(_ images: [PhotoDataType]?) {
    	guard let postText = postTextCell.editedText ?? postTextCell.editText else { return }
    	var subjectText: String?
    	if threadTitleEditCell.shouldBeVisible {
    		subjectText =  threadTitleEditCell.editedText ?? postTextCell.editText 
		}
    	
    	if let edit = editPost {
    		// This is an edit of an existing post.
			ForumPostDataManager.shared.queuePostEditOp(for: edit, newText: postText, images: images, done: postEnqueued)    	
    	}
		else {
			// This is a new post in an existing thread, or a new thread, or an update to a draft of a post.
			ForumPostDataManager.shared.queuePost(existingDraft: draftPost, inThread: thread, inCategory: category, titleText: subjectText,
					postText: postText, images: images, done: postEnqueued)
		}
    }

    func postEnqueued(post: PostOpForumPost?) {
    	if let post = post {
	    	statusCell.postOp = post
    		inProgressOp = post
    	
    		// If we can connect to the server, wait until we suceed/fail the network call. Else, we 'succeed' as soon
    		// as we queue up the post. Either way, 2 sec timer, then dismiss the compose view.
 		   	post.tell(self, when: "operationState") { observer, observed in 
				if observed.operationState == .callSuccess || NetworkGovernor.shared.connectionState != .canConnect {
    				DispatchQueue.main.asyncAfter(deadline: .now() + DispatchTimeInterval.seconds(2)) {
						self.performSegue(withIdentifier: "dismissingPostingView", sender: nil)
    				}
    			}
			}?.execute()
    	}
    }

    func emojiButtonTapped(withEmojiString: String?) {
    	if let emoji = withEmojiString, let range = activeTextEntry?.selectedTextRange {
    		activeTextEntry?.replace(range, withText: emoji)
    	}
    }
    
    // When the user starts typing an "@" username, they get a user suggestion cell with username completions. 
    // Tapping on a user in the list gets them here.
	func suggestedUserTappedAction(user: PossibleKrakenUser) {
		var username: String
		if let krakenUser = user.user {
			username = krakenUser.username
		}
		else {
			username = user.username
		}
		
		guard var postText = postTextCell.getText(), let lastAtSign = postText.lastIndex(of: "@") else { return }
		let suffix = postText.suffix(from: lastAtSign)
		if suffix.contains(" ") { return }
		postText.replaceSubrange(lastAtSign..<postText.endIndex, with: "@\(username)")
		postTextCell.editText = ""
		postTextCell.editText = postText
	}

	// When the Username Completions call returns we need to re-set the predicate. If we were using a fetchedResultsController,
	// we wouldn't need to do this (the FRC informs us of new results automatically)
	func userCompletionsCompletion(for: String?) {
		let pred = userSuggestionsCell.predicate
		userSuggestionsCell.predicate = nil
		userSuggestionsCell.predicate = pred
	}

	// MARK: - Navigation
    
	// This is the handler for the CameraViewController's unwind segue. Pull the captured photo out of the
	// source VC to get the photo that was taken.
	@IBAction func dismissingCamera(_ segue: UIStoryboardSegue) {
		guard let sourceVC = segue.source as? CameraViewController else { return }
		if let photoPacket = sourceVC.capturedPhoto {
			switch photoPacket {
			case .camera(let photo): photoCell.cameraPhotos.insert(photo, at: 0)
			case .image(let image): photoCell.cameraPhotos.insert(image, at: 0)
			case .library: break
			case .data: break
			case .server: break
			}
		}
	}	
}
