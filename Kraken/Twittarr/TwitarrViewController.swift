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
	var tweetDataSource = FetchedResultsControllerDataSource<TwitarrPost>()

	var customGR: UILongPressGestureRecognizer?
	var tappedCell: UICollectionViewCell?
	
//	private var collectionViewUpdateBlocks: [() -> Void] = []

	override func viewDidLoad() {
        super.viewDidLoad()
        
		collectionView.refreshControl = UIRefreshControl()
		collectionView.refreshControl?.addTarget(self, action: #selector(self.self.startRefresh), for: .valueChanged)
 		TwitarrTweetCell.registerCells(with:collectionView)
		try! self.dataManager.fetchedData.performFetch()
 		tweetDataSource.setup(viewController: self, collectionView: collectionView, frc: dataManager.fetchedData, 
 				createCellModel: createCellModel, reuseID: "tweet")
		collectionView.dataSource = tweetDataSource
		collectionView.delegate = tweetDataSource
 		collectionView.prefetchDataSource = tweetDataSource

        // Do any additional setup after loading the view.
		startRefresh()
		
		title = dataManager.filter ?? "Twitarr"
		setupGestureRecognizer()
	}
    
    override func viewWillAppear(_ animated: Bool) {
		dataManager.addDelegate(tweetDataSource)
		tweetDataSource.enableAnimations = true
	}
	
    override func viewDidAppear(_ animated: Bool) {
		tweetDataSource.enableAnimations = true
	}
	
    override func viewWillDisappear(_ animated: Bool) {
		dataManager.removeDelegate(tweetDataSource)
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
		case "TweetFilter":
			if let destVC = segue.destination as? TwitarrViewController, let filterString = sender as? String {
				destVC.dataManager = TwitarrDataManager(filterString: filterString)
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

extension TwitarrViewController: UIGestureRecognizerDelegate {

	func setupGestureRecognizer() {	
		let tapper = UILongPressGestureRecognizer(target: self, action: #selector(TwitarrViewController.tweetCellTapped))
		tapper.minimumPressDuration = 0.05
		tapper.numberOfTouchesRequired = 1
		tapper.numberOfTapsRequired = 0
		tapper.allowableMovement = 10.0
		tapper.delegate = self
		tapper.name = "TwitarrViewController Long Press"
		collectionView.addGestureRecognizer(tapper)
		customGR = tapper
	}

	func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
		// need to call super if it's not our recognizer
		if gestureRecognizer != customGR {
			return false
		}
		let hitPoint = gestureRecognizer.location(in: collectionView)
		if !collectionView.point(inside:hitPoint, with: nil) {
			return false
		}
		
		// Only take the tap if the cell isn't already selected. This ensures taps on widgets inside the cell go through
		// once the cell is selected.
		if let path = collectionView.indexPathForItem(at: hitPoint), let cell = collectionView.cellForItem(at: path),
				let c = cell as? TwitarrTweetCell, !c.privateSelected {
			return true
		}
		
		return false
	}

	@objc func tweetCellTapped(_ sender: UILongPressGestureRecognizer) {
		if sender.state == .began {
			if let indexPath = collectionView.indexPathForItem(at: sender.location(in:collectionView)) {
				tappedCell = collectionView.cellForItem(at: indexPath)
				tappedCell?.isHighlighted = true
			}
			else {
				tappedCell = nil
			}
		}
		guard let tappedCell = tappedCell else { return }
		
		if sender.state == .changed {
			tappedCell.isHighlighted = tappedCell.point(inside:sender.location(in: tappedCell), with: nil)
		}
		else if sender.state == .ended {
			if tappedCell.isHighlighted {
//				let indexPath = collectionView.indexPath(for: tappedCell)
//				collectionView.selectItem(at: indexPath, animated: true, scrollPosition: .left)
				
				if let tc = tappedCell as? TwitarrTweetCell {
					tc.privateSelectCell()
				}
			}
		} 
		
		if sender.state == .ended || sender.state == .cancelled || sender.state == .failed {
			tappedCell.isHighlighted = false
			
			// Stop the scroll view's odd scrolling behavior that happens when cell tap resizes the cell.
			collectionView.setContentOffset(collectionView.contentOffset, animated: false)
		}
	}
	
}

