//
//  TwitarrTweetCell.swift
//  Kraken
//
//  Created by Chall Fry on 3/30/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit
import CoreData

@objc protocol TwitarrTweetCellBindingProtocol: FetchedResultsBindingProtocol {
	var isInteractive: Bool { get set }
}

@objc class TwitarrTweetCellModel: FetchedResultsCellModel, TwitarrTweetCellBindingProtocol {
	override class var validReuseIDDict: [String: BaseCollectionViewCell.Type ] { return [ "tweet" : TwitarrTweetCell.self ] }

	// If false, the tweet cell doesn't show text links, the like/reply/delete/edit buttons, nor does tapping the 
	// user thumbnail open a user profile panel.
	@objc dynamic var isInteractive: Bool = true
	
	override init(withModel: NSFetchRequestResult?, reuse: String, bindingWith: Protocol = TwitarrTweetCellBindingProtocol.self) {
		super.init(withModel: withModel, reuse: reuse, bindingWith: bindingWith)
	}
}


class TwitarrTweetCell: BaseCollectionViewCell, TwitarrTweetCellBindingProtocol, UITextViewDelegate {
	
// MARK: - Declarations
	@IBOutlet var titleLabel: UITextView!			// Author and timestamp
	@IBOutlet var likesLabel: UILabel!				
	@IBOutlet var tweetTextView: UITextView!
	@IBOutlet var postImage: UIImageView!
	@IBOutlet var 	postImageHeightConstraint: NSLayoutConstraint!
	@IBOutlet var userButton: UIButton!
	
	@IBOutlet var pendingOpsStackView: UIStackView!
	@IBOutlet var 	deleteQueuedView: UIView!
	@IBOutlet var 		deleteQueuedLabel: UILabel!
	@IBOutlet var 		cancelQueuedDeleteButton: UIButton!
	@IBOutlet var 	editQueuedView: UIView!
	@IBOutlet var 		editQueuedLabel: UILabel!
	@IBOutlet var 		cancelQueuedEditButton: UIButton!
	@IBOutlet var 	replyQueuedView: UIView!
	@IBOutlet var 		replyQueuedLabel: UILabel!
	@IBOutlet var 		viewQueuedRepliesButton: UIButton!
	@IBOutlet var 	reactionQueuedView: UIView!
	@IBOutlet var 		reactionQueuedLabel: UILabel!
	@IBOutlet var 		cancelQueuedReactionButton: UIButton!
	@IBOutlet var 	editStackView: UIView!
	@IBOutlet var 		editStack: UIStackView!
	@IBOutlet var   		likeButton: UIButton!
	@IBOutlet var 			editButton: UIButton!
	@IBOutlet var 			replyButton: UIButton!
	@IBOutlet var 			deleteButton: UIButton!

	private var opsByCurrentUserObservations: [EBNObservation?] = []

	@objc dynamic var loggedInUserHasLikedThis: Bool = false

	private static let cellInfo = [ "tweet" : PrototypeCellInfo("TwitarrTweetCell") ]
	override class var validReuseIDDict: [ String: PrototypeCellInfo] { return TwitarrTweetCell.cellInfo }
	
	var isInteractive: Bool = true

// MARK: - Methods

    var model: NSFetchRequestResult? {
    	didSet {
    		clearObservations()
    		if let tweetModel = model as? TwitarrPost, !tweetModel.isDeleted {
    			setup(from: tweetModel)
			}
			else if let postOpModel = model as? PostOpTweet, !postOpModel.isDeleted {
				setup(from: postOpModel)
			}
			else {
				titleLabel.attributedText = nil
				tweetTextView.attributedText = nil
				postImage.image = nil
				userButton.setBackgroundImage(nil, for: .normal)				
  				self.postImage.isHidden = true
				self.postImage.image = nil
  			}
		}
	}
  			
	func setup(from tweetModel: TwitarrPost) {
    		
		let titleAttrString = NSMutableAttributedString(string: "\(tweetModel.author.displayName), ", 
				attributes: authorTextAttributes())
		let timeString = StringUtilities.relativeTimeString(forDate: tweetModel.postDate())
		let timeAttrString = NSAttributedString(string: timeString, attributes: postTimeTextAttributes())
		titleAttrString.append(timeAttrString)
		titleLabel.attributedText = titleAttrString
		
		// Show the current number of likes this tweet has.
		addObservation(tweetModel.tell(self, when: "likeReaction.count") { observer, observed in
			if let likeCount = observed.likeReaction?.count, likeCount > 0 {
				observer.likesLabel.isHidden = false
				observer.likesLabel.text = "\(likeCount) 💛"
			}
			else {
				observer.likesLabel.isHidden = true
			}
		}?.execute())
		
		// Tweet text
		addObservation(tweetModel.tell(self, when: "text") { observer, observed in 		
			// Can the user tap on a link and open a filtered view?
			let addLinksToText = observer.viewController?.shouldPerformSegue(withIdentifier: "TweetFilter", 
					sender: observer) ?? false
	// Damascus is pretty good; really like Helvetica. Hoefler doesn't work here. Times New Roman isn't bad.
	// 
	//		let tweetTextAttrs: [NSAttributedString.Key : Any] = [ .font : UIFont(name: "Damascus", size: 16.0) as Any ]
	//		let tweetTextAttrs: [NSAttributedString.Key : Any] = [ .font : UIFont(name: "Helvetica", size: 17.0) as Any ]
	//		let tweetTextAttrs: [NSAttributedString.Key : Any] = [ .font : UIFont.systemFont(ofSize: 17.0) as Any ]
	//		let tweetTextAttrs: [NSAttributedString.Key : Any] = [ .font : UIFont(name: "HoeflerText-Regular", size: 16.0) as Any ]
	//		let tweetTextAttrs: [NSAttributedString.Key : Any] = [ .font : UIFont(name: "TimesNewRomanPSMT", size: 17.0) as Any ]
	//		let tweetTextAttrs: [NSAttributedString.Key : Any] = [ .font : UIFont(name: "Verdana", size: 15.0) as Any ]

			let tweetTextFont = UIFont(name: "TimesNewRomanPSMT", size: 17.0) ?? UIFont.preferredFont(forTextStyle: .body)
			let scaledTweetFont = UIFontMetrics(forTextStyle: .body).scaledFont(for: tweetTextFont)
			let tweetTextAttrs: [NSAttributedString.Key : Any] = [ .font : scaledTweetFont as Any ]

			let tweetTextWithLinks = StringUtilities.cleanupText(tweetModel.text, addLinks: addLinksToText)
			tweetTextWithLinks.addAttributes(tweetTextAttrs, range: NSRange(location: 0, length: tweetTextWithLinks.length))
			observer.tweetTextView.attributedText = tweetTextWithLinks

			let fixedWidth = observer.tweetTextView.frame.size.width
			let newSize = observer.tweetTextView.sizeThatFits(CGSize(width: fixedWidth, 
					height: CGFloat.greatestFiniteMagnitude))
			observer.tweetTextView.frame.size = CGSize(width: max(newSize.width, fixedWidth), height: newSize.height)
		}?.execute())
		
		// User Icon
		tweetModel.author.loadUserThumbnail()
		addObservation(tweetModel.author.tell(self, when:"thumbPhoto") { observer, observed in
			observed.loadUserThumbnail()
			observer.userButton.setBackgroundImage(observed.thumbPhoto, for: .normal)
			observer.userButton.setTitle("", for: .normal)
		}?.execute())
		
		// Photo, if one's attached
		addObservation(tweetModel.tell(self, when:"photoDetails.id") { observer, observed in
			if let photo = tweetModel.photoDetails {
				observer.postImage.isHidden = false
				if !observer.isPrototypeCell {
					ImageManager.shared.image(withSize:.medium, forKey: photo.id) { image in
						observer.postImage.image = image
					}
				}
			}
			else {
				observer.postImage.image = nil
				observer.postImage.isHidden = true
			}
		}?.execute())
		
		// Watch for login/out, so we can update like/unlike button state
		addObservation(CurrentUser.shared.tell(self, when: "loggedInUser") { observer, observed in
			let currentUserWroteThis = tweetModel.author.username == CurrentUser.shared.loggedInUser?.username
			observer.editButton.isHidden = !currentUserWroteThis
			observer.deleteButton.isHidden = !currentUserWroteThis
			observer.setLikeButtonState()
			
			// If we're logged in, observe a bunch of stuff
			if let username = CurrentUser.shared.loggedInUser?.username {

				// setup observation on 'replyOps' to watch for currentUser replying to this tweet.
				var observation = tweetModel.tell(self, when: "opsWithThisParent.count") { observer, observed in
					let replyCount = observed.opsWithThisParent?.reduce(0) { result, operation in 
						return operation.author.username == username ? result + 1 : result
					} ?? 0
					observer.setViewVisibility(view: observer.replyQueuedView, showIf: replyCount != 0)
					if replyCount == 1 {
						observer.replyQueuedLabel.text = "Reply pending"
					}
					else if replyCount > 1 {
						observer.replyQueuedLabel.text = "\(replyCount) replies pending"
					}
				}?.execute()
				observer.opsByCurrentUserObservations.append(observation)
				observer.addObservation(observation)
				
				if currentUserWroteThis { 
					// Observe "opsDeletingThisTweet" 
					observation = tweetModel.tell(self, when: "opsDeletingThisTweet") { observer, observed in
						let opCount = observed.opsDeletingThisTweet?.count ?? 0
						observer.setViewVisibility(view: observer.deleteQueuedView, showIf: opCount > 0)
					}?.execute()
					observer.opsByCurrentUserObservations.append(observation)
					observer.addObservation(observation)
				
					// Observe "opsEditingThisTweet" to find edits
					observation = tweetModel.tell(self, when: "opsEditingThisTweet") { observer, observed in
						observer.setViewVisibility(view: observer.editQueuedView, 
							showIf: observed.opsEditingThisTweet != nil)
					}?.execute()
					observer.opsByCurrentUserObservations.append(observation)
					observer.addObservation(observation)
				}
				else {
					observer.deleteQueuedView.isHidden = true
					observer.editQueuedView.isHidden = true
				}
			
				// setup observation on 'reactions' to watch for currentUser reacting to this tweet.
				observation = tweetModel.tell(self, when: "reactionDict.like.users.\(username)") { observer, observed in
					observer.setLikeButtonState()
					
//					if !observer.isPrototypeCell {
//						CollectionViewLog.debug("Hit for non-proto cell.")
//					}
				}?.execute()
				observer.opsByCurrentUserObservations.append(observation)
				observer.addObservation(observation)
				
				// and watch ReactionOps to look for pending reactions; show/hide the Pending Reaction card.
				observation = tweetModel.tell(self, when: "reactionOpsCount") { observer, observed in
					if let likeReaction = tweetModel.getPendingUserReaction("like") {
						observer.setViewVisibility(view: observer.reactionQueuedView, showIf: true)
						observer.reactionQueuedLabel.text = likeReaction.isAdd ? "\"Like\" pending" : "\"Unlike\" pending"
						observer.likeButton.isEnabled = false
					}
					else {
						observer.setViewVisibility(view: observer.reactionQueuedView, showIf: false)
						observer.likeButton.isEnabled = true
					}
				}?.execute()
				observer.opsByCurrentUserObservations.append(observation)
				observer.addObservation(observation)
			}
			else {
				// Nobody's logged in. Hide all the queued action views, don't bother observing CurrentUser things.
				observer.opsByCurrentUserObservations.forEach { observation in 
					observer.removeObservation(observation)
				}
				observer.deleteQueuedView.isHidden = true
				observer.editQueuedView.isHidden = true
				observer.replyQueuedView.isHidden = true
				observer.reactionQueuedView.isHidden = true
				observer.likeButton.isEnabled = true
			}
		}?.execute())
		
		titleLabel.textContainerInset = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
		tweetTextView.textContainerInset = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
	}
	
	func setup(from postOpModel: PostOpTweet) {
		let titleAttrString = NSMutableAttributedString(string: "\(postOpModel.author.displayName), ", 
				attributes: authorTextAttributes())
		let timeString = "In the near future"
		let timeAttrString = NSAttributedString(string: timeString, attributes: postTimeTextAttributes())
		titleAttrString.append(timeAttrString)
		titleLabel.attributedText = titleAttrString
		
		likesLabel.isHidden = true

		addObservation(postOpModel.tell(self, when:"text") { observer, observed in
			observer.tweetTextView.attributedText = StringUtilities.cleanupText(observed.text, addLinks: false)
		}?.execute())
		let fixedWidth = tweetTextView.frame.size.width
		let newSize = tweetTextView.sizeThatFits(CGSize(width: fixedWidth, height: CGFloat.greatestFiniteMagnitude))
		tweetTextView.frame.size = CGSize(width: max(newSize.width, fixedWidth), height: newSize.height)

		postOpModel.author.loadUserThumbnail()
		addObservation(postOpModel.author.tell(self, when:"thumbPhoto") { observer, observed in
			observed.loadUserThumbnail()
			observer.userButton.setBackgroundImage(observed.thumbPhoto, for: .normal)
			observer.userButton.setTitle("", for: .normal)
		}?.execute())

		addObservation(postOpModel.tell(self, when:"image") { observer, observed in
			if let imageData = observed.image, let image = UIImage(data: imageData as Data) {
				observer.postImage.isHidden = false
				observer.postImage.image = image
				observer.cellSizeChanged()
			}
			else {
				observer.postImage.image = nil
				observer.postImage.isHidden = true
				observer.cellSizeChanged()
			}
		}?.execute())
		
		deleteQueuedView.isHidden = true
		editQueuedView.isHidden = true
		replyQueuedView.isHidden = true
		reactionQueuedView.isHidden = true
		likeButton.isHidden = true
		replyButton.isHidden = true
				
		titleLabel.textContainerInset = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
		tweetTextView.textContainerInset = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
	}
	
	override func awakeFromNib() {
		super.awakeFromNib()
		pendingOpsStackView.isHidden = true				// In case the xib didn't leave this hidden

		// Font styling
		likesLabel.styleFor(.body)
		userButton.styleFor(.body)
		deleteQueuedLabel.styleFor(.body)
		cancelQueuedDeleteButton.styleFor(.body)
		editQueuedLabel.styleFor(.body)
		cancelQueuedEditButton.styleFor(.body)
		replyQueuedLabel.styleFor(.body)
		viewQueuedRepliesButton.styleFor(.body)
		reactionQueuedLabel.styleFor(.body)
		cancelQueuedReactionButton.styleFor(.body)
		likeButton.styleFor(.body)
		editButton.styleFor(.body)
		replyButton.styleFor(.body)
		deleteButton.styleFor(.body)
		
		tweetTextView.adjustsFontForContentSizeCategory = true

		// Every 10 seconds, update the post time (the relative time since now that the post happened).
		NotificationCenter.default.addObserver(forName: RefreshTimers.TenSecUpdateNotification, object: nil,
				queue: nil) { [weak self] notification in
    		if let self = self, let tweetModel = self.model as? TwitarrPost, !tweetModel.isDeleted {
				let titleAttrString = NSMutableAttributedString(string: "\(tweetModel.author.displayName), ", 
						attributes: self.authorTextAttributes())
				let timeString = StringUtilities.relativeTimeString(forDate: tweetModel.postDate())
				let timeAttrString = NSAttributedString(string: timeString, attributes: self.postTimeTextAttributes())
				titleAttrString.append(timeAttrString)
				self.titleLabel.attributedText = titleAttrString
			}
		}
	}
	
	// Prototype cells have difficulty figuring out their layout while animating.
	func setViewVisibility(view: UIView, showIf: Bool) {
		if showIf != view.isHidden { return }
		if isPrototypeCell {
			view.isHidden = !showIf
		}
		else {
			UIView.animate(withDuration: 0.3) {
				view.isHidden = !showIf
			}
			if privateSelected {
				cellSizeChanged()
			}
		}
	}
	
	func setLikeButtonState() {
		guard let currentUser = CurrentUser.shared.loggedInUser, let tweetModel = model as? TwitarrPost else {
			likeButton.setTitle("Like", for: .normal)
			return
		}
		
		// If the current logged in user already likes this tweet, set the like button to unlike
		if let likeReaction = tweetModel.reactionDict?["like"] as? Reaction {
			if likeReaction.users.contains(where: { user in return user.username == currentUser.username }) {
				likeButton.setTitle("Unlike", for: .normal)
			}
		}
		else {
			likeButton.setTitle("Like", for: .normal)
		}
//		if !self.isPrototypeCell {
//			CollectionViewLog.debug("like button state change:", ["Title" : self.likeButton.titleLabel!.text,
//					"index" : self.dataSource?.collectionView?.indexPath(for: self)])
//		}
	}
	
	override var privateSelected: Bool {
		didSet {
			if !isPrototypeCell, privateSelected == oldValue { return }
			
			var newImageHeight: CGFloat = 200.0
			if privateSelected, let tweetModel = model as? TwitarrPost, let photoDetails = tweetModel.photoDetails {
				newImageHeight = postImage.bounds.width / photoDetails.aspectRatio
			}
			if isPrototypeCell {
				pendingOpsStackView.isHidden = !privateSelected
				postImageHeightConstraint.constant = newImageHeight
			}
			else {
				UIView.animate(withDuration: 0.3) {
					self.pendingOpsStackView.isHidden = !self.privateSelected
					self.postImageHeightConstraint.constant = newImageHeight
				}
				cellSizeChanged()
			}
			contentView.backgroundColor = privateSelected ? UIColor(named: "Cell Background Selected") : 
					UIColor(named: "Cell Background")
		}
	}
	
	var highlightAnimation: UIViewPropertyAnimator?
	override var isHighlighted: Bool {
		didSet {
			if let oldAnim = highlightAnimation {
				oldAnim.stopAnimation(true)
			}
			let anim = UIViewPropertyAnimator(duration: 0.2, curve: .easeInOut) {
				self.contentView.backgroundColor = self.isHighlighted || self.privateSelected ? 
						UIColor(named: "Cell Background Selected") : UIColor(named: "Cell Background")
			}
			anim.isUserInteractionEnabled = true
			anim.isInterruptible = true
			anim.startAnimation()
			highlightAnimation = anim
		}
	}
	
	func authorTextAttributes() -> [ NSAttributedString.Key : Any ] {
		let metrics = UIFontMetrics(forTextStyle: .body)
		let baseFont = UIFont(name:"Helvetica-Bold", size: 14) ?? UIFont.preferredFont(forTextStyle: .body)
		let authorFont = metrics.scaledFont(for: baseFont)
		let result: [NSAttributedString.Key : Any] = [ .font : authorFont as Any, 
				.foregroundColor : UIColor(named: "Kraken Username Text") as Any ]
		return result
	}
	
	func postTimeTextAttributes() -> [ NSAttributedString.Key : Any ] {
		let metrics = UIFontMetrics(forTextStyle: .body)
		let baseFont = UIFont(name:"Georgia-Italic", size: 14) ?? UIFont.preferredFont(forTextStyle: .body)
		let postTimeFont = metrics.scaledFont(for: baseFont)
		let postTimeColor = UIColor(named: "Kraken Secondary Text")
		let result: [NSAttributedString.Key : Any] = [ .font : postTimeFont as Any, 
				.foregroundColor : postTimeColor as Any ]
		return result
	}
	
	
// MARK: Actions

	// Handler for tapping on linktext. The textView is non-editable.
	func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange, 
			interaction: UITextItemInteraction) -> Bool {
 //		UIApplication.shared.open(URL, options: [:])
 		guard isInteractive else { return false }
 		viewController?.performSegue(withIdentifier: "TweetFilter", sender: URL.absoluteString)
        return false
    }
        
   	@IBAction func showUserProfile() {
 		guard isInteractive else { return }
   		if let tweetModel = model as? TwitarrPost {
   			let userName = tweetModel.author.username
   			viewController?.performSegue(withIdentifier: "UserProfile", sender: userName)
		}
   	}
   	
// MARK: Buttons in toolbar
   	
   	@IBAction func likeButtonTapped() {
 		guard isInteractive else { return }
   		guard let tweetModel = model as? TwitarrPost else { return } 
   		var alreadyLikesThis = false
		if let currentUser = CurrentUser.shared.loggedInUser,
				let likeReaction = tweetModel.reactionDict?["like"] as? Reaction,
				likeReaction.users.contains(where: { user in return user.username == currentUser.username }) {
			alreadyLikesThis = true
		}

		if !CurrentUser.shared.isLoggedIn() {
 			let seguePackage = LoginSegueWithAction(promptText: "In order to like this post, you'll need to log in first.",
 					loginSuccessAction: { tweetModel.setReaction("like", to: !alreadyLikesThis) }, loginFailureAction: nil)
  			viewController?.performSegue(withIdentifier: "ModalLogin", sender: seguePackage)
   		}
   		else {
    		if let tweetModel = model as? TwitarrPost {
    			tweetModel.setReaction("like", to: !alreadyLikesThis)
    		}
   		}
   	}
   	
	@IBAction func replyButtonTapped() {
 		guard isInteractive else { return }
   		guard let tweetModel = model as? TwitarrPost else { return } 
		viewController?.performSegue(withIdentifier: "ComposeReplyTweet", sender: tweetModel)
	}
  	
	@IBAction func editButtonTapped() {
 		guard isInteractive else { return }
   		if let tweetModel = model as? TwitarrPost {
			viewController?.performSegue(withIdentifier: "EditTweet", sender: tweetModel)
		}
		else if let tweetOpModel = model as? PostOpTweet {
			viewController?.performSegue(withIdentifier: "EditTweet", sender: tweetOpModel)
		}
	}
	
	@IBAction func eliteDeleteTweetButtonTapped() {
 		guard isInteractive else { return }
 		
 		var deleteConfirmationMessage: String
 		switch model {
 		case is TwitarrPost: deleteConfirmationMessage = "Are you sure you want to delete this post?"
 		case is PostOpTweet: deleteConfirmationMessage = "This draft post hasn't been delivered to the server yet. Delete it?"
   		default: deleteConfirmationMessage = ""
   		}
   		
   		let alert = UIAlertController(title: "Delete Confirmation", message: deleteConfirmationMessage, 
   				preferredStyle: .alert) 
		alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: "Cancel action"), 
				style: .cancel, handler: nil))
		alert.addAction(UIAlertAction(title: NSLocalizedString("Delete", comment: "Default action"), 
				style: .destructive, handler: eliteDeleteTweetConfirmationComplete))
		
		viewController?.present(alert, animated: true, completion: nil)
	}
	
	func eliteDeleteTweetConfirmationComplete(_ action: UIAlertAction) {
   		if let tweetModel = model as? TwitarrPost {
			tweetModel.addDeleteTweetOp()
		}
		else if let postOpModel = model as? PostOpTweet {
			PostOperationDataManager.shared.remove(op: postOpModel)
		}
	}
	
// MARK: Buttons in pending state change views
	
	
   	@IBAction func cancelDeleteOpButtonTapped() {
 		guard isInteractive else { return }
   		guard let tweetModel = model as? TwitarrPost else { return } 
   		tweetModel.cancelDeleteOp()   		
   	}
		
   	@IBAction func cancelEditOpButtonTapped() {
 		guard isInteractive else { return }
   		guard let tweetModel = model as? TwitarrPost else { return } 
   		tweetModel.cancelEditOp()   		
   	}
		
   	@IBAction func viewPendingRepliesButtonTapped() {
 		guard isInteractive else { return }
   		guard let tweetModel = model as? TwitarrPost else { return } 
		viewController?.performSegue(withIdentifier: "PendingReplies", sender: tweetModel)
   	}
		
   	@IBAction func cancelReactionOpButtonTapped() {
 		guard isInteractive else { return }
   		guard let tweetModel = model as? TwitarrPost else { return } 
   		tweetModel.cancelReactionOp("like")   		
   	}
		
}



// "<a class=\"tweet-url username\" href=\"#/user/profile/kvort\">@kvort</a> Okay. This is a reply."
