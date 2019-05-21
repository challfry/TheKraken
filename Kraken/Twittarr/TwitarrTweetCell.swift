//
//  TwitarrTweetCell.swift
//  Kraken
//
//  Created by Chall Fry on 3/30/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit

class TwitarrTweetCell: BaseCollectionViewCell, UITextViewDelegate {
	@IBOutlet var titleLabel: UITextView!
	@IBOutlet var tweetTextView: UITextView!
	@IBOutlet var postImage: UIImageView!
	@IBOutlet var userButton: UIButton!
	@IBOutlet var editStack: UIStackView!
	@IBOutlet var editButton: UIButton!
		
	private static let cellInfo = [ "tweet" : PrototypeCellInfo("TwitarrTweetCell") ]
	override class var validReuseIDDict: [ String: PrototypeCellInfo] { return TwitarrTweetCell.cellInfo }
	
	private static var prototypeCell: TwitarrTweetCell =
		UINib(nibName: "TwitarrTweetCell", bundle: nil).instantiate(withOwner: nil, options: nil)[0] as! TwitarrTweetCell

	static func makePrototypeCell(for collectionView: UICollectionView, indexPath: IndexPath) -> TwitarrTweetCell? {
		let cell = TwitarrTweetCell.prototypeCell
		cell.collectionViewSize = collectionView.bounds.size
		return cell
	}

    var tweetModel: TwitarrPost? {
    	didSet {
    		titleLabel.text = tweetModel?.author.displayName
    		if let text = tweetModel?.text {
	    		tweetTextView.attributedText = StringUtilities.cleanupText(text)
	    		
				let fixedWidth = tweetTextView.frame.size.width
				let newSize = tweetTextView.sizeThatFits(CGSize(width: fixedWidth, height: CGFloat.greatestFiniteMagnitude))
				tweetTextView.frame.size = CGSize(width: max(newSize.width, fixedWidth), height: newSize.height)
			}
			else {
				tweetTextView.attributedText = nil
			}
			
    		if let user = tweetModel?.author {
	    		user.loadUserThumbnail()
	    		user.tell(self, when:"thumbPhoto") { observer, observed in
					observer.userButton.setBackgroundImage(observed.thumbPhoto, for: .normal)
					observer.userButton.setTitle("", for: .normal)
	    		}?.schedule()
			}
			
			if let photo = tweetModel?.photoDetails {
				self.postImage.isHidden = false
				ImageManager.shared.image(withSize:.medium, forKey: photo.id) { image in
					self.postImage.image = image
				}
			}
			else {
				self.postImage.image = nil
				self.postImage.isHidden = true
			}

			titleLabel.textContainerInset = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
			tweetTextView.textContainerInset = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
    	}
	}
	
	override var isSelected: Bool {
		didSet {
			if  isSelected != editStack.isHidden {
				return
			}
			editStack.isHidden = !isSelected
			contentView.backgroundColor = isSelected ? UIColor(white: 0.95, alpha: 1.0) : UIColor.white
			
			if let vc = viewController as? TwitarrViewController {
				vc.runUpdates()
			}
		}
	
	}
	
	var highlightAnimation: UIViewPropertyAnimator?
	override var isHighlighted: Bool {
		didSet {
			if let oldAnim = highlightAnimation {
				oldAnim.stopAnimation(true)
			}
			let anim = UIViewPropertyAnimator(duration: 0.2, curve: .easeInOut) {
				self.contentView.backgroundColor = self.isHighlighted || self.isSelected ? UIColor(white:0.95, alpha: 1.0) : UIColor.white
			}
			anim.isUserInteractionEnabled = true
			anim.isInterruptible = true
			anim.startAnimation()
			highlightAnimation = anim
		}
	}	
	
	func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange, 
			interaction: UITextItemInteraction) -> Bool {
 //		UIApplication.shared.open(URL, options: [:])
 		viewController?.performSegue(withIdentifier: "TweetFilter", sender: URL.absoluteString)
        return false
    }
    
   	@IBAction func showUserProfile() {
   		if let userName = tweetModel?.author.username {
   			viewController?.performSegue(withIdentifier: "UserProfile", sender: userName)
		}
   	}
		
}



// "<a class=\"tweet-url username\" href=\"#/user/profile/kvort\">@kvort</a> Okay. This is a reply."
