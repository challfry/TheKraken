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
	var filterPack: TwitarrFilterPack = TwitarrFilterPack(author: nil, text: nil)	
	
	let dataManager = TwitarrDataManager.shared
	var tweetDataSource = KrakenDataSource()
		var loadingSegment = FilteringDataSourceSegment() 
		var tweetSegment = FRCDataSourceSegment<TwitarrPost>()

	let loginDataSource = KrakenDataSource()
	let loginSection = LoginDataSourceSegment()

	lazy var statusCell: LoadingStatusCellModel = {
 		let cell = LoadingStatusCellModel()
 		cell.statusText = "Loading Twitarr Posts"
 		cell.shouldBeVisible = true
 		cell.showSpinner = true
 		dataManager.tell(cell, when: "networkUpdateActive") { observer, observed in
 			observer.shouldBeVisible = observed.networkUpdateActive  		
 		}
 		return cell
	}()
	
	override func viewDidLoad() {
        super.viewDidLoad()
        
 		tweetDataSource.append(segment: loadingSegment)
		loadingSegment.append(statusCell)
 		
  		tweetDataSource.append(segment: tweetSegment)
		tweetSegment.loaderDelegate = filterPack
		tweetSegment.activate(predicate: filterPack.predicate, sort: filterPack.sortDescriptors, cellModelFactory: createCellModel)
		filterPack.frc = tweetSegment.frc
		
        loginDataSource.append(segment: loginSection)
		loginSection.headerCellText = "In order to see the Twitarr stream, you will need to log in first."

		// When a user is logged in we'll set up the FRC to load the threads which that user can 'see'. Remember, CoreData
		// stores ALL the seamail we ever download, for any user who logs in on this device.
        CurrentUser.shared.tell(self, when: "loggedInUser") { observer, observed in        		
			if let _ = observed.loggedInUser?.userID {
        		observer.tweetDataSource.register(with: observer.collectionView, viewController: observer)
				observer.postButton.isEnabled = true
				observer.collectionView.refreshControl = UIRefreshControl()
				observer.collectionView.refreshControl?.addTarget(self, action: #selector(self.self.startRefresh), for: .valueChanged)
				observer.startRefresh()
			}
       		else {
       			// If nobody's logged in, pop to root, show the login cells.
				observer.loginDataSource.register(with: observer.collectionView, viewController: observer)
				observer.postButton.isEnabled = false
				observer.navigationController?.popToViewController(observer, animated: false)
				observer.collectionView.refreshControl = nil
       		}
        }?.execute()        

		knownSegues = Set([.tweetFilter, .pendingReplies, .userProfile, .modalLogin, .composeReplyTweet, .editTweet,
				.composeTweet, .reportContent, .showLikeOptions])
	}
    
    override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		tweetDataSource.enableAnimations = true

		// Every time our view appears, make sure the visible tweets have a 'fresh' cache status.
		if collectionView.indexPathsForVisibleItems.count > 0 {
			collectionView.indexPathsForVisibleItems.forEach { filterPack.checkLoadRequiredFor(frcIndex: $0.row) }
		}
		else {
			filterPack.checkLoadRequiredFor(frcIndex: 0)
		}
	}
	
	override func viewDidAppear(_ animated: Bool) {
    	super.viewDidAppear(animated)
	}
			
	func createCellModel(_ model:TwitarrPost) -> BaseCellModel {
		let cellModel =  TwitarrTweetCellModel(withModel: model)
		cellModel.viewController = self
		return cellModel
	}
    
	@objc func startRefresh() {
		filterPack.loadNewestTweets() {
			DispatchQueue.main.async { self.collectionView.refreshControl?.endRefreshing() }
		}
    }

	// This is the unwind segue from the Tweet compose view.
	@IBAction func dismissingPostingView(_ segue: UIStoryboardSegue) {
	}	
}

