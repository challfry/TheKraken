//
//  TwitarrTweetCell.swift
//  Kraken
//
//  Created by Chall Fry on 3/30/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit

class TwitarrTweetCell: UICollectionViewCell {
	@IBOutlet var titleLabel: UILabel!
	@IBOutlet var tweetTextLabel: UILabel!
	@IBOutlet var userAvatar: UIImageView!

    var tweetModel: TwitarrV2Post? {
    	didSet {
    		titleLabel.text = tweetModel?.author.displayName
    		tweetTextLabel.text = tweetModel?.text
    		if let username = tweetModel?.author.username, let user = UserManager.shared.user(username) {
	    		userAvatar.image = user.thumbPhoto
	    		user.loadUserThumbnail()
			}
    	}
	}
		
    
    
}
