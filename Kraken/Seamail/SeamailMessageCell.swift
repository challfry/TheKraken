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

	override func reuseID() -> String {
		guard let username = CurrentUser.shared.loggedInUser?.username else { return "SeamailMessageCell" }
		
		if let message = model as? SeamailMessage, message.author.username == username {
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
	@IBOutlet var authorUsernameLabel: UILabel?
	@IBOutlet var postTimeLabel: UILabel?
	@IBOutlet var messageLabel: UILabel!
		
	private static let cellInfo = [ "SeamailMessageCell" : PrototypeCellInfo("SeamailMessageCell"),
			"SeamailSelfMessageCell" : PrototypeCellInfo("SeamailSelfMessageCell") ]
	override class var validReuseIDDict: [ String: PrototypeCellInfo] { return SeamailMessageCell.cellInfo }

	override func awakeFromNib() {
        super.awakeFromNib()

		// Update the relative post time every 10 seconds.
		NotificationCenter.default.addObserver(forName: RefreshTimers.TenSecUpdateNotification, object: nil,
				queue: nil) { [weak self] notification in
    		if let self = self, let message = self.model as? SeamailMessage, !message.isDeleted {
	    		let postDate: TimeInterval = TimeInterval(message.timestamp) / 1000.0
	    		let dateString = StringUtilities.relativeTimeString(forDate: Date(timeIntervalSince1970: postDate))
				self.authorUsernameLabel?.attributedText = self.authorAndTime(author: message.author.username, 
						time: dateString)
				self.postTimeLabel?.attributedText = self.authorAndTime(author: nil, time: dateString)
			}
		}
    }
    
    var model: NSFetchRequestResult? {
    	didSet {
    		if let message = model as? SeamailMessage, !message.isDeleted {
	    	//	authorUsernameLabel.text = message.author.username
	    		messageLabel.text = message.text
	    		let postDate: TimeInterval = TimeInterval(message.timestamp) / 1000.0
	    		let dateString = StringUtilities.relativeTimeString(forDate: Date(timeIntervalSince1970: postDate))
				authorUsernameLabel?.attributedText = authorAndTime(author: message.author.username, time: dateString)
				postTimeLabel?.attributedText = authorAndTime(author: nil, time: dateString)
				contentView.backgroundColor = UIColor(named: "Cell Background")
 
				message.author.loadUserThumbnail()
				message.author.tell(self, when:"thumbPhoto") { observer, observed in
					observed.loadUserThumbnail()
					observer.authorImage.image = observed.thumbPhoto
//					CollectionViewLog.debug("Setting user image for \(observed.username)", ["image" : observed.thumbPhoto])
				}?.schedule()
			}
			else if let message = model as? PostOpSeamailMessage, !message.isDeleted {
	    		messageLabel.text = message.text
				postTimeLabel?.attributedText = authorAndTime(author: nil, time: "In the near future")
				authorUsernameLabel?.text = "\(message.author.username), In the near future"
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
}
