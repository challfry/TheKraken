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
	}
    
    override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		tweetDataSource.enableAnimations = true
	}

	func createCellModel(_ model:PostOpTweet) -> BaseCellModel {
		let cellModel =  TwitarrTweetOpCellModel(withModel: model)
		return cellModel
	}
	
// MARK: Navigation
	override var knownSegues : Set<GlobalKnownSegue> {
		Set<GlobalKnownSegue>([ .userProfile, .editTweetOp ])
	}
}

