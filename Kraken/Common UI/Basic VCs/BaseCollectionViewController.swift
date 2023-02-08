//
//  BaseCollectionViewController.swift
//  Kraken
//
//  Created by Chall Fry on 4/27/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit

// The raw values for these enums are the Storyboard Segue Identifiers. 
enum GlobalKnownSegue: String {
	case dismiss =					"dismiss"
	case dismissCamera =			"dismissCamera"
	
	case modalLogin = 				"ModalLogin"
	case reportContent = 			"ReportContent"

	case twitarrRoot = 				"TwitarrRoot"
	case tweetFilter = 				"TweetFilter"
	case showLikeOptions = 			"LikesPopover"
	case pendingReplies = 			"PendingReplies"
	case composeReplyTweet = 		"ComposeReplyTweet"
	case editTweet = 				"EditTweet"
	case editTweetOp = 				"EditTweetOp"
	case composeTweet = 			"ComposeTweet"
	case showUserTweets = 			"ShowUserTweets"
	case showUserMentions = 		"ShowUserMentions"
	
	case forumsRoot = 				"ForumsRoot"
	case showForumCategory = 		"ShowForumCategory"
	case showForumThread = 			"ShowForumThread"
	case composeForumThread = 		"ComposeForumThread"
	case composeForumPost = 		"ComposeForumPost"
	case editForumPost = 			"EditForumPost"
	case editForumPostDraft = 		"EditForumPostDraft"
	
	case seamailRoot = 				"SeamailRoot"
	case showSeamailThread = 		"ShowSeamailThread"
	case editSeamailThreadOp = 		"EditSeamailThreadOp"
	case seamailManageMembers = 	"SeamailManageMenbers"

	case eventsRoot = 				"EventsRoot"
	
	case lfgRoot = 					"LFGRoot"
	case lfgCreateEdit = 			"LFGCreate"
	
	case deckMapRoot =				"DeckMapRoot"
	case showRoomOnDeckMap = 		"ShowRoomOnDeckMap"
	
	case karaokeRoot =				"KaraokeRoot"
	case gamesRoot =				"GamesRoot"
	case scrapbookRoot =			"ScrapbookRoot"
	case lighterMode =				"RockBalladMode"
	case pirateAR =					"PirateARCamera"
	
	case settingsRoot = 			"SettingsRoot"
	case postOperations =			"PostOperations"
	case about = 					"AboutViewController"
	case twitarrHelp = 				"TwitarrHelp"

	case userProfile_Name = 		"UserProfile_Name"
	case userProfile_User = 		"UserProfile"
	case editUserProfile = 			"EditUserProfile"
	case initiatePhoneCall = 		"InitiatePhoneCall"
	case activePhoneCall = 			"ActivePhoneCall"
	
	case fullScreenCamera = 		"fullScreenCamera"
	case cropCamera = 				"cropCamera"
	
	var senderType: Any.Type {
		switch self {
		case .dismiss: return Any.self
		case .dismissCamera: return Data?.self
		
		case .modalLogin: return LoginSegueWithAction.self
		case .reportContent: return KrakenManagedObject.self

		case .twitarrRoot: return Void.self
		case .tweetFilter: return TwitarrFilterPack.self
		case .showLikeOptions: return LikeTypePopupSegue.self
		case .pendingReplies: return TwitarrPost.self
		case .composeReplyTweet: return Int64.self
		case .editTweet: return TwitarrPost.self
		case .editTweetOp: return PostOpTweet.self
		case .composeTweet: return Void.self
		case .showUserTweets: return String.self
		case .showUserMentions: return String.self
		
		case .forumsRoot: return Void.self
		case .showForumCategory: return ForumCategory.self
		case .showForumThread: return Any.self					// ForumThread or UUID of a thread
		case .composeForumThread: return ForumCategory.self 
		case .composeForumPost: return ForumThread.self 
		case .editForumPost: return ForumPost.self 
		case .editForumPostDraft: return PostOpForumPost.self 
		
		case .seamailRoot: return Void.self
		case .showSeamailThread: return SeamailThread.self
		case .editSeamailThreadOp: return PostOpSeamailThread.self
		case .seamailManageMembers: return SeamailThread.self
		
		case .eventsRoot: return String.self
		
		case .lfgRoot: return Void.self
		case .lfgCreateEdit: return Any.self
		
		case .deckMapRoot: return Void.self
		case .showRoomOnDeckMap: return String.self
		
		case .karaokeRoot: return Void.self
		case .gamesRoot: return Void.self
		case .scrapbookRoot: return Void.self
		case .lighterMode: return Void.self
		case .pirateAR: return BaseCollectionViewCell.self

		case .settingsRoot: return Void.self
		case .postOperations: return Any.self
		case .about: return Void.self
		case .twitarrHelp: return ServerTextFileSeguePackage.self

		case .userProfile_Name: return String.self
		case .userProfile_User: return KrakenUser.self
		case .editUserProfile: return PostOpUserProfileEdit.self
		case .initiatePhoneCall: return Void.self
		case .activePhoneCall: return Void.self
		
		case .fullScreenCamera: return BaseCollectionViewCell.self
		case .cropCamera: return BaseCollectionViewCell.self

//		@unknown default: return Void.self
		}
	}
	
	func segueName() -> String {
		switch self {
			case .userProfile_Name: return "UserProfile"
			case .userProfile_User: return "UserProfile"
			default: return rawValue
		}
	}
}

class BaseCollectionViewController: UIViewController {
	@IBOutlet var collectionView: UICollectionView!
	@objc dynamic var activeTextEntry: UITextInput?
		
	var keyboardCanceler: UILongPressGestureRecognizer?
	var enableKeyboardCanceling = true
	var isKeyboardVisible: Bool = false
	var indexPathToScrollToVisible: IndexPath?
	var allowTransparency = true
	
	// Properties of the Image Viewer. This is a covering view that shows an image. Other UI elements can call showImageInOverlay()
	// on this VC and we'll show the provided image in a translucent overlay over the regular content.
	var photoBeingShown: UIImage? 
	var photoCoveringView: UIVisualEffectView?
	var 	photoZoomView: UIScrollView?
	var 		photoOverlayView: UIImageView?
	var photoShareButton: UIButton?
	var photoHeightConstraint: NSLayoutConstraint?
	var photoWidthConstraint: NSLayoutConstraint?
	var zoomViewWidthConstraint: NSLayoutConstraint?
	var zoomViewHeightConstraint: NSLayoutConstraint?
	
	// Subclasses should set this to the list of global segue enums (see above) they actually support
	var knownSegues: Set<GlobalKnownSegue> { Set() }

// MARK: Methods	
    override func viewDidLoad() {
        super.viewDidLoad()
        
		keyboardCanceler = UILongPressGestureRecognizer(target: self, action: #selector(BaseCollectionViewController.cancelerTapped(_:)))
		keyboardCanceler!.minimumPressDuration = 0.2
		keyboardCanceler!.numberOfTouchesRequired = 1
		keyboardCanceler!.numberOfTapsRequired = 0
		keyboardCanceler!.allowableMovement = 10.0
     	keyboardCanceler!.cancelsTouchesInView = false
     	keyboardCanceler!.delegate = self
		keyboardCanceler!.name = "BaseCollectionViewController Keyboard Hider"
	 	view.addGestureRecognizer(keyboardCanceler!)
               
        collectionView.collectionViewLayout = VerticalLayout()
 
		NotificationCenter.default.addObserver(self, selector: #selector(BaseCollectionViewController.keyboardWillShow(notification:)), 
				name: UIResponder.keyboardDidShowNotification, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(BaseCollectionViewController.keyboardDidShowNotification(notification:)), 
				name: UIResponder.keyboardDidShowNotification, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(BaseCollectionViewController.keyboardWillHide(notification:)), 
				name: UIResponder.keyboardDidHideNotification, object: nil)

		// CoreMotion is our own device motion manager, a singleton for the whole app. We use it here to get device
		// orientation without allowing our UI to actually rotate.
		NotificationCenter.default.addObserver(self, selector: #selector(BaseCollectionViewController.deviceRotationNotification), 
				name: CoreMotion.OrientationChanged, object: nil)
						
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
				// Doing an equality check first because setting contentInset causes a layout invalidate, which is annoying.
				let newInsets = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
				if newInsets != observer.collectionView.contentInset {
					observer.collectionView.contentInset = newInsets
				}
			}
		}?.execute()
		
		// Set the background color to clear in Deep Sea Mode
		Settings.shared.tell(self, when: "uiDisplayStyle") { observer, observed in 
			UIView.animate(withDuration: 0.3) {
				self.view.backgroundColor = observed.uiDisplayStyle == .deepSeaMode ? UIColor.clear : 
						UIColor(named: "VC Background")
			}
		}
	}
	
	override func viewDidAppear(_ animated: Bool) {
		if allowTransparency {
			UIView.animate(withDuration: 0.3) {
				self.view.backgroundColor = Settings.shared.uiDisplayStyle == .deepSeaMode ? UIColor.clear : 
						UIColor(named: "VC Background")
			}
		}
	}
	
	func showImageInOverlay(image: UIImage) {
		if let win = view.window {
			CoreMotion.shared.start(forClient: "ImageOverlay", updatesPerSec: 2)
			photoBeingShown = image

			// Set up the visual effect view that covers the regular content
			var effectStyle = UIBlurEffect.Style.dark
			if #available(iOS 13.0, *) {
				effectStyle = .systemUltraThinMaterialDark
			}
			let coveringView = UIVisualEffectView(effect: nil)
			photoCoveringView = coveringView
			coveringView.frame = win.frame
			win.addSubview(coveringView)
			UIView.animate(withDuration: 1) {
				coveringView.effect = UIBlurEffect(style: effectStyle)
			}
						
			// Scroll view goes inside the covering view, centered.
			let zoomView = UIScrollView()
			photoZoomView = zoomView
			zoomView.delegate = self
			zoomView.translatesAutoresizingMaskIntoConstraints = false
			zoomView.showsVerticalScrollIndicator = false
			zoomView.showsHorizontalScrollIndicator = false
			zoomView.contentInsetAdjustmentBehavior = .never
			coveringView.contentView.addSubview(zoomView)
			let zoomViewWidthConstraint = zoomView.widthAnchor.constraint(lessThanOrEqualToConstant: coveringView.contentView.bounds.size.width)
			let zoomViewHeightConstraint = zoomView.heightAnchor.constraint(lessThanOrEqualToConstant: coveringView.contentView.bounds.size.height)
			var constraints = [
					zoomView.centerYAnchor.constraint(equalTo: coveringView.contentView.centerYAnchor),
					zoomView.centerXAnchor.constraint(equalTo: coveringView.contentView.centerXAnchor),
					zoomViewWidthConstraint,
					zoomViewHeightConstraint]
			NSLayoutConstraint.activate(constraints)
			self.zoomViewWidthConstraint = zoomViewWidthConstraint
			self.zoomViewHeightConstraint = zoomViewHeightConstraint
			
			// Image view goes inside the scrollview. This view gets special constraints. 
			// It pins to the scrollView, which is normal, but it also sets the height/width of the scrollView to
			// match the (zoomed) frame of the overlayImageView. Priority of these is 999, and they get updated in
			// scrollViewDidZoom as the zoom changes. In handleDeviceRotation() we set other constraints (@1000) on the 
			// scrollView to be <= the height/width of the covering view (essentially, screen size). 
			// Thus, as you zoom out the scrollView centers until it is the height/width of the screen, then allows 
			// panning. That is, the scrollView size == the image size if less than screen size, else scrollView size ==
			// screen size, and the content size continues growing, and you can pan.
			let overlayImageView = UIImageView()
			photoOverlayView = overlayImageView
			overlayImageView.translatesAutoresizingMaskIntoConstraints = false
			zoomView.addSubview(overlayImageView)
			let photoHeightConstraint = zoomView.heightAnchor.constraint(equalToConstant: image.size.height)
			photoHeightConstraint.priority = UILayoutPriority(999.0)
			self.photoHeightConstraint = photoHeightConstraint
			let photoWidthConstraint = zoomView.widthAnchor.constraint(equalToConstant: image.size.width)
			photoWidthConstraint.priority = UILayoutPriority(999.0)
			self.photoWidthConstraint = photoWidthConstraint
			constraints = [
					overlayImageView.leadingAnchor.constraint(equalTo: zoomView.leadingAnchor),
					overlayImageView.trailingAnchor.constraint(equalTo: zoomView.trailingAnchor),
					overlayImageView.bottomAnchor.constraint(equalTo: zoomView.bottomAnchor),
					overlayImageView.topAnchor.constraint(equalTo: zoomView.topAnchor),
					photoHeightConstraint,
					photoWidthConstraint
					]
			NSLayoutConstraint.activate(constraints)
			overlayImageView.image = image
			
			handleDeviceRotation(animated: false)
			
			// Tap gesture exits photo view
			let photoTap = UITapGestureRecognizer(target: self, action: #selector(BaseCollectionViewController.photoTapped(_:)))
			coveringView.contentView.addGestureRecognizer(photoTap)
			
			// Share Button opens the UIActivity sheet.
			let shareButton = UIButton(type: .system)
			shareButton.translatesAutoresizingMaskIntoConstraints = false
			shareButton.setTitle("", for: .normal)
			shareButton.setImage(UIImage(named: "square.and.arrow.up"), for: .normal)
			shareButton.setImage(UIImage(named: "square.and.arrow.up.fill"), for: .highlighted)
			shareButton.addTarget(self, action: #selector(shareButtonTapped), for: .touchUpInside)
			shareButton.imageView?.tintColor = UIColor(named: "Icon Foreground")
			coveringView.contentView.addSubview(shareButton)
			constraints = [
					shareButton.leadingAnchor.constraint(equalTo: coveringView.leadingAnchor, constant: 20),
					shareButton.bottomAnchor.constraint(equalTo: coveringView.safeAreaLayoutGuide.bottomAnchor) ]
			NSLayoutConstraint.activate(constraints)
			photoShareButton = shareButton
		}
	}
	
	// on iPhone, viewControllers are all portrait only. We manually watch for device rotation and rotate the photo
	// view.
	@objc func deviceRotationNotification(_ notification: Notification) {
		if UIDevice.current.userInterfaceIdiom == .phone {
			handleDeviceRotation(animated: true)
		}
	}
	
	// on iPad, we can get view rotations while showing the photo view.
	override func viewDidLayoutSubviews() {
		if let coveringView = photoCoveringView {
			coveringView.removeFromSuperview()
			photoOverlayView = nil
			photoCoveringView = nil
			if let photo = photoBeingShown {
				showImageInOverlay(image: photo)
			}
		}
	}
	
	
	// These VCs don't support landscape; only portrait mode. However, the photo view overlay does need to rotate to 
	// show landscape mode, which is what this crazy code does.
	func handleDeviceRotation(animated: Bool) {
		guard let zoomView = self.photoZoomView else { return }
		guard let coveringView = self.photoCoveringView else { return }
		guard let photo = self.photoBeingShown else { return }
		guard let win = view.window else { return }
				
		var rotationAngle: CGFloat = 0.0
		var isLandscape = false
		switch CoreMotion.shared.currentDeviceOrientation {
			case .portrait, .faceUp, .unknown: rotationAngle = 0.0
			case .landscapeLeft: rotationAngle = 90.0; isLandscape = true
			case .landscapeRight: rotationAngle = -90.0; isLandscape = true
			case .portraitUpsideDown, .faceDown: rotationAngle = 180.0
			default: rotationAngle = 0.0
		}
		let xform = CGAffineTransform(rotationAngle: CGFloat.pi * rotationAngle / 180.0)

		// ScaleFactor is the scaling to apply to the image to get .scaleAspectFit behavior.
		let imageSize = photo.size
		let scaleFactor: CGFloat = isLandscape ? min(win.bounds.size.width / imageSize.height, win.bounds.size.height / imageSize.width) :
				min(win.bounds.size.width / imageSize.width, win.bounds.size.height / imageSize.height)
		
		// Depending on orientation, constrain the zoom view to the coveringView's size. Note that we use constant
		// constraints here, as for 'landscape' we rotate the zoomView by 90 degrees.
		let coveringViewSize = coveringView.contentView.bounds.size
		zoomViewWidthConstraint?.constant = isLandscape ? coveringViewSize.height : coveringViewSize.width
		zoomViewHeightConstraint?.constant = isLandscape ? coveringViewSize.width : coveringViewSize.height

		zoomView.minimumZoomScale = scaleFactor
		zoomView.maximumZoomScale = scaleFactor * 3.0
		zoomView.setNeedsLayout()
		zoomView.layoutIfNeeded()
		zoomView.setZoomScale(scaleFactor, animated: animated)
		
		if UIDevice.current.userInterfaceIdiom == .phone {
			if animated {
				UIViewPropertyAnimator.runningPropertyAnimator(withDuration: 0.3, delay: 0, options: [], animations: {
					zoomView.transform = xform
				})
			}
			else {
				zoomView.transform = xform
			}
		}
	}
	
	override func viewWillLayoutSubviews() {
		super.viewWillLayoutSubviews()

		// I'm pretty sure this isn't the right way to do this. However, it's the first thing that works, after several
		// failed attempts. The issue is, we need to either resize or invalidate these cells when the collectionView
		// width changes, else the CV layout gets angry that cells are wider than the CV. I've tried:
		//		- Invalidating the layout in several places, including viewWillLayoutSubviews, viewWillTransition.
		//		- Reloading the CV, again in several places.
		//		- Changing how we make cells full-width
		//		- Changing constraint priorities
		//
		// Note that at the time this is called, the VC's view has been resized but the CV's view hasn't. We just assume
		// the CV will get laid out with the same width as the VC's view.
		for cell in collectionView.visibleCells {
			if let baseCell = cell as? BaseCollectionViewCell {
				baseCell.collectionViewSizeChanged(to: view.frame.size)
				baseCell.setNeedsLayout()
				baseCell.layoutIfNeeded()
			}
		}
	}

	@objc func shareButtonTapped() {
		guard let photo = self.photoBeingShown else { return }
		guard let shareButton = photoShareButton else { return }
		let activityViewController = UIActivityViewController(activityItems: [photo], applicationActivities: nil)
		present(activityViewController, animated: true, completion: {})
		if let popper = activityViewController.popoverPresentationController {
			popper.sourceView = self.view
			popper.sourceRect = shareButton.frame
		}
	}
	
	// Dismisses the photo overlay view.
	@objc func photoTapped(_ sender: UITapGestureRecognizer) {
		if let coveringView = photoCoveringView {
			coveringView.removeFromSuperview()
			photoBeingShown = nil
			photoOverlayView = nil
			photoCoveringView = nil
			CoreMotion.shared.stop(client: "ImageOverlay")
		}
	}
        
    @objc func keyboardWillShow(notification: NSNotification) {
    	isKeyboardVisible = true
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
    	isKeyboardVisible = false
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
	
	// MARK: Navigation

	// FFS Apple should provide this as part of their API. This is used by collectionView cells to see if they're
	// attached to a ViewController that supports launching a given segue; if not they generally hide/disable buttons.
	// This only matters if you make cells that are usable in multiple VCs, which Apple apparently recommends against --
	// a recommendation about as useful as Q-Tips recommending you not use Q-Tips in your ears.
	func canPerformSegue(_ segue: GlobalKnownSegue) -> Bool {
		return knownSegues.contains(segue)
	}
	
	func segueOrNavToLink(_ link: String) {
		// Open externally if it's not our link
		if let url = URL(string: link), !["twitarr.com", "joco.hollandamerica.com", Settings.shared.settingsBaseURL.host]
				.contains(url.host ?? "nohostfoundasdfasfasf") {
			UIApplication.shared.open(url)
			return
		}
	
		let packet = GlobalNavPacket(from: self, url: link)
		// If the current VC can perform the segue, do it
		if let segueType = packet.segue, canPerformSegue(segueType) {
			performKrakenSegue(segueType, sender: packet.sender)
		}
		else {
			// Use global nav to get to the dest.
			ContainerViewController.shared?.globalNavigateTo(packet: packet)
		}
	}
	
	func performKrakenSegue(_ id: GlobalKnownSegue, sender: Any?) {
		guard canPerformSegue(id) else {
			let vcType = type(of: self)
			AppLog.error("VC \(vcType) doesn't claim to support segue \(id.rawValue)")
			return 
		}
		
		if sender is GlobalNavPacket {
			// If the dest VC is GlobalNavEnabled, it'll be able to handle this.
			performSegueWrapper(withIdentifier: id, sender: sender)
		}
		else if let senderValue = sender {
			let expectedType = id.senderType
			var typeIsValid =  type(of: senderValue) == expectedType || expectedType == Any.self
			if !typeIsValid {
				let seq = sequence(first: Mirror(reflecting: senderValue), next: { $0.superclassMirror })
				typeIsValid = seq.contains { $0.subjectType == expectedType }
			}
			
			if typeIsValid {
				performSegueWrapper(withIdentifier: id, sender: sender)
			}
		}
		else {
			// Always allow segues with nil senders. This doesn't mean prepare(for segue) will like it.
			performSegueWrapper(withIdentifier: id, sender: sender)
		}
	}
	
	func performSegueWrapper(withIdentifier id: GlobalKnownSegue, sender: Any?) {
		performSegue(withIdentifier: id.segueName(), sender: sender)
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
    	return prepareGlobalSegue(for: id, source: segue.source, destination: segue.destination, sender: sender)	
	}
    	
	@discardableResult func prepareGlobalSegue(for id: GlobalKnownSegue, source: UIViewController, 
			destination: UIViewController, sender: Any?) -> GlobalKnownSegue? {
    	
    	// If this is a global nav to a VC that can handle it, pass it on
    	if let packet = sender as? GlobalNavPacket, let destVC = destination as? GlobalNavEnabled {
    		destVC.globalNavigateTo(packet: packet)
    	}
    	
    	switch id {

// Twittar
		// A filtered view of the tweet stream. Used for text search, hashtag search, @username search, reply groups.
		case .tweetFilter:
			if let destVC = destination as? TwitarrViewController, let filter = sender as? TwitarrFilterPack {
				destVC.filterPack = filter
			}
				
		// PostOpTweets by this user, that are replies to a given tweet.
		case .pendingReplies:
			if let destVC = destination as? PendingTwitarrRepliesVC, let parent = sender as? TwitarrPost {
				destVC.parentTweet = parent
			}
			
		case .showLikeOptions:
			if let destVC = destination as? PostCellLikeVC, let package = sender as? LikeTypePopupSegue {
				destVC.segueData = package
				destination.preferredContentSize = CGSize(width: 150, height: 44)
				if let presentationController = destination.popoverPresentationController {
					presentationController.barButtonItem = nil
					presentationController.sourceView = package.button
					presentationController.delegate = self
				}
			}
			
		case .showUserMentions:
			if let destVC = destination as? TwitarrViewController, let filterString = sender as? String {
				destVC.filterPack = TwitarrFilterPack(author: nil, text: filterString)
			}
			
		case .showUserTweets:
			if let destVC = destination as? TwitarrViewController, let filterString = sender as? String {
				destVC.filterPack = TwitarrFilterPack(author: filterString, text: nil)
			}
			
		case .composeTweet: break
		
		case .composeReplyTweet:
			if let destVC = destination as? ComposeTweetViewController, let replyGroupID = sender as? Int64 {
				destVC.replyGroupID = replyGroupID
			}
			
		case .editTweet, .editTweetOp:
			if let destVC = destination as? ComposeTweetViewController {
				if let original = sender as? TwitarrPost {
					destVC.editTweet = original
				}
				else if let original = sender as? PostOpTweet {
					destVC.draftTweet = original
				}
			}
			
// Forums
		case .showForumCategory:
			if let destVC = destination as? ForumsCategoryViewController, let cat = sender as? ForumCategory {
				destVC.categoryModel = cat
			}
			
		case .showForumThread:
			if let destVC = destination as? ForumThreadViewController, let thread = sender as? ForumThread {
				destVC.threadModel = thread
			}
			if let destVC = destination as? ForumThreadViewController, let threadID = sender as? UUID {
				destVC.threadModelID = threadID
			}
			
		case .composeForumThread:
			if let destVC = destination as? ForumComposeViewController, let threadModel = sender as? ForumThread {
				destVC.thread = threadModel
			}
			else if let destVC = destination as? ForumComposeViewController, let catModel = sender as? ForumCategory {
				destVC.category = catModel
			}
			
		case .composeForumPost:
			if let destVC = destination as? ForumComposeViewController, let threadModel = sender as? ForumThread {
				destVC.thread = threadModel
			}
			
		case .editForumPost:
			if let destVC = destination as? ForumComposeViewController, let postModel = sender as? ForumPost {
				destVC.editPost = postModel
			}

		case .editForumPostDraft:
			if let destVC = destination as? ForumComposeViewController, let postModel = sender as? PostOpForumPost {
				destVC.draftPost = postModel
			}
	
// Seamail
		case .showSeamailThread:
			if let destVC = destination as? SeamailThreadViewController, let threadModel = sender as? SeamailThread {
				destVC.threadModel = threadModel
			}
			
		case .editSeamailThreadOp:
			if let destVC = destination as? ComposeSeamailThreadVC, let thread = sender as? PostOpSeamailThread {
				destVC.threadToEdit = thread
			}

		case .seamailManageMembers:
			if let destVC = destination as? ManageMembersVC, let thread = sender as? SeamailThread {
				destVC.threadModel = thread
			}
			
// LFG
		case .lfgCreateEdit:
			if let destVC = destination as? CreateLFGViewController{
				if let thread = sender as? SeamailThread {
					destVC.lfgModel = thread
				}
				else if let op = sender as? PostOpLFGCreate {
					destVC.opToEdit = op
				}
			}
// Events
		case .eventsRoot: break
			
			
// Maps
		case .showRoomOnDeckMap:
			if let destVC = destination as? DeckMapViewController, let location = sender as? String {
				destVC.pointAtRoomNamed(location)
			}

// Users
		case .userProfile_Name:
			if let destVC = destination as? UserProfileViewController, let username = sender as? String {
				destVC.modelUserName = username
			}
			
		case .userProfile_User:
			if let destVC = destination as? UserProfileViewController, let target = sender as? KrakenUser {
				destVC.modelKrakenUser = target
				destVC.modelUserName = target.username
			}
			
		case .editUserProfile:
			break
			
		case .modalLogin:
			if let destVC = destination as? ModalLoginViewController, let package = sender as? LoginSegueWithAction {
				destVC.segueData = package
				// Specify the presentation style so the ModalLogin VC can layout appropriately
				// The .automatic style maps to these values anyway, but the dest VC apparently can't know?
				if #available(iOS 13.0, *) {
					destVC.modalPresentationStyle = .pageSheet
				}
				else {
					destVC.modalPresentationStyle = .fullScreen
				}
			}

		case .reportContent:
			if let destVC = destination as? ReportContentViewController, let post = sender as? KrakenManagedObject {
				destVC.contentToReport = post
			}
			
// Settings
		case .postOperations: break
		
		case .fullScreenCamera, .cropCamera:
			break
			
		case .pirateAR:
			if let destVC = destination as? CameraViewController {
				destVC.pirateMode = true
			}
			
		case .twitarrHelp:
			if let destVC = destination as? ServerTextFileViewController, let package = sender as? ServerTextFileSeguePackage {
				destVC.package = package
			}
			
		default: break 
		}
		
		return id
    }
    
	// This is the unwind segue from the login modal. I believe every subclass that might use this should
	// implement it like this--therefore it's in the base class.
	@IBAction func dismissingLoginModal(_ segue: UIStoryboardSegue) {
		// Try to continue whatever we were doing before having to log in.
		if let loginVC = segue.source as? ModalLoginViewController {
			if CurrentUser.shared.isLoggedIn() {
				loginVC.segueData?.loginSuccessAction?()
			}
			else {
				loginVC.segueData?.loginFailureAction?()
			}
		}
	}	
}

// MARK: UIPopoverPresentationControllerDelegate
extension BaseCollectionViewController: UIPopoverPresentationControllerDelegate {
    func adaptivePresentationStyle(for controller: UIPresentationController, traitCollection: UITraitCollection) -> UIModalPresentationStyle {
        return .none
    }
}

// MARK: UIScrollViewDelegate
extension BaseCollectionViewController: UIScrollViewDelegate {
	func viewForZooming(in scrollView: UIScrollView) -> UIView? {
		if scrollView == photoZoomView {
			return photoOverlayView
		}
		return nil
	}
	
	func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
	}
	
	func scrollViewDidZoom(_ scrollView: UIScrollView) {
		photoHeightConstraint?.constant = photoOverlayView?.frame.size.height ?? 0
		photoWidthConstraint?.constant = photoOverlayView?.frame.size.width ?? 0
	}
}

// MARK: UIGestureRecognizerDelegate
extension BaseCollectionViewController: UIGestureRecognizerDelegate {

	func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
		if gestureRecognizer != keyboardCanceler {
			return false
		}
		if enableKeyboardCanceling && isKeyboardVisible {
			return true
		}
		
		return false
	}
	
//	func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, 
//			shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer) -> Bool {
//		return true		
//	}
	
//	func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, 
//			shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
//		return true		
//	}
	
//	func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
//		if gestureRecognizer == customGR && otherGestureRecognizer == collectionView.panGestureRecognizer {
//			return true
//		}
//		return false
//	}
//
	@objc func cancelerTapped(_ sender: UILongPressGestureRecognizer) {
//		if sender.state == .began {
//		}
		if sender.state == .changed {
		}
		else if sender.state == .ended {
			if (enableKeyboardCanceling) {
				view.endEditing(true)
			}
		} 
		
//		if sender.state == .ended || sender.state == .cancelled || sender.state == .failed {			
//		}
	}
}

