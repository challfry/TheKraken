//
//  TwitarrViewController.swift
//  Kraken
//
//  Created by Chall Fry on 3/22/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit
import CoreData

class TwitarrViewController: BaseCollectionViewController {
	@IBOutlet var postButton: UIBarButtonItem!

	// For VCs that show a filtered view (@Author/#Hashtag/@Mention/String Search) this is where we store the filter
	var dataManager = TwitarrDataManager.shared
	var tweetDataSource = KrakenDataSource()
	
	override func viewDidLoad() {
        super.viewDidLoad()
        
		collectionView.refreshControl = UIRefreshControl()
		collectionView.refreshControl?.addTarget(self, action: #selector(self.self.startRefresh), for: .valueChanged)
 
 		tweetDataSource.register(with: collectionView, viewController: self)
 		
 		let loadingSegment = FilteringDataSourceSegment() 
 		let statusCell = OperationStatusCellModel()
 		statusCell.statusText = "Loading Twitarr Posts"
 		statusCell.shouldBeVisible = true
 		loadingSegment.append(statusCell)
 		tweetDataSource.append(segment: loadingSegment)
 		
		let tweetSegment = FRCDataSourceSegment<TwitarrPost>(withCustomFRC: dataManager.fetchedData)
		dataManager.addDelegate(tweetSegment)
  		tweetDataSource.append(segment: tweetSegment)
		tweetSegment.activate(predicate: nil, sort: nil, cellModelFactory: createCellModel)
		
        // Do any additional setup after loading the view.
		startRefresh()
		title = dataManager.filter ?? "Twitarr"
		setupGestureRecognizer()
	}
    
    override func viewWillAppear(_ animated: Bool) {
		tweetDataSource.enableAnimations = true
	}
			
	func createCellModel(_ model:TwitarrPost) -> BaseCellModel {
		return TwitarrTweetCellModel(withModel: model, reuse: "tweet")
	}
    
	@objc func startRefresh() {
		dataManager.loadNewestTweets() {
			DispatchQueue.main.async { self.collectionView.refreshControl?.endRefreshing() }
		}
    }

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
    	switch segue.identifier {
			// A filtered view of the tweet stream.
		case "TweetFilter":
			if let destVC = segue.destination as? TwitarrViewController, let filterString = sender as? String {
				destVC.dataManager = TwitarrDataManager(filterString: filterString)
			}
			
			// PostOpTweets by this user, that are replies to a given tweet.
		case "PendingReplies":
			if let destVC = segue.destination as? PendingTwitarrRepliesVC, let parent = sender as? TwitarrPost {
				destVC.parentTweet = parent
			}
			
		case "UserProfile":
			if let destVC = segue.destination as? UserProfileViewController, let username = sender as? String {
				destVC.modelUserName = username
			}

		case "ModalLogin":
			if let destVC = segue.destination as? ModalLoginViewController, let package = sender as? LoginSegueWithAction {
				destVC.segueData = package
			}
			
		case "ComposeReplyTweet":
			if let destVC = segue.destination as? ComposeTweetViewController, let parent = sender as? TwitarrPost {
				destVC.parentTweet = parent
			}
			
		case "EditTweet":
			if let destVC = segue.destination as? ComposeTweetViewController, let original = sender as? TwitarrPost {
				destVC.editTweet = original
			}
			
		// Some segues legit don't need us to do anything.
		case "ComposeTweet": break
		default: break 
    	}
    }
    
	@IBAction func dismissingLoginModal(_ segue: UIStoryboardSegue) {
		// Try to continue whatever we were doing before having to log in.
		if let loginVC = segue.source as? ModalLoginViewController {
			if CurrentUser.shared.isLoggedIn() {
				loginVC.segueData?.loginSuccessAction?()
			}
			else {
				loginVC.segueData?.loginFailureAction?()
			}
		}
	}	
    
}

