//
//  TwitarrTweetCell.swift
//  Kraken
//
//  Created by Chall Fry on 3/30/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit
import CoreData

@objc class TwitarrTweetCellModel: FetchedResultsCellModel {
	override class var validReuseIDDict: [String: BaseCollectionViewCell.Type ] { return [ "tweet" : TwitarrTweetCell.self ] }
}


class TwitarrTweetCell: BaseCollectionViewCell, FetchedResultsBindingProtocol, UITextViewDelegate {
	
	@IBOutlet var titleLabel: UITextView!			// Author and timestamp
	@IBOutlet var likesLabel: UILabel!				
	@IBOutlet var tweetTextView: UITextView!
	@IBOutlet var postImage: UIImageView!
	@IBOutlet var userButton: UIButton!
	@IBOutlet var editStackView: UIView!
	@IBOutlet var 	editStack: UIStackView!
	@IBOutlet var   	likeButton: UIButton!
	@IBOutlet var 		editButton: UIButton!
	@IBOutlet var 		replyButton: UIButton!
	@IBOutlet var 		deleteButton: UIButton!
	
	@IBOutlet var 	reactionQueuedView: UIView!
	@IBOutlet var 		reactionQueuedLabel: UILabel!
	@IBOutlet var 		cancelQueuedReactionButton: UIButton!
		
	private var reactionDictObservation: EBNObservation?
	private var reactionOpsObservation: EBNObservation?
	@objc dynamic var loggedInUserHasLikedThis: Bool = false

	private static let cellInfo = [ "tweet" : PrototypeCellInfo("TwitarrTweetCell") ]
	override class var validReuseIDDict: [ String: PrototypeCellInfo] { return TwitarrTweetCell.cellInfo }
	
	private static var prototypeCell: TwitarrTweetCell =
		UINib(nibName: "TwitarrTweetCell", bundle: nil).instantiate(withOwner: nil, options: nil)[0] as! TwitarrTweetCell


    var model: NSFetchRequestResult? {
    	didSet {
    		clearObservations()
    		guard let tweetModel = model as? TwitarrPost else {
				titleLabel.attributedText = nil
				tweetTextView.attributedText = nil
				postImage.image = nil
				userButton.setBackgroundImage(nil, for: .normal)				
  				self.postImage.isHidden = true
				self.postImage.image = nil
				return
  			}
    		
			let titleAttrString = NSMutableAttributedString(string: "\(tweetModel.author.displayName), ", 
					attributes: authorTextAttributes())
			let timeString = StringUtilities.relativeTimeString(forDate: tweetModel.postDate())
			let timeAttrString = NSAttributedString(string: timeString, attributes: postTimeTextAttributes())
			titleAttrString.append(timeAttrString)
			titleLabel.attributedText = titleAttrString
			
			if let likeReaction = tweetModel.reactions.first(where: { reaction in reaction.word == "like" }) {
				likesLabel.isHidden = false
				likesLabel.text = "\(likeReaction.count) 💛"
			}
			else {
				likesLabel.isHidden = true
			}
			
			// Can the user tap on a link and open a filtered view?
			let addLinksToText = viewController?.shouldPerformSegue(withIdentifier: "TweetFilter", sender: self) ?? false

			tweetTextView.attributedText = StringUtilities.cleanupText(tweetModel.text, addLinks: addLinksToText)
			let fixedWidth = tweetTextView.frame.size.width
			let newSize = tweetTextView.sizeThatFits(CGSize(width: fixedWidth, height: CGFloat.greatestFiniteMagnitude))
			tweetTextView.frame.size = CGSize(width: max(newSize.width, fixedWidth), height: newSize.height)
			
			tweetModel.author.loadUserThumbnail()
			addObservation(tweetModel.author.tell(self, when:"thumbPhoto") { observer, observed in
				observer.userButton.setBackgroundImage(observed.thumbPhoto, for: .normal)
				observer.userButton.setTitle("", for: .normal)
			}?.schedule())
			
			if let photo = tweetModel.photoDetails {
				self.postImage.isHidden = false
				ImageManager.shared.image(withSize:.medium, forKey: photo.id) { image in
					self.postImage.image = image
					self.cellSizeChanged()
				}
			}
			else {
				self.postImage.image = nil
				self.postImage.isHidden = true
			}
			
			let currentUserWroteThis = tweetModel.author.username == CurrentUser.shared.loggedInUser?.username
			editButton.isHidden = !currentUserWroteThis
			deleteButton.isHidden = !currentUserWroteThis
			
			// Watch for login/out, so we can update like/unlike button state
			addObservation(CurrentUser.shared.tell(self, when: "loggedInUser") { observer, observed in
				observer.setLikeButtonState()
				
				// Inside the other obseration: if we're logged in,
				if let username = CurrentUser.shared.loggedInUser?.username {
					// setup observation on reactions to watch for currentUser has reacting to this tweet.
					observer.reactionDictObservation = tweetModel.tell(self, when: "reactionDict.like.users.\(username)") { observer, observed in
						observer.setLikeButtonState()
					}?.schedule()
					observer.addObservation(observer.reactionDictObservation)
					
					// and watch ReactionOps to look for pending reactions; show/hide the Pending Reaction card.
					observer.reactionOpsObservation = tweetModel.tell(self, when: "reactionOpsCount") { observer, observed in
						if observer.privateSelected, let likeReaction = tweetModel.getPendingUserReaction("like") {
							if observer.isPrototypeCell {
								observer.reactionQueuedView.isHidden = !observer.privateSelected
							}
							else {
								UIView.animate(withDuration: 0.3) {
									observer.reactionQueuedView.isHidden = !observer.privateSelected
								}
							}
						//	observer.reactionQueuedView.isHidden = !observer.privateSelected/
							observer.reactionQueuedLabel.text = likeReaction.isAdd ? "\"Like\" pending" : "\"Unlike\" pending"
							observer.likeButton.isEnabled = false
						}
						else {
							if observer.isPrototypeCell {
								observer.reactionQueuedView.isHidden = true
							}
							else {
								UIView.animate(withDuration: 0.3) {
									observer.reactionQueuedView.isHidden = true
								}
							}
							observer.likeButton.isEnabled = true
						}
				
						observer.cellSizeChanged()
					}?.execute()
					observer.addObservation(observer.reactionOpsObservation)
				}
				else {
					observer.removeObservation(observer.reactionDictObservation)
					observer.removeObservation(observer.reactionOpsObservation)
					observer.reactionQueuedView.isHidden = true
					observer.likeButton.isEnabled = true
				}
			}?.execute())
			

			titleLabel.textContainerInset = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
			tweetTextView.textContainerInset = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
    	}
	}
	
	override func awakeFromNib() {
		super.awakeFromNib()
		reactionQueuedView.isHidden = true
		editStackView.isHidden = true
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
	}
	
	
//	override var isSelected: Bool {
//		didSet {
//			// debug
//			print ("\(isSelected) old: \(oldValue) proto: \(isPrototypeCell) for cell: " + tweetTextView.text)
//			if !isSelected && oldValue && !isPrototypeCell {
//				print("boned")
//			}
//
//			if  isSelected == oldValue {
//				return
//			}
//			editStackView.isHidden = !isSelected
//			
//			if let username = CurrentUser.shared.loggedInUser?.username, let tweetModel = model as? TwitarrPost, 
//					let likeReaction = tweetModel.reactionOps?.first(where: { reaction in
//						return reaction.author.username == username && reaction.reactionWord == "like" 
//					}) {
//				reactionQueuedView.isHidden = !isSelected
//				reactionQueuedLabel.text = likeReaction.isAdd ? "\"Like\" pending" : "\"Unlike\" pending"
//			}
//			else {
//				reactionQueuedView.isHidden = true
//			}
//
//			cellSizeChanged()
//			contentView.backgroundColor = isSelected ? UIColor(white: 0.95, alpha: 1.0) : UIColor.white
//		}
//	}
	
	override var privateSelected: Bool {
		didSet {
			if privateSelected == oldValue { return }
			
			editStackView.isHidden = !privateSelected
			
			if let tweetModel = model as? TwitarrPost, let existingLikeReactionOp = tweetModel.getPendingUserReaction("like") {
				reactionQueuedView.isHidden = !privateSelected
				reactionQueuedLabel.text = existingLikeReactionOp.isAdd ? "\"Like\" pending" : "\"Unlike\" pending"
			}
			else {
				reactionQueuedView.isHidden = true
			}

			cellSizeChanged()
			contentView.backgroundColor = privateSelected ? UIColor(white: 0.95, alpha: 1.0) : UIColor.white
		}
	}
	
	var highlightAnimation: UIViewPropertyAnimator?
	override var isHighlighted: Bool {
		didSet {
			if let oldAnim = highlightAnimation {
				oldAnim.stopAnimation(true)
			}
			let anim = UIViewPropertyAnimator(duration: 0.2, curve: .easeInOut) {
				self.contentView.backgroundColor = self.isHighlighted || self.privateSelected ? UIColor(white:0.95, alpha: 1.0) : UIColor.white
			}
			anim.isUserInteractionEnabled = true
			anim.isInterruptible = true
			anim.startAnimation()
			highlightAnimation = anim
		}
	}
	
	func authorTextAttributes() -> [ NSAttributedString.Key : Any ] {
		let authorFont = UIFont(name:"Helvetica-Bold", size: 14)
		let result: [NSAttributedString.Key : Any] = [ .font : authorFont?.withSize(14) as Any ]
		return result
	}
	
	func postTimeTextAttributes() -> [ NSAttributedString.Key : Any ] {
		let postTimeFont = UIFont(name:"Georgia-Italic", size: 14)
		let postTimeColor = UIColor.lightGray
		let result: [NSAttributedString.Key : Any] = [ .font : postTimeFont?.withSize(14) as Any, .foregroundColor : postTimeColor ]
		return result
	}
	
	
// MARK: Actions

	// Handler for tapping on linktext. The textView is non-editable.
	func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange, 
			interaction: UITextItemInteraction) -> Bool {
 //		UIApplication.shared.open(URL, options: [:])
 		viewController?.performSegue(withIdentifier: "TweetFilter", sender: URL.absoluteString)
        return false
    }
        
   	@IBAction func showUserProfile() {
   		if let tweetModel = model as? TwitarrPost {
   			let userName = tweetModel.author.username
   			viewController?.performSegue(withIdentifier: "UserProfile", sender: userName)
		}
   	}
   	
   	@IBAction func likeButtonTapped() {
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
   		guard let tweetModel = model as? TwitarrPost else { return } 
		viewController?.performSegue(withIdentifier: "ComposeReplyTweet", sender: tweetModel)
	}
  	
	@IBAction func editButtonTapped() {
   		guard let tweetModel = model as? TwitarrPost else { return } 
		viewController?.performSegue(withIdentifier: "EditTweet", sender: tweetModel)
	}
	
	@IBAction func eliteDeleteTweetButtonTapped() {
   		guard let tweetModel = model as? TwitarrPost else { return } 
//
	}
	
   	@IBAction func cancelReactionOpButtonTapped() {
   		guard let tweetModel = model as? TwitarrPost else { return } 
   		tweetModel.cancelReactionOp("like")   		
   	}
		
}



// "<a class=\"tweet-url username\" href=\"#/user/profile/kvort\">@kvort</a> Okay. This is a reply."
