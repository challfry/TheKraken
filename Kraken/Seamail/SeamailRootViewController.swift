//
//  SeamailRootViewController.swift
//  Kraken
//
//  Created by Chall Fry on 3/29/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit
import CoreData

class SeamailRootViewController: BaseCollectionViewController {
	let loginDataSource = LoginDataSource()
	let frcDataSource = FetchedResultsControllerDataSource<SeamailThread, SeamailThreadCell>()
	let dataManager = SeamailDataManager.shared
	
	override func viewDidLoad() {
        super.viewDidLoad()
        loginDataSource.viewController = self
		loginDataSource.headerCellText = "In order to see your Seamail, you will need to log in first."
		frcDataSource.setup(collectionView: collectionView, frc: dataManager.fetchedData,
				setupCell: setupThreadCell, reuseID: "seamailThread")
  		SeamailThreadCell.registerCells(with:collectionView)
    	view.addGestureRecognizer(UITapGestureRecognizer(target: view, action: #selector(UIView.endEditing(_:))))
       
        CurrentUser.shared.tell(self, when: "loggedInUser") { observer, observed in
        	if observed.loggedInUser == nil {
				observer.loginDataSource.register(with: observer.collectionView)
				observer.dataManager.removeDelegate(observer.frcDataSource)
        	}
        	else {
       			observer.collectionView.dataSource = observer.frcDataSource
        		observer.collectionView.delegate = observer.frcDataSource
  				observer.dataManager.addDelegate(observer.frcDataSource)
        		observer.dataManager.loadSeamails { 
					DispatchQueue.main.async { observer.collectionView.reloadData() }
				}
       	}
        }?.execute()        

		title = "Seamail"
    }
    
    override func viewDidAppear(_ animated: Bool) {
		loginDataSource.enableAnimations = true
	}
	
	// Gets called from within collectionView:cellForItemAt:
	func setupThreadCell(_ cell: UICollectionViewCell, _ modelObject: NSManagedObject) {
		guard let threadCell = cell as? SeamailThreadCell, let thread = modelObject as? SeamailThread else { return }
		threadCell.viewController = self
		threadCell.threadModel = thread
	}

    
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
		if segue.identifier == "UserProfile", let destVC = segue.destination as? UserProfileViewController,
				let userName = sender as? String {
			destVC.modelUserName = userName
		}
		else if segue.identifier == "ShowSeamailThread", let destVC = segue.destination as? SeamailThreadViewController,
				let threadModel = sender as? SeamailThread {
			destVC.threadModel = threadModel
		}
    }

}
