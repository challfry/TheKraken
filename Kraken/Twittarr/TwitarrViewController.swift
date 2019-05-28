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
	var tweetDataSource = FetchedResultsControllerDataSource<TwitarrPost, TwitarrTweetCell>()

	var customGR: UILongPressGestureRecognizer?
	var tappedCell: UICollectionViewCell?
	
//	private var collectionViewUpdateBlocks: [() -> Void] = []

	override func viewDidLoad() {
        super.viewDidLoad()
        
		collectionView.refreshControl = UIRefreshControl()
		collectionView.refreshControl?.addTarget(self, action: #selector(self.self.startRefresh), for: .valueChanged)
 		TwitarrTweetCell.registerCells(with:collectionView)
 		tweetDataSource.setup(collectionView: collectionView, frc: dataManager.fetchedData, setupCell: setupTweetCell, 
 				reuseID: "tweet")
		collectionView.dataSource = tweetDataSource
		collectionView.delegate = tweetDataSource
 		collectionView.prefetchDataSource = tweetDataSource

        // Do any additional setup after loading the view.
		try! self.dataManager.fetchedData.performFetch()
		startRefresh()
		
		title = dataManager.filter ?? "Twitarr"
		setupGestureRecognizer()
	}
    
    override func viewWillAppear(_ animated: Bool) {
		dataManager.addDelegate(tweetDataSource)
	}
	
    override func viewWillDisappear(_ animated: Bool) {
		dataManager.removeDelegate(tweetDataSource)
	}
	
	func setupTweetCell(cell: TwitarrTweetCell, fromModel: TwitarrPost) {
		cell.tweetModel = fromModel
	}
    
	@objc func startRefresh() {
		dataManager.loadNewestTweets() {
			DispatchQueue.main.async { self.collectionView.refreshControl?.endRefreshing() }
		}
    }

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
		if segue.identifier == "TweetFilter", let destVC = segue.destination as? TwitarrViewController,
				let filterString = sender as? String {
			destVC.dataManager = TwitarrDataManager(filterString: filterString)
		}
		else if segue.identifier == "UserProfile", let destVC = segue.destination as? UserProfileViewController,
				let username = sender as? String {
			destVC.modelUserName = username
		}
    }
    
}

extension TwitarrViewController: UIGestureRecognizerDelegate {

	func setupGestureRecognizer() {	
		let tapper = UILongPressGestureRecognizer(target: self, action: #selector(TwitarrViewController.tweetCellTapped))
		tapper.minimumPressDuration = 0.1
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
		if let _ = collectionView.indexPathForItem(at: hitPoint) {
			return true
		}
		
		return false
	}

	@objc func tweetCellTapped(_ sender: UILongPressGestureRecognizer) {
		if sender.state == .began {
			if let indexPath = collectionView.indexPathForItem(at: sender.location(in:collectionView)) {
				tappedCell = collectionView.cellForItem(at: indexPath)
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
				let indexPath = collectionView.indexPath(for: tappedCell)
				collectionView.selectItem(at: indexPath, animated: true, scrollPosition: .left)
			}
		} 
		
		if sender.state == .ended || sender.state == .cancelled || sender.state == .failed {
			tappedCell.isHighlighted = false
		}
	}
	
}

   
// Lumping all of these extensions together since they're indistinguishable from each other
//extension TwitarrViewController: UICollectionViewDataSource, UICollectionViewDelegate,  UICollectionViewDelegateFlowLayout {
//
//	func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
//		guard let sections = self.dataManager.fetchedData.sections else {
//			fatalError("No sections in fetchedResultsController")
//		}
//		let sectionInfo = sections[section]
//		return sectionInfo.numberOfObjects
//	}
//	    
//	func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
//		let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "tweet", for: indexPath) as! TwitarrTweetCell
//		cell.viewController = self
//		cell.collectionViewSize = collectionView.bounds.size
//
//		let object = self.dataManager.fetchedData.object(at: indexPath) 
//		cell.tweetModel = object
//
//		return cell
//	}
//
//	func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, 
//			sizeForItemAt indexPath: IndexPath) -> CGSize {
//		let model = dataManager.fetchedData.object(at: indexPath)
//
////		let sectionInset = collectionViewLayout.sectionInset
////		let widthToSubtract = sectionInset!.left + sectionInset!.right
//	//	let requiredWidth = collectionView.bounds.size.width
//	
//		if let protoCell = TwitarrTweetCell.makePrototypeCell(for: collectionView, indexPath: indexPath) {
//			protoCell.tweetModel = model
//			if let selection = collectionView.indexPathsForSelectedItems, selection.contains(indexPath) {
//				protoCell.isSelected = true
//			}
//			else {
//				protoCell.isSelected = false
//			}
//
//			let newSize = protoCell.calculateSize()
//   			return newSize
//		}
//
//		return CGSize(width:414, height: 50)
//	}
//}
//
//extension TwitarrViewController: NSFetchedResultsControllerDelegate {
//			
//	func controllerWillChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
//		collectionViewUpdateBlocks.removeAll(keepingCapacity: false)
//	}
//
//	func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange anObject: Any,
//			at indexPath: IndexPath?, for type: NSFetchedResultsChangeType, newIndexPath: IndexPath?) {
//
//		switch type {
//		case .insert:
//			guard let newIndexPath = newIndexPath else { return }
//			collectionViewUpdateBlocks.append( { self.collectionView.insertItems(at: [newIndexPath]); print ("Insert at \(newIndexPath)") })
//		case .delete:
//			guard let indexPath = indexPath else { return }
//			collectionViewUpdateBlocks.append( { self.collectionView.deleteItems(at: [indexPath]); print ("Delete at \(indexPath)") })
//		case .move:
//			guard let indexPath = indexPath,  let newIndexPath = newIndexPath else { return }
//			collectionViewUpdateBlocks.append( { self.collectionView.moveItem(at: indexPath, to: newIndexPath); print ("Move from \(indexPath) to \(newIndexPath)") })
//		case .update:
//			guard let indexPath = indexPath else { return }
//			collectionViewUpdateBlocks.append( { self.collectionView.reloadItems(at: [indexPath]); print ("Update at \(indexPath)") })
//		@unknown default:
//			fatalError()
//		}
//	}
//
//	func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
//		runUpdates()	
//	}
//}
//
//extension TwitarrViewController: UICollectionViewDataSourcePrefetching {
//
//	func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
//		print ("Prefetch at: \(indexPaths)")
//	}
//
//	func collectionView(_ collectionView: UICollectionView, cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {
//		print ("Cancel \(indexPaths)")
//	}
//}
