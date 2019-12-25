//
//  PendingTwitarrRepliesVC.swift
//  Kraken
//
//  Created by Chall Fry on 7/6/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit

class PendingTwitarrRepliesVC: BaseCollectionViewController {

	var parentTweet: TwitarrPost?
	var tweetDataSource = KrakenDataSource()

	override func viewDidLoad() {
        super.viewDidLoad()
		title = "Pending Replies"
		
		tweetDataSource.register(with: collectionView, viewController: self)

		let tweetSegment = tweetDataSource.append(segment: FRCDataSourceSegment<PostOpTweet>())
		var predicate: NSPredicate?
		if let currentUsername = CurrentUser.shared.loggedInUser?.username, let parent = parentTweet {
			predicate = NSPredicate(format: "parent == %@ AND author.username == %@", parent, currentUsername)
		}
		tweetSegment.activate(predicate: predicate, sort: [NSSortDescriptor(key: "originalPostTime", ascending: true)],
				cellModelFactory: createCellModel)

		setupGestureRecognizer()
		knownSegues = Set([.userProfile, .editTweetOp])
  }
    
    override func viewWillAppear(_ animated: Bool) {
		tweetDataSource.enableAnimations = true
	}

	func createCellModel(_ model:PostOpTweet) -> BaseCellModel {
		let cellModel =  TwitarrTweetOpCellModel(withModel: model)
		return cellModel
	}
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
    	switch segue.identifier {
		case "UserProfile":
			if let destVC = segue.destination as? UserProfileViewController, let username = sender as? String {
				destVC.modelUserName = username
			}

		case "EditTweet":
			if let destVC = segue.destination as? ComposeTweetViewController, let original = sender as? PostOpTweet {
				destVC.draftTweet = original
			}
			
		default: break 
    	}
    }
}

