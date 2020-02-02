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
	var filterPack: TwitarrFilterPack?	
	
	let dataManager = TwitarrDataManager.shared
	var tweetDataSource = KrakenDataSource()
		var loadingSegment = FilteringDataSourceSegment() 
		var tweetSegment = FRCDataSourceSegment<TwitarrPost>()

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
        
		// Set up our filterpack, if we don't have one provided
        if filterPack == nil {
        	filterPack = TwitarrFilterPack(author: nil, text: nil)
        }
		title = filterPack?.filterTitle ?? "Twitarr"
		filterPack?.checkLoadRequiredFor(index: 0)
       
		collectionView.refreshControl = UIRefreshControl()
		collectionView.refreshControl?.addTarget(self, action: #selector(self.self.startRefresh), for: .valueChanged)
 
 		tweetDataSource.register(with: collectionView, viewController: self)
 		tweetDataSource.append(segment: loadingSegment)
		loadingSegment.append(statusCell)
 		
  		tweetDataSource.append(segment: tweetSegment)
		tweetSegment.loaderDelegate = filterPack
		tweetSegment.activate(predicate: filterPack?.predicate, sort: filterPack?.sortDescriptors, cellModelFactory: createCellModel)
		filterPack?.frc = tweetSegment.frc
		
		knownSegues = Set([.tweetFilter, .pendingReplies, .userProfile, .modalLogin, .composeReplyTweet, .editTweet,
				.composeTweet])
	}
    
    override func viewWillAppear(_ animated: Bool) {
		tweetDataSource.enableAnimations = true
	}
	
	override func viewDidAppear(_ animated: Bool) {
		// Every time our view appears, make sure the visible tweets have a 'fresh' cache status.
		if collectionView.indexPathsForVisibleItems.count > 0 {
			collectionView.indexPathsForVisibleItems.forEach { filterPack?.checkLoadRequiredFor(index: $0.row) }
		}
		else {
			filterPack?.checkLoadRequiredFor(index: 0)
		}
	}
			
	func createCellModel(_ model:TwitarrPost) -> BaseCellModel {
		let cellModel =  TwitarrTweetCellModel(withModel: model)
		cellModel.viewController = self
		return cellModel
	}
    
	@objc func startRefresh() {
		dataManager.loadNewestTweets(filterPack) {
			DispatchQueue.main.async { self.collectionView.refreshControl?.endRefreshing() }
		}
    }

	// This is the unwind segue from the Tweet compose view.
	@IBAction func dismissingPostingView(_ segue: UIStoryboardSegue) {
	}	
}

