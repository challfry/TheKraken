//
//  BaseCollectionViewController.swift
//  Kraken
//
//  Created by Chall Fry on 4/27/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit

enum GlobalKnownSegue: String {
	case dismiss =					"dismiss"
	case dismissCamera =			"dismissCamera"
	
	case modalLogin = 				"ModalLogin"

	case tweetFilter = 				"TweetFilter"
	case pendingReplies = 			"PendingReplies"
	case composeReplyTweet = 		"ComposeReplyTweet"
	case editTweet = 				"EditTweet"
	case editTweetOp = 				"EditTweetOp"
	case composeTweet = 			"ComposeTweet"
	case showUserTweets = 			"ShowUserTweets"
	case showUserMentions = 		"ShowUserMentions"
	
	case showForumThread = 			"ShowForumThread"
	case composeForumThread = 		"ComposeForumThread"
	case composeForumPost = 		"ComposeForumPost"
	case editForumPost = 			"EditForumPost"
	case editForumPostDraft = 		"EditForumPostDraft"
	
	case showSeamailThread = 		"ShowSeamailThread"
	case editSeamailThreadOp = 		"EditSeamailThreadOp"

	case userProfile = 				"UserProfile"
	case editUserProfile = 			"EditUserProfile"
	
	case postOperations =			"PostOperations"
	case showRoomOnDeckMap = 		"ShowRoomOnDeckMap"
	case fullScreenCamera = 		"fullScreenCamera"
	case cropCamera = 				"cropCamera"
	
	var senderType: Any.Type {
		switch self {
		case .dismiss: return Any.self
		case .dismissCamera: return Data?.self
		
		case .modalLogin: return LoginSegueWithAction.self

		case .tweetFilter: return String.self
		case .pendingReplies: return TwitarrPost.self
		case .composeReplyTweet: return TwitarrPost.self
		case .editTweet: return TwitarrPost.self
		case .editTweetOp: return PostOpTweet.self
		case .composeTweet: return Void.self
		case .showUserTweets: return String.self
		case .showUserMentions: return String.self
		
		case .showForumThread: return ForumThread.self
		case .composeForumThread: return Void.self 
		case .composeForumPost: return ForumThread.self 
		case .editForumPost: return ForumPost.self 
		case .editForumPostDraft: return PostOpForumPost.self 
		
		case .showSeamailThread: return SeamailThread.self
		case .editSeamailThreadOp: return PostOpSeamailThread.self
		
		case .userProfile: return String.self
		case .editUserProfile: return PostOpUserProfileEdit.self

		case .postOperations: return Any.self
		
		case .showRoomOnDeckMap: return String.self
		case .fullScreenCamera: return BaseCollectionViewCell.self
		case .cropCamera: return BaseCollectionViewCell.self

//		@unknown default: return Void.self
		}
	}
}

class BaseCollectionViewController: UIViewController {
	@IBOutlet var collectionView: UICollectionView!
	@objc dynamic var activeTextEntry: UITextInput?
		
	var customGR: UILongPressGestureRecognizer?
	var tappedCell: UICollectionViewCell?
	var indexPathToScrollToVisible: IndexPath?
	
	var knownSegues: Set<GlobalKnownSegue> = Set()
	
    override func viewDidLoad() {
        super.viewDidLoad()
     	let keyboardCanceler = UITapGestureRecognizer(target: view, action: #selector(UIView.endEditing(_:)))
 //    	keyboardCanceler.cancelsTouchesInView = false
	 	view.addGestureRecognizer(keyboardCanceler)
               
 		if let layout = collectionView.collectionViewLayout as? UICollectionViewFlowLayout {
			layout.itemSize = UICollectionViewFlowLayout.automaticSize
			let width = self.view.frame.size.width
			layout.estimatedItemSize = CGSize(width: width, height: 52 )
			
			layout.minimumLineSpacing = 0
		}
 
		NotificationCenter.default.addObserver(self, selector: #selector(BaseCollectionViewController.keyboardWillShow(notification:)), 
				name: UIResponder.keyboardDidShowNotification, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(BaseCollectionViewController.keyboardDidShowNotification(notification:)), 
				name: UIResponder.keyboardDidShowNotification, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(BaseCollectionViewController.keyboardWillHide(notification:)), 
				name: UIResponder.keyboardDidHideNotification, object: nil)

		let bgImage = UIImageView(frame: view.frame)
		view.addSubview(bgImage)
		view.sendSubviewToBack(bgImage)
		bgImage.image = UIImage(named: "octo1")
		bgImage.contentMode = .scaleAspectFill
		bgImage.alpha = 0.0
		
		// Show the background image in Deep Sea Mode
		Settings.shared.tell(self, when: "uiDisplayStyle") { observer, observed in 
			UIView.animate(withDuration: 0.3) {
				bgImage.alpha = observed.uiDisplayStyle == .deepSeaMode ? 1.0 : 0.0
			}
		}?.execute()
		
		// Shift the collectionView down a bit if we're showing the no network warning view.
		// It'd be cleaner to do this in the KrakenNavController, where the 'No Network' banner is, but I don't see how.
		NetworkGovernor.shared.tell(self, when: "connectionState") { observer, governor in
			if governor.connectionState != NetworkGovernor.ConnectionState.canConnect,
					let nav = observer.navigationController as? KrakenNavController, !nav.networkLabel.isHidden {
				let size = nav.networkLabel.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
				observer.collectionView.contentInset = UIEdgeInsets(top: size.height, 
						left: 0, bottom: 0, right: 0)
			}
			else {
				observer.collectionView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
			}
		}?.execute()
	}
	
	var photoCoveringView: UIVisualEffectView?
	
	func showImageInOverlay(image: UIImage) {
		let imageSize = image.size
		let hScaleFactor: CGFloat = view.bounds.size.width / imageSize.width
		let vScaleFactor: CGFloat = view.bounds.size.height / imageSize.height
		let scaleFactor = hScaleFactor < vScaleFactor ? hScaleFactor : vScaleFactor
		let imageViewSize = CGSize(width: imageSize.width * scaleFactor, height: imageSize.height * scaleFactor)
		
		if let win = view.window {
			var effectStyle = UIBlurEffect.Style.dark
			if #available(iOS 13.0, *) {
				effectStyle = .systemUltraThinMaterialDark
			}
			let coveringView = UIVisualEffectView(effect: nil)
			coveringView.frame = win.frame
			win.addSubview(coveringView)

			let overlayImageView = UIImageView()
			overlayImageView.translatesAutoresizingMaskIntoConstraints = false
			coveringView.contentView.addSubview(overlayImageView)
			let constraints = [
					overlayImageView.widthAnchor.constraint(equalToConstant: imageViewSize.width),
					overlayImageView.heightAnchor.constraint(equalToConstant: imageViewSize.height),
					overlayImageView.centerYAnchor.constraint(equalTo: coveringView.centerYAnchor),
					overlayImageView.centerXAnchor.constraint(equalTo: coveringView.centerXAnchor) ]
			NSLayoutConstraint.activate(constraints)
			overlayImageView.image = image
			
			UIView.animate(withDuration: 1) {
				coveringView.effect = UIBlurEffect(style: effectStyle)
			}
			
			let photoTap = UITapGestureRecognizer(target: self, action: #selector(BaseCollectionViewController.photoTapped(_:)))
			coveringView.contentView.addGestureRecognizer(photoTap)
			photoCoveringView = coveringView
		}
	}
	
	@objc func photoTapped(_ sender: UITapGestureRecognizer) {
		if let coveringView = photoCoveringView {
			coveringView.removeFromSuperview()
			photoCoveringView = nil
		}
	}
        
    @objc func keyboardWillShow(notification: NSNotification) {
		if let keyboardHeight = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue.height {
			collectionView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: keyboardHeight, right: 0)
		}
	}

    @objc func keyboardDidShowNotification(notification: NSNotification) {
    	if let indexPath = indexPathToScrollToVisible {
			collectionView.scrollToItem(at: indexPath, at: .centeredVertically, animated: true)
		}
	}

	@objc func keyboardWillHide(notification: NSNotification) {
		UIView.animate(withDuration: 0.2, animations: {
			self.collectionView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
		})
	}
	
	func textViewBecameActive(_ field: UITextInput, inCell: BaseCollectionViewCell) {
		activeTextEntry = field
		if let indexPath = collectionView.indexPath(for: inCell) {
			indexPathToScrollToVisible = indexPath
		}
	}
	
	func textViewResignedActive(_ field: UITextInput, inCell: BaseCollectionViewCell) {
		activeTextEntry = nil
		indexPathToScrollToVisible = nil
	}
	
	// MARK: - Navigation

	// FFS Apple should provide this as part of their API. This is used by collectionView cells to see if they're
	// attached to a ViewController that supports launching a given segue; if not they generally hide/disable buttons.
	// This only matters if you make cells that are usable in multiple VCs, which Apple apparently recommends against --
	// a recommendation about as useful as Q-Tips recommending you not use Q-Tips in your ears.
	func canPerformSegue(_ segue: GlobalKnownSegue) -> Bool {
		return knownSegues.contains(segue)
	}
	
	func performKrakenSegue(_ id: GlobalKnownSegue, sender: Any?) {
		guard canPerformSegue(id) else {
			let vcType = type(of: self)
			AppLog.error("VC \(vcType) doesn't claim to support segue \(id.rawValue)")
			return 
		}
	
		if let senderValue = sender {
			let expectedType = id.senderType
			var typeIsValid =  type(of: senderValue) == expectedType || expectedType == Any.self
			if !typeIsValid {
				let seq = sequence(first: Mirror(reflecting: senderValue), next: { $0.superclassMirror })
				typeIsValid = seq.contains { $0.subjectType == expectedType }
			}
			
			if typeIsValid {
				let segueName = id.rawValue
				performSegue(withIdentifier: segueName, sender: sender)
			}
		}
		else {
			// Always allow segues with nil senders. This doesn't mean prepare(for segue) will like it.
			performSegue(withIdentifier: id.rawValue, sender: sender)
		}
	}

	// Most global segues are only dependent on their destination VC and info in the sender parameter.
	// We handle most of them here. Subclasses can override this to handle segues with special needs.
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
    	if let _ = prepareGlobalSegue(for: segue, sender: sender) {
    		return
    	}
    }
    
	// Set up data in destination view controllers when we're about to segue to them.
	// Note: This fn has knowledge of a bunch of its subclasses. A cooler solution would be some sort of 
	// registration system but boy is that needlessly complicated.
    func prepareGlobalSegue(for segue: UIStoryboardSegue, sender: Any?) -> GlobalKnownSegue? {
    	guard let segueName = segue.identifier, let id = GlobalKnownSegue(rawValue: segueName) else {
    		return nil
    	}
    	
    	switch id {

// Twittar
		// A filtered view of the tweet stream.
		case .tweetFilter:
			if let destVC = segue.destination as? TwitarrViewController, let filterString = sender as? String {
				destVC.dataManager = TwitarrDataManager(filterString: filterString)
			}
				
		// PostOpTweets by this user, that are replies to a given tweet.
		case .pendingReplies:
			if let destVC = segue.destination as? PendingTwitarrRepliesVC, let parent = sender as? TwitarrPost {
				destVC.parentTweet = parent
			}
			
		case .showUserMentions:
			if let destVC = segue.destination as? TwitarrViewController, let filterString = sender as? String {
				destVC.dataManager = TwitarrDataManager(filterString: filterString)
			}
			
		case .showUserTweets:
			if let destVC = segue.destination as? TwitarrViewController, let filterString = sender as? String {
				destVC.dataManager = TwitarrDataManager(predicate: NSPredicate(format: "author.username == %@", filterString),
						titleString: "Author: \(filterString)")
			}
			
		case .composeTweet: break
		
		case .composeReplyTweet:
			if let destVC = segue.destination as? ComposeTweetViewController, let parent = sender as? TwitarrPost {
				destVC.parentTweet = parent
			}
			
		case .editTweet, .editTweetOp:
			if let destVC = segue.destination as? ComposeTweetViewController {
				if let original = sender as? TwitarrPost {
					destVC.editTweet = original
				}
				else if let original = sender as? PostOpTweet {
					destVC.draftTweet = original
				}
			}
			
// Forums
		case .showForumThread:
			if let destVC = segue.destination as? ForumThreadViewController, let thread = sender as? ForumThread {
				destVC.threadModel = thread
			}
			
		case .composeForumThread:
			if let destVC = segue.destination as? ForumComposeViewController, let threadModel = sender as? ForumThread {
				destVC.thread = threadModel
			}
			
		case .composeForumPost:
			if let destVC = segue.destination as? ForumComposeViewController, let threadModel = sender as? ForumThread {
				destVC.thread = threadModel
			}
			
		case .editForumPost:
			if let destVC = segue.destination as? ForumComposeViewController, let postModel = sender as? ForumPost {
				destVC.editPost = postModel
			}

		case .editForumPostDraft:
			if let destVC = segue.destination as? ForumComposeViewController, let postModel = sender as? PostOpForumPost {
				destVC.draftPost = postModel
			}
	
// Seamail
		case .showSeamailThread:
			if let destVC = segue.destination as? SeamailThreadViewController,
					let threadModel = sender as? SeamailThread {
				destVC.threadModel = threadModel
			}
			
		case .editSeamailThreadOp:
			if let destVC = segue.destination as? ComposeSeamailThreadVC, let thread = sender as? PostOpSeamailThread {
				destVC.threadToEdit = thread
			}
			
// Maps
		case .showRoomOnDeckMap:
			if let destVC = segue.destination as? DeckMapViewController, let location = sender as? String {
				destVC.pointAtRoomNamed(location)
			}

// Users
		case .userProfile:
			if let destVC = segue.destination as? UserProfileViewController, let username = sender as? String {
				destVC.modelUserName = username
			}
			
		case .editUserProfile:
			break
			
		case .modalLogin:
			if let destVC = segue.destination as? ModalLoginViewController, let package = sender as? LoginSegueWithAction {
				destVC.segueData = package
			}
			
// Settings
		case .postOperations: break
		
		case .fullScreenCamera, .cropCamera:
			break
			
		default: break 
		}
		
		return id
    }
    

}

extension BaseCollectionViewController: UIGestureRecognizerDelegate {

	func setupGestureRecognizer() {	
		let tapper = UILongPressGestureRecognizer(target: self, action: #selector(BaseCollectionViewController.cellTapped))
		tapper.minimumPressDuration = 0.05
		tapper.numberOfTouchesRequired = 1
		tapper.numberOfTapsRequired = 0
		tapper.allowableMovement = 10.0
		tapper.delegate = self
		tapper.name = "BaseCollectionViewController Long Press"
		collectionView.addGestureRecognizer(tapper)
		customGR = tapper
	}

	func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
		// need to call super if it's not our recognizer
		if gestureRecognizer != customGR {
			return false
		}
		let hitPoint = gestureRecognizer.location(in: collectionView)
		if !collectionView.point(inside:hitPoint, with: nil) {
			return false
		}
		
		// Only take the tap if the cell isn't already selected. This ensures taps on widgets inside the cell go through
		// once the cell is selected.
		if let path = collectionView.indexPathForItem(at: hitPoint), let cell = collectionView.cellForItem(at: path),
				let c = cell as? BaseCollectionViewCell, !c.privateSelected {
			if c.allowsSelection {
				return true
			}
		}
		
		
		return false
	}

	@objc func cellTapped(_ sender: UILongPressGestureRecognizer) {
		if sender.state == .began {
			if let indexPath = collectionView.indexPathForItem(at: sender.location(in:collectionView)) {
				tappedCell = collectionView.cellForItem(at: indexPath)
				tappedCell?.isHighlighted = true
			}
			else {
				tappedCell = nil
			}
		}
		guard let tappedCell = tappedCell else { return }
		
		if sender.state == .changed {
			tappedCell.isHighlighted = tappedCell.point(inside:sender.location(in: tappedCell), with: nil)
		}
		else if sender.state == .ended {
			if tappedCell.isHighlighted {				
				if let tc = tappedCell as? BaseCollectionViewCell {
					tc.privateSelectCell()
				}
			}
		} 
		
		if sender.state == .ended || sender.state == .cancelled || sender.state == .failed {
			tappedCell.isHighlighted = false
			
			// Stop the scroll view's odd scrolling behavior that happens when cell tap resizes the cell.
//			collectionView.setContentOffset(collectionView.contentOffset, animated: false)
		}
	}
	
}

