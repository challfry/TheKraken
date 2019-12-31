//
//  TwitarrTweetCell.swift
//  Kraken
//
//  Created by Chall Fry on 3/30/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit
import CoreData

@objc enum LikeOpKind: Int {
	case none
	case like
	case unlike
}

@objc protocol TwitarrTweetCellBindingProtocol: FetchedResultsBindingProtocol {

	var isInteractive: Bool { get set }
	
	var author: KrakenUser? { get set }
	var postTime: Date? { get set }
	
	var numLikes: Int32 { get set }
	var postText: String? { get set }
	var photos: [PhotoDetails]? { get set }
	var photoImages: [Data]? { get set }			// For ops, where there's no PhotoDetails yet.
	
	var loggedInUserIsAuthor: Bool { get set }		// False if no logged in user
	
	// Reply, Edit, Delete, Like
	var currentUserReplyOpCount: Int32 { get set }
	var currentUserHasDeleteOp: Bool { get set }
	var currentUserHasEditOp: Bool { get set }
	var currentUserReactOpCount: Int32 { get set }
	var currentUserHasLikeOp: LikeOpKind { get set }
	var currentUserLikesThis: Bool { get set }
	var canReply: Bool { get set }
	var canEdit: Bool { get set }
	var canDelete: Bool { get set }
	
	var isDeleted: Bool { get set }
	
	// 
	func linkTextTapped(link: String)
	func authorIconTapped()
	func likeButtonTapped()
	func replyButtonTapped()
	func editButtonTapped()
	func deleteButtonTapped()
	func cancelDeleteOpButtonTapped()
	func cancelEditOpButtonTapped()
	func viewPendingRepliesButtonTapped()
	func cancelReactionOpButtonTapped()
}

@objc class TwitarrTweetCellModel: FetchedResultsCellModel, TwitarrTweetCellBindingProtocol {	
	override class var validReuseIDDict: [String: BaseCollectionViewCell.Type ] { return [ "tweet" : TwitarrTweetCell.self ] }

	// If false, the tweet cell doesn't show text links, the like/reply/delete/edit buttons, nor does tapping the 
	// user thumbnail open a user profile panel.
	@objc dynamic var isInteractive: Bool = true
	
	dynamic var author: KrakenUser?
	dynamic var postTime: Date?
	
	dynamic var numLikes: Int32 = 0
	dynamic var postText: String?
	dynamic var photos: [PhotoDetails]?
	dynamic var photoImages: [Data]? 
	dynamic var loggedInUserIsAuthor: Bool = false		// False if no logged in user

	// Reply, Edit, Delete, Like
	dynamic var currentUserReplyOpCount: Int32 = 0
	dynamic var currentUserHasDeleteOp: Bool = false
	dynamic var currentUserHasEditOp: Bool = false
	dynamic var currentUserReactOpCount: Int32 = 0
	dynamic var currentUserHasLikeOp: LikeOpKind = .none
	dynamic var currentUserLikesThis: Bool = false
	dynamic var canReply: Bool = true
	dynamic var canEdit: Bool = true
	dynamic var canDelete: Bool = true

	dynamic var isDeleted: Bool = false
	
    override var model: NSFetchRequestResult? {
    	didSet {
    		clearObservations()
    		if let tweetModel = model as? TwitarrPost, !tweetModel.isDeleted {
    			setup(from: tweetModel)
			}
			else {
				author = nil
				postTime = nil
				postText = nil				
  				photos = nil
  				isDeleted = true
  				shouldBeVisible = false
			}
		}
	}
	
	var viewController: BaseCollectionViewController?
	
	func setup(from tweetModel: TwitarrPost) {
	
		author = tweetModel.author
		postTime = tweetModel.postDate()
					
		// Show the current number of likes this tweet has.
		addObservation(tweetModel.tell(self, when: "likeReaction.count") { observer, observed in
			observer.numLikes = observed.likeReaction?.count ?? 0
		}?.execute())
		
		// Tweet text
		addObservation(tweetModel.tell(self, when: "text") { observer, observed in 	
			observer.postText = observed.text
		}?.execute())
							
		// Photo, if one's attached
		addObservation(tweetModel.tell(self, when: "photoDetails.id") { observer, observed in
			if let photo = observed.photoDetails {
				observer.photos = [photo]
			}
			else {
				observer.photos = []
			}
		}?.execute())
		
		// Watch for login/out, so we can update like/unlike button state
		let authorUsername = author?.username ?? ""
		addObservation(CurrentUser.shared.tell(self, when: "loggedInUser") { observer, observed in
			let currentUsername = CurrentUser.shared.loggedInUser?.username ?? ""
			observer.loggedInUserIsAuthor = authorUsername == currentUsername
			observer.canEdit = observer.loggedInUserIsAuthor
			observer.canDelete = observer.loggedInUserIsAuthor
		
			// When the current user changes, need to re-evaluate: Replies, DeleteOps, EditOps, Likes, LikeOps
			observer.currentUserReplyOpCount = tweetModel.opsWithThisParent?.reduce(0) { (result, operation) in 
				return operation.author.username == currentUsername ? result + 1 : result 
			} ?? 0
			observer.currentUserHasDeleteOp = tweetModel.opsDeletingThisTweet?.contains { 
				$0.author.username == currentUsername 
			} ?? false
			observer.currentUserHasEditOp = tweetModel.opsEditingThisTweet?.author.username == currentUsername
			observer.currentUserLikesThis = tweetModel.likeReaction?.users.contains { $0.username == currentUsername } ?? false
			if let likeOp = tweetModel.getPendingUserReaction("like") {
				observer.currentUserHasLikeOp = likeOp.isAdd ? .like : .unlike
			}
			else {
				observer.currentUserHasLikeOp = .none
			}
			
		}?.execute())
		
		// Reply ops for replies that are children of this tweet
		addObservation(tweetModel.tell(self, when: "opsWithThisParent.count") { observer, observed in 
			let currentUsername = CurrentUser.shared.loggedInUser?.username ?? ""
			observer.currentUserReplyOpCount = observed.opsWithThisParent?.reduce(0) { (result, operation) in 
				return operation.author.username == currentUsername ? result + 1 : result
			} ?? 0
		}?.execute())
		
		// Ops deleting this tweet
		addObservation(tweetModel.tell(self, when: "opsDeletingThisTweet") { observer, observed in
			let currentUsername = CurrentUser.shared.loggedInUser?.username ?? ""
			observer.currentUserHasDeleteOp = observed.opsDeletingThisTweet?.contains { 
				$0.author.username == currentUsername 
			} ?? false
		}?.execute())
		
		// Ops editing this tweet
		addObservation(tweetModel.tell(self, when: "opsEditingThisTweet") { observer, observed in
			let currentUsername = CurrentUser.shared.loggedInUser?.username ?? ""
			observer.currentUserHasEditOp = observed.opsEditingThisTweet?.author.username == currentUsername
		}?.execute())
		
		// Likes
		addObservation(tweetModel.tell(self, when: "reactionDict.like.users.count") { observer, observed in
			let currentUsername = CurrentUser.shared.loggedInUser?.username ?? ""
			observer.currentUserLikesThis = observed.likeReaction?.users.contains 
					{ $0.username == currentUsername } ?? false
		}?.execute())
							
		// Like/Unlike ops
		addObservation(tweetModel.tell(self, when: "reactionOps.count") { observer, observed in
			if let likeOp = tweetModel.getPendingUserReaction("like") {
				observer.currentUserHasLikeOp = likeOp.isAdd ? .like : .unlike
			}
			else {
				observer.currentUserHasLikeOp = .none
			}
		}?.execute())
	}
	
	init(withModel: TwitarrPost?) {
		super.init(withModel: nil, reuse: "tweet", bindingWith: TwitarrTweetCellBindingProtocol.self)
		model = withModel
	}

//MARK: Action Handlers
	func linkTextTapped(link: String) {
 		viewController?.performKrakenSegue(.tweetFilter, sender: link)
	}
	
	func authorIconTapped() {
		if let tweetModel = model as? TwitarrPost {
			viewController?.performKrakenSegue(.userProfile, sender: tweetModel.author.username)
		}
	}
	
	func likeButtonTapped() {
 		guard isInteractive else { return }
   		guard let tweetModel = model as? TwitarrPost else { return } 

		// FIXME: Still not sure what to do in the case where the user, once logged in, already likes the post.
		// When nobody is logged in we still enable and show the Like button. Tapping it opens the login panel, 
		// with a successAction that performs the like action.
		if !CurrentUser.shared.isLoggedIn() {
 			let seguePackage = LoginSegueWithAction(promptText: "In order to like this post, you'll need to log in first.",
					loginSuccessAction: { tweetModel.setReaction("like", to: !self.currentUserLikesThis) }, 
					loginFailureAction: nil)
  			viewController?.performKrakenSegue(.modalLogin, sender: seguePackage)
   		}
   		else {
			tweetModel.setReaction("like", to: !currentUserLikesThis)
   		}
	}
	
	func replyButtonTapped() {
   		guard let tweetModel = model as? TwitarrPost else { return } 
		viewController?.performKrakenSegue(.composeReplyTweet, sender: tweetModel)
	}
	
	func editButtonTapped() {
   		guard let tweetModel = model as? TwitarrPost else { return } 
		viewController?.performKrakenSegue(.editTweet, sender: tweetModel)
	}
	
	func deleteButtonTapped() {
   		guard let tweetModel = model as? TwitarrPost else { return } 
		tweetModel.addDeleteTweetOp()
	}
	
	func cancelDeleteOpButtonTapped() {
		guard let tweetModel = model as? TwitarrPost else { return } 
		tweetModel.cancelDeleteOp()   		
	}
	
	func cancelEditOpButtonTapped() {
		guard let tweetModel = model as? TwitarrPost else { return } 
		tweetModel.cancelEditOp()   		
	}
	
	func viewPendingRepliesButtonTapped() {
		guard let tweetModel = model as? TwitarrPost else { return } 
		viewController?.performKrakenSegue(.pendingReplies, sender: tweetModel)
	}
	
	func cancelReactionOpButtonTapped() {
		guard let tweetModel = model as? TwitarrPost else { return } 
		tweetModel.cancelReactionOp("like")   		
	}

}

@objc class TwitarrTweetOpCellModel: FetchedResultsCellModel, TwitarrTweetCellBindingProtocol {
	override class var validReuseIDDict: [String: BaseCollectionViewCell.Type ] { return [ "tweet" : TwitarrTweetCell.self ] }

	// If false, the tweet cell doesn't show text links, the like/reply/delete/edit buttons, nor does tapping the 
	// user thumbnail open a user profile panel.
	@objc dynamic var isInteractive: Bool = false
	
	dynamic var author: KrakenUser?
	dynamic var postTime: Date?
	
	dynamic var numLikes: Int32 = 0
	dynamic var postText: String?
	dynamic var photos: [PhotoDetails]?
	dynamic var photoImages: [Data]? 
	dynamic var loggedInUserIsAuthor: Bool = false		// False if no logged in user

	// Reply, Edit, Delete, Like
	dynamic var currentUserReplyOpCount: Int32 = 0
	dynamic var currentUserHasDeleteOp: Bool = false
	dynamic var currentUserHasEditOp: Bool = false
	dynamic var currentUserReactOpCount: Int32 = 0
	dynamic var currentUserHasLikeOp: LikeOpKind = .none
	dynamic var currentUserLikesThis: Bool = false
	dynamic var canReply: Bool = false
	dynamic var canEdit: Bool = true
	dynamic var canDelete: Bool = true

	dynamic var isDeleted: Bool = false
	
    override var model: NSFetchRequestResult? {
    	didSet {
    		clearObservations()
    		if let tweetModel = model as? PostOpTweet, !tweetModel.isDeleted {
    			setup(from: tweetModel)
			}
			else {
				author = nil
				postTime = nil
				postText = nil				
  				photos = nil
  				isDeleted = true
  				shouldBeVisible = false
  			}
		}
	}

	init(withModel: PostOpTweet?) {
		super.init(withModel: nil, reuse: "tweet", bindingWith: TwitarrTweetCellBindingProtocol.self)
		model = withModel
	}
	
	func setup(from tweetOpModel: PostOpTweet) {
		author = tweetOpModel.author
		postTime = tweetOpModel.originalPostTime
		numLikes = 0
		
		// Tweet text
		addObservation(tweetOpModel.tell(self, when: "text") { observer, observed in 	
			observer.postText = observed.text
		}?.execute())
							
		// Photo, if one's attached. Tweets can only have 1 photo.
		addObservation(tweetOpModel.tell(self, when: "image") { observer, observed in
			if let photoData = observed.image {
				observer.photoImages = [(photoData as Data)]
			}
			else {
				observer.photoImages = []
			}
		}?.execute())
		
		// Pending Ops cannot have replies, deleteOps, editOps, LikeOps, or reactOps applied to them, so there are all false
	}
	
	func linkTextTapped(link: String) {	}
	func authorIconTapped() { }
	func likeButtonTapped() { }
	func replyButtonTapped() { }
	func editButtonTapped() { }
	func deleteButtonTapped() { }
	func cancelDeleteOpButtonTapped() {	}
	func cancelEditOpButtonTapped() { }
	func viewPendingRepliesButtonTapped() { }
	func cancelReactionOpButtonTapped() { }
}

// MARK: -
class TwitarrTweetCell: BaseCollectionViewCell, TwitarrTweetCellBindingProtocol, UITextViewDelegate {
	
// MARK: Declarations
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

	private static let cellInfo = [ "tweet" : PrototypeCellInfo("TwitarrTweetCell") ]
	override class var validReuseIDDict: [ String: PrototypeCellInfo] { return TwitarrTweetCell.cellInfo }
	
	private var opsByCurrentUserObservations: [EBNObservation?] = []
	@objc dynamic var loggedInUserHasLikedThis: Bool = false

// MARK: Binding Protocol Vars

	var isInteractive: Bool = true
	
	// 
    var model: NSFetchRequestResult? 
  			
	var authorIconObservation: EBNObservation?
	var author: KrakenUser? {
		didSet {
			// Author's name, and also post time.
			buildTitleLabel()
			
			// Author's user icon. loadUserThumbnail() starts a network call for the image, if necessary.
			userButton.setTitle("", for: .normal)
			if let author = author {
				author.loadUserThumbnail()
				authorIconObservation?.stopObservations()
				authorIconObservation = author.tell(self, when:"thumbPhoto") { observer, observed in
					observer.userButton.setBackgroundImage(observed.thumbPhoto, for: .normal)
				}?.execute()
			}
		}
	}
	
	var postTime: Date? {
		didSet {
			buildTitleLabel()
		}
	}
	
	var numLikes: Int32 = 0 {
		didSet {
			if numLikes > 0 {
				likesLabel.isHidden = false
				likesLabel.text = "\(numLikes) 💛"
			}
			else {
				likesLabel.isHidden = true
			}
		}
	}
	
	var postText: String? {
		didSet {
			// Can the user tap on a link and open a filtered view?
			var addLinksToText = !isPrototypeCell
			if isInteractive, let vc = viewController as? BaseCollectionViewController {
				addLinksToText = vc.canPerformSegue(.tweetFilter)
			}
					
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

			let tweetTextWithLinks = StringUtilities.cleanupText(postText ?? "", addLinks: addLinksToText)
			tweetTextWithLinks.addAttributes(tweetTextAttrs, range: NSRange(location: 0, length: tweetTextWithLinks.length))
			tweetTextView.attributedText = tweetTextWithLinks
			
			let fixedWidth = tweetTextView.frame.size.width
			let newSize = tweetTextView.sizeThatFits(CGSize(width: fixedWidth, 
					height: CGFloat.greatestFiniteMagnitude))
			tweetTextView.frame.size = CGSize(width: max(newSize.width, fixedWidth), height: newSize.height)
		}
	}
	
	var photos: [PhotoDetails]? {
		didSet {
			setupPhotos()
		}
	}
	
	dynamic var photoImages: [Data]? {
		didSet {
			setupPhotos()
		}
	}
	
	func setupPhotos() {
		if let photoArray = photos, photoArray.count > 0 {
			postImage.isHidden = false
			if !isPrototypeCell {
				ImageManager.shared.image(withSize:.medium, forKey: photoArray[0].id) { image in
					self.postImage.image = image
				}
			}
		}
		else if let photoArray = photoImages, photoArray.count > 0 {
			postImage.isHidden = false
			if !isPrototypeCell {
				self.postImage.image = UIImage(data: photoArray[0])
			}
		}
		else {
			postImage.image = nil
			postImage.isHidden = true
		}
	}
	
	var currentUserReplyOpCount: Int32 = 0 {
		didSet {
			setViewVisibility(view: replyQueuedView, showIf: currentUserReplyOpCount != 0)
			if currentUserReplyOpCount == 1 {
				replyQueuedLabel.text = "Reply pending"
			}
			else if currentUserReplyOpCount > 1 {
				replyQueuedLabel.text = "\(currentUserReplyOpCount) replies pending"
			}
		}
	}
	
	var currentUserHasDeleteOp: Bool = false {
		didSet {
			setViewVisibility(view: deleteQueuedView, showIf: currentUserHasDeleteOp)
		}
	}
	
	var currentUserHasEditOp: Bool = false {
		didSet {
			setViewVisibility(view: editQueuedView, showIf: currentUserHasEditOp)
		}
	}
	
	var currentUserReactOpCount: Int32 = 0 {
		didSet {
		}
	}
	
	var currentUserHasLikeOp: LikeOpKind = .none {
		didSet {
			setViewVisibility(view: reactionQueuedView, showIf: currentUserHasLikeOp != .none)
			reactionQueuedLabel.text = currentUserHasLikeOp == .like ? "\"Like\" pending" : "\"Unlike\" pending"
			likeButton.isEnabled = currentUserHasLikeOp == .none
		}
	}
	
	var currentUserLikesThis: Bool = false {
		didSet {
			let newText = currentUserLikesThis ? "Unlike" : "Like"
			likeButton.setTitle(newText, for: .normal)
		}
	}
	
	var canReply: Bool = false {
		didSet {
			replyButton.isHidden = !canReply
		}
	}
	
	var canEdit: Bool = false {
		didSet {
			editButton.isHidden = !canEdit
		}
	}
	
	var canDelete: Bool = false {
		didSet {
			deleteButton.isHidden = !canDelete
		}
	}
	
	var loggedInUserIsAuthor: Bool = false
	var isDeleted: Bool	= false

// MARK: Methods

	func buildTitleLabel() {
		let authorDisplayName: String = author?.displayName ?? ""
		let titleAttrString = NSMutableAttributedString(string: "\(authorDisplayName), ", 
				attributes: authorTextAttributes())

		if let time = postTime {
			let timeString = StringUtilities.relativeTimeString(forDate: time)
			let timeAttrString = NSAttributedString(string: timeString, attributes: postTimeTextAttributes())
			titleAttrString.append(timeAttrString)
		}
		titleLabel.attributedText = titleAttrString
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

		titleLabel.textContainerInset = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
		tweetTextView.textContainerInset = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)

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
	
	// Prototype cells have difficulty figuring out their layout while animating. This fn shows/hides subviews immediately
	// for proto cells, but animates for normal cells.
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
		
	override var privateSelected: Bool {
		didSet {
			if !isPrototypeCell, privateSelected == oldValue { return }
			
			var newImageHeight: CGFloat = 200.0
			if privateSelected, let photos = photos, photos.count == 1 {
				let photoDetails = photos[0] 
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
 		linkTextTapped(link: URL.absoluteString)
        return false
    }
    
    func linkTextTapped(link: String) {
 		if let bindingModel = cellModel as? TwitarrTweetCellBindingProtocol {
			bindingModel.linkTextTapped(link: link)
		}
	}
        
   	@IBAction func authorIconTapped() {
 		guard isInteractive else { return }
 		if let bindingModel = cellModel as? TwitarrTweetCellBindingProtocol {
			bindingModel.authorIconTapped()
		}
   	}
   	
// MARK: Buttons in toolbar
   	
   	@IBAction func likeButtonTapped() {
 		guard isInteractive else { return }
 		if let bindingModel = cellModel as? TwitarrTweetCellBindingProtocol {
			bindingModel.likeButtonTapped()
		}
   	}
   	
	@IBAction func replyButtonTapped() {
 		guard isInteractive else { return }
 		if let bindingModel = cellModel as? TwitarrTweetCellBindingProtocol {
			bindingModel.replyButtonTapped()
		}
	}
  	
	@IBAction func editButtonTapped() {
 		guard isInteractive else { return }
   		if let bindingModel = cellModel as? TwitarrTweetCellBindingProtocol {
			bindingModel.editButtonTapped()
		}

//		else if let tweetOpModel = model as? PostOpTweet {
//			viewController?.performSegue(withIdentifier: "EditTweet", sender: tweetOpModel)
//		}
	}
	
	@IBAction func deleteButtonTapped() {
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
   		if let bindingModel = cellModel as? TwitarrTweetCellBindingProtocol {
			bindingModel.deleteButtonTapped()
		}
//		else if let postOpModel = model as? PostOpTweet {
//			PostOperationDataManager.shared.remove(op: postOpModel)
//		}
	}
	
// MARK: Buttons in pending state change views
	
	
   	@IBAction func cancelDeleteOpButtonTapped() {
 		guard isInteractive else { return }
   		if let bindingModel = cellModel as? TwitarrTweetCellBindingProtocol {
			bindingModel.cancelDeleteOpButtonTapped()
		}
   	}
		
   	@IBAction func cancelEditOpButtonTapped() {
 		guard isInteractive else { return }
   		if let bindingModel = cellModel as? TwitarrTweetCellBindingProtocol {
			bindingModel.cancelEditOpButtonTapped()
		}
   	}
		
   	@IBAction func viewPendingRepliesButtonTapped() {
 		guard isInteractive else { return }
   		if let bindingModel = cellModel as? TwitarrTweetCellBindingProtocol {
			bindingModel.viewPendingRepliesButtonTapped()
		}
   	}
		
   	@IBAction func cancelReactionOpButtonTapped() {
 		guard isInteractive else { return }
   		if let bindingModel = cellModel as? TwitarrTweetCellBindingProtocol {
			bindingModel.cancelReactionOpButtonTapped()
		}
   	}
		
}



// "<a class=\"tweet-url username\" href=\"#/user/profile/kvort\">@kvort</a> Okay. This is a reply."
