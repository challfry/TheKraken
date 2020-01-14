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
 		let statusCell = LoadingStatusCellModel()
 		statusCell.statusText = "Loading Twitarr Posts"
 		statusCell.shouldBeVisible = true
 		statusCell.showSpinner = true
 		loadingSegment.append(statusCell)
 		tweetDataSource.append(segment: loadingSegment)
 		dataManager.tell(self, when: "networkUpdateActive") { observer, observed in
 			statusCell.shouldBeVisible = observed.networkUpdateActive  		
 		}
 		
 		
		let tweetSegment = FRCDataSourceSegment<TwitarrPost>(withCustomFRC: dataManager.fetchedData)
		dataManager.addDelegate(tweetSegment)
  		tweetDataSource.append(segment: tweetSegment)
		tweetSegment.loaderDelegate = dataManager
		tweetSegment.activate(predicate: nil, sort: nil, cellModelFactory: createCellModel)
		
        // Do any additional setup after loading the view.
		startRefresh()
		title = dataManager.filter ?? "Twitarr"
		setupGestureRecognizer()
		
		knownSegues = Set([.tweetFilter, .pendingReplies, .userProfile, .modalLogin, .composeReplyTweet, .editTweet,
				.composeTweet])
	}
    
    override func viewWillAppear(_ animated: Bool) {
		tweetDataSource.enableAnimations = true
	}
			
	func createCellModel(_ model:TwitarrPost) -> BaseCellModel {
		let cellModel =  TwitarrTweetCellModel(withModel: model)
		cellModel.viewController = self
		return cellModel
	}
    
	@objc func startRefresh() {
		dataManager.loadNewestTweets() {
			DispatchQueue.main.async { self.collectionView.refreshControl?.endRefreshing() }
		}
    }

	// This is the unwind segue from the login modal.
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
    
	// This is the unwind segue from the Tweet compose view.
	@IBAction func dismissingPostingView(_ segue: UIStoryboardSegue) {
	}	
}

