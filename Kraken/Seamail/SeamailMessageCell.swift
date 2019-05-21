//
//  SeamailMessageCell.swift
//  Kraken
//
//  Created by Chall Fry on 5/16/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit

class SeamailMessageCell: BaseCollectionViewCell {

	@IBOutlet weak var authorImage: UIImageView!
	@IBOutlet weak var authorUsernameLabel: UILabel!
	@IBOutlet weak var postTimeLabel: UILabel!
	@IBOutlet weak var messageLabel: UILabel!
	
	
	override func awakeFromNib() {
        super.awakeFromNib()
        // Initialization code
    }
    
    var model: SeamailMessage? {
    	didSet {
    		if let message = model {
	    	//	authorUsernameLabel.text = message.author.username
	    		messageLabel.text = message.text
	    		let postDate: TimeInterval = TimeInterval(message.timestamp) / 1000.0
	    		let dateString = StringUtilities.relativeTimeString(forDate: Date(timeIntervalSince1970: postDate))
				authorUsernameLabel.text = "\(message.author.username), \(dateString)"
				postTimeLabel.text = dateString
 
				message.author.loadUserThumbnail()
				message.author.tell(self, when:"thumbPhoto") { observer, observed in
					observer.authorImage.image = observed.thumbPhoto
				}?.schedule()
			}
    	}
    }

}
