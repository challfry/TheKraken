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
	var tweetDataSource = FetchedResultsControllerDataSource<PostOpTweet>()

	override func viewDidLoad() {
        super.viewDidLoad()
		title = "Pending Replies"       

 		TwitarrTweetCell.registerCells(with:collectionView)

		let fetchRequest = NSFetchRequest<PostOpTweet>(entityName: "PostOpTweet")
		fetchRequest.sortDescriptors = [ NSSortDescriptor(key: "originalPostTime", ascending: true)]
		fetchRequest.fetchBatchSize = 50
		if let currentUsername = CurrentUser.shared.loggedInUser?.username, let parent = parentTweet {
			fetchRequest.predicate = NSPredicate(format: "parent == %@ AND author.username == %@", 
					parent, currentUsername)
			let fetchedData = NSFetchedResultsController(fetchRequest: fetchRequest, 
					managedObjectContext: LocalCoreData.shared.mainThreadContext, 
					sectionNameKeyPath: nil, cacheName: nil)
			do {
				try fetchedData.performFetch()
			}
			catch {
				CoreDataLog.error("Couldn't fetch pending replies.", [ "error" : error ])
			}
			tweetDataSource.setup(viewController: self, collectionView: collectionView, frc: fetchedData, 
 					createCellModel: createCellModel, reuseID: "tweet")
		}
		setupGestureRecognizer()
  }
    
    override func viewWillAppear(_ animated: Bool) {
		tweetDataSource.enableAnimations = true
	}

	func createCellModel(_ model:PostOpTweet) -> BaseCellModel {
		return TwitarrTweetCellModel(withModel: model, reuse: "tweet")
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

