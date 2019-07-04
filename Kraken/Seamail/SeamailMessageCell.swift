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
	override class var validReuseIDDict: [String: BaseCollectionViewCell.Type ] { return [ "SeamailMessageCell" : SeamailMessageCell.self ] }

	override func reuseID() -> String {
		if let message = model as? SeamailMessage, message.author.username == CurrentUser.shared.loggedInUser?.username {
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
        // Initialization code
    }
    
    var model: NSFetchRequestResult? {
    	didSet {
    		if let message = model as? SeamailMessage {
	    	//	authorUsernameLabel.text = message.author.username
	    		messageLabel.text = message.text
	    		let postDate: TimeInterval = TimeInterval(message.timestamp) / 1000.0
	    		let dateString = StringUtilities.relativeTimeString(forDate: Date(timeIntervalSince1970: postDate))
				authorUsernameLabel?.text = "\(message.author.username), \(dateString)"
				postTimeLabel?.text = dateString
 
				message.author.loadUserThumbnail()
				message.author.tell(self, when:"thumbPhoto") { observer, observed in
					observer.authorImage.image = observed.thumbPhoto
					CollectionViewLog.debug("Setting user image for \(observed.username)", ["image" : observed.thumbPhoto])
				}?.schedule()
			}
    	}
    }
    
}
