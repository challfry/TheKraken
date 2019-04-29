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

	// For VCs that show a filtered view (@Author/#Hashtag/@Mention/String Search) this is where we store the filter
	var dataManager = TwitarrDataManager.shared

	private var collectionViewUpdateBlocks: [() -> Void] = []

	override func viewDidLoad() {
        super.viewDidLoad()
        
		collectionView.refreshControl = UIRefreshControl()
		collectionView.refreshControl?.addTarget(self, action: #selector(self.self.startRefresh), for: .valueChanged)
 		collectionView.prefetchDataSource = self

        // Do any additional setup after loading the view.
		try! self.dataManager.fetchedData.performFetch()
		startRefresh()
		
		title = dataManager.filter ?? "Twitarr"
		
		
    }
    
    override func viewWillAppear(_ animated: Bool) {
		dataManager.addDelegate(self)
	}
	
    override func viewWillDisappear(_ animated: Bool) {
		dataManager.removeDelegate(self)
	}
    
	@objc func startRefresh() {
		dataManager.loadNewestTweets() {
			DispatchQueue.main.async { self.collectionView.refreshControl?.endRefreshing() }
		}
    }
    

	// MARK: - Navigation

	var filterForNextVC: String?
    func pushSubController(forFilterString: String) {
    	filterForNextVC = forFilterString
    	self.performSegue(withIdentifier: "TweetFilter", sender: self)
    }
    
    var userNameForUserProfileVC: String?
    func pushUserProfileController(forUser: String) {
    	userNameForUserProfileVC = forUser
    	self.performSegue(withIdentifier: "UserProfile", sender: self)
    }

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
		if segue.identifier == "TweetFilter", let destVC = segue.destination as? TwitarrViewController {
			destVC.dataManager = TwitarrDataManager(filterString: filterForNextVC)
		}
		else if segue.identifier == "UserProfile", let destVC = segue.destination as? UserProfileViewController {
			
			destVC.modelUserName = userNameForUserProfileVC
		}
    }
    
}
   
// Lumping all of these extensions together since they're indistinguishable from each other
extension TwitarrViewController: UICollectionViewDataSource, UICollectionViewDelegate,  UICollectionViewDelegateFlowLayout {

	func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
		guard let sections = self.dataManager.fetchedData.sections else {
			fatalError("No sections in fetchedResultsController")
		}
		let sectionInfo = sections[section]
		return sectionInfo.numberOfObjects
	}
	    
	func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
		let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "tweet", for: indexPath) as! TwitarrTweetCell
		cell.viewController = self

		let object = self.dataManager.fetchedData.object(at: indexPath) 
		cell.tweetModel = object

		return cell
	}

}

// Have to change this:
//Operations order in PerformBatchUpdates
//
//Deletes → Always use original indexes (will be used in descending order)
//Inserts → Always use final indexes (will be used in ascending order)
//Moves → From = original index; To = final index
//Reload → Under the hood, it deletes then inserts. Index = original index. You can't reload an item that is moved.

extension TwitarrViewController: NSFetchedResultsControllerDelegate {
			
	func controllerWillChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
		collectionViewUpdateBlocks.removeAll(keepingCapacity: false)
	}

	func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange anObject: Any,
			at indexPath: IndexPath?, for type: NSFetchedResultsChangeType, newIndexPath: IndexPath?) {

		switch type {
		case .insert:
			guard let newIndexPath = newIndexPath else { return }
			collectionViewUpdateBlocks.append( { self.collectionView.insertItems(at: [newIndexPath]); print ("Insert at \(newIndexPath)") })
		case .delete:
			guard let indexPath = indexPath else { return }
			collectionViewUpdateBlocks.append( { self.collectionView.deleteItems(at: [indexPath]); print ("Delete at \(indexPath)") })
		case .move:
			guard let indexPath = indexPath,  let newIndexPath = newIndexPath else { return }
			collectionViewUpdateBlocks.append( { self.collectionView.moveItem(at: indexPath, to: newIndexPath); print ("Move from \(indexPath) to \(newIndexPath)") })
		case .update:
			guard let indexPath = indexPath else { return }
			collectionViewUpdateBlocks.append( { self.collectionView.reloadItems(at: [indexPath]); print ("Update at \(indexPath)") })
		@unknown default:
			fatalError()
		}
	}

	func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
		collectionView.performBatchUpdates({
			self.collectionViewUpdateBlocks.forEach { $0() }
		}, completion: { finished in
			self.collectionViewUpdateBlocks.removeAll(keepingCapacity: false)
		})
	}

}

extension TwitarrViewController: UICollectionViewDataSourcePrefetching {

	func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
		print ("Prefetch at: \(indexPaths)")
	}

	func collectionView(_ collectionView: UICollectionView, cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {
		print ("Cancel \(indexPaths)")
	}
}
