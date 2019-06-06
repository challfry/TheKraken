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
		cell.collectionView = collectionView
		return cell
	}

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

			tweetTextView.attributedText = StringUtilities.cleanupText(tweetModel.text)
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

			titleLabel.textContainerInset = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
			tweetTextView.textContainerInset = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
    	}
	}
	
	
	override var isSelected: Bool {
		didSet {
			if  isSelected == oldValue {
				return
			}
			editStack.isHidden = !isSelected
			cellSizeChanged()
			contentView.backgroundColor = isSelected ? UIColor(white: 0.95, alpha: 1.0) : UIColor.white
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
		
}



// "<a class=\"tweet-url username\" href=\"#/user/profile/kvort\">@kvort</a> Okay. This is a reply."
