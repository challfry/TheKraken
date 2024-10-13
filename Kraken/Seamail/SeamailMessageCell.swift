//
//  SeamailMessageCell.swift
//  Kraken
//
//  Created by Chall Fry on 5/16/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit
import CoreData

@objc class SeamailMessageCellModel: FetchedResultsCellModel {
	override class var validReuseIDDict: [String: BaseCollectionViewCell.Type ] { 
		return [ "SeamailMessageCell" : SeamailMessageCell.self, "SeamailSelfMessageCell" : SeamailMessageCell.self ] 
	}

	override func reuseID(traits: UITraitCollection) -> String {
		guard let userID = CurrentUser.shared.loggedInUser?.userID else { return "SeamailMessageCell" }
		
		if let message = model as? SeamailMessage, message.author?.userID == userID {
    		return "SeamailSelfMessageCell"
    	}
    	else if let _ = model as? PostOpSeamailMessage {
    		return "SeamailSelfMessageCell"
    	}
    	else {
    		return "SeamailMessageCell"
    	}
	}
}

class SeamailMessageCell: BaseCollectionViewCell, FetchedResultsBindingProtocol {
	@IBOutlet var authorImage: UIImageView!
	
	// IMPORTANT that these are optional! The xib for self messages doesn't have a username!
	@IBOutlet var authorUsernameLabel: UILabel?
	@IBOutlet var postTimeLabel: UILabel?
	@IBOutlet var messageLabel: UILabel!
	
	@IBOutlet var imageView: UIImageView!
	@IBOutlet var imageViewHeight: NSLayoutConstraint!
	
	private static let cellInfo = [ "SeamailMessageCell" : PrototypeCellInfo("SeamailMessageCell"),
			"SeamailSelfMessageCell" : PrototypeCellInfo("SeamailSelfMessageCell") ]
	override class var validReuseIDDict: [ String: PrototypeCellInfo] { return SeamailMessageCell.cellInfo }

	override func awakeFromNib() {
        super.awakeFromNib()

		// Font styling
		authorUsernameLabel?.styleFor(.body)
		postTimeLabel?.styleFor(.body)
		messageLabel.styleFor(.body)

		// Update the relative post time every 10 seconds.
		NotificationCenter.default.addObserver(forName: RefreshTimers.TenSecUpdateNotification, object: nil,
				queue: nil) { [weak self] notification in
    		if let self = self, let message = self.model as? SeamailMessage, !message.isDeleted {
	    		let dateString = StringUtilities.relativeTimeString(forDate: message.timestamp)
				self.authorUsernameLabel?.attributedText = self.authorAndTime(author: message.author?.username, 
						time: dateString)
				self.postTimeLabel?.attributedText = self.authorAndTime(author: nil, time: dateString)
			}
		}
		
		if !isPrototypeCell {
	 		let photoTap = UITapGestureRecognizer(target: self, action: #selector(SeamailMessageCell.photoTapped(_:)))
		 	imageView.addGestureRecognizer(photoTap)
		}
	}
    
    var model: NSFetchRequestResult? {
    	didSet {
     		clearObservations()
	   		if let message = model as? SeamailMessage, !message.isDeleted {
	    	//	authorUsernameLabel.text = message.author.username
				let msgFont = UIFont(name: "TimesNewRomanPSMT", size: 17.0) ?? UIFont.preferredFont(forTextStyle: .body)
	    		messageLabel.attributedText = StringUtilities.cleanupText(message.text, font: msgFont)
	    		let dateString = StringUtilities.relativeTimeString(forDate: message.timestamp)
				authorUsernameLabel?.attributedText = authorAndTime(author: message.author?.username, time: dateString)
				postTimeLabel?.attributedText = authorAndTime(author: nil, time: dateString)
				contentView.backgroundColor = UIColor(named: "Cell Background")
 
				addObservation(message.tell(self, when: "author") { observer, observed in
					observed.author?.loadUserThumbnail()
				}?.execute())
				addObservation(message.tell(self, when:"author.thumbPhoto") { observer, observed in
					observer.authorImage.image = observed.author?.thumbPhoto
//					CollectionViewLog.debug("Setting user image for \(observed.username)", ["image" : observed.thumbPhoto])
				}?.execute())
				
				message.tell(self, when: "image") { observer, observed in
					if let photoDetails = message.image {
						ImageManager.shared.image(withSize: .full, forKey: photoDetails.id) { image in
							observer.imageView.image = image
							let newHeight = image != nil ? 200.0 : 0.0
							if observer.imageViewHeight.constant != newHeight {
								observer.imageViewHeight.constant = newHeight
								observer.cellSizeChanged()
							}
						}
						observer.imageViewHeight.constant = 200
					}
					else {
						observer.imageView.image = nil
						observer.imageViewHeight.constant = 0
					}
					observer.cellSizeChanged()
				}?.execute()
				
				var authorAccessibility = "You"
				if authorUsernameLabel?.isHidden == false, let authorName = message.author?.username {
					authorAccessibility = "\(authorName)"
				}
				accessibilityLabel = "\(authorAccessibility), \(dateString) wrote, \(messageLabel.text ?? "")"
				isAccessibilityElement = true
			}
			else if let message = model as? PostOpSeamailMessage, !message.isDeleted {
	    		messageLabel.text = message.text
				postTimeLabel?.attributedText = authorAndTime(author: nil, time: "In the near future")
				authorUsernameLabel?.text = "\(message.author.username), In the near future"
				if let photoDetails = message.photo {
					if let imageData = photoDetails.imageData {
						imageView.image = UIImage(data: imageData)
						imageViewHeight.constant = imageView.image != nil ? 200 : 0
						cellSizeChanged()
					}
					else if let imageName = photoDetails.filename {
						ImageManager.shared.image(withSize: .full, forKey: imageName) { image in
							self.imageView.image = image
							self.imageViewHeight.constant = self.imageView.image != nil ? 200 : 0
							self.cellSizeChanged()
						}
					}
				}
				else {
					imageView.image = nil
					imageViewHeight.constant = 0
					cellSizeChanged()
				}
				contentView.backgroundColor = UIColor(named: "Cell Background Selected")
			}
    	}
    }
    
    func authorAndTime(author: String?, time: String) -> NSAttributedString {
    	
 		let resultString = NSMutableAttributedString()
 		if let author = author {
 			let authorString = NSAttributedString(string: "\(author), ", attributes: authorTextAttributes())
 			resultString.append(authorString)
		}
		let timeAttrString = NSAttributedString(string: time, attributes: postTimeTextAttributes())
		resultString.append(timeAttrString)
  		return resultString
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
	
	@objc func photoTapped(_ sender: UITapGestureRecognizer) {
		if let vc = viewController as? BaseCollectionViewController, let image = imageView.image {
			vc.showImageInOverlay(image: image)
		}
	}
}
