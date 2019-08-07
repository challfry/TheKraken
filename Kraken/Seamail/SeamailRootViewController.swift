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
	@IBOutlet var newThreadButton: UIBarButtonItem!

	let loginDataSource = KrakenDataSource()
	let loginSection = LoginDataSourceSegment()
	let threadDataSource = KrakenDataSource()
	lazy var threadSegment = FRCDataSourceSegment<SeamailThread>(withCustomFRC: dataManager.fetchedData)
	let dataManager = SeamailDataManager.shared
	
	override func viewDidLoad() {
        super.viewDidLoad()
        
        //
        loginDataSource.append(segment: loginSection)
		loginSection.headerCellText = "In order to see your Seamail, you will need to log in first."

		threadDataSource.append(segment: threadSegment)
		threadSegment.activate(predicate: nil, sort: nil, cellModelFactory: createCellModel)
		dataManager.addDelegate(threadSegment)
       
        CurrentUser.shared.tell(self, when: "loggedInUser") { observer, observed in
        	if observed.loggedInUser == nil {
				observer.loginDataSource.register(with: observer.collectionView, viewController: observer)
				observer.newThreadButton.isEnabled = false
				self.navigationController?.popToRootViewController(animated: false)
        	}
        	else {
         		observer.threadDataSource.register(with: observer.collectionView, viewController: observer)
        		observer.dataManager.loadSeamails { 
					DispatchQueue.main.async { observer.collectionView.reloadData() }
				}
				observer.newThreadButton.isEnabled = true
       		}
        }?.execute()        

		title = "Seamail"
    }
    
    override func viewDidAppear(_ animated: Bool) {
		loginDataSource.enableAnimations = true
		threadDataSource.enableAnimations = true
		loginSection.clearAllSensitiveFields()
	}
	
	// Gets called from within collectionView:cellForItemAt:
	func createCellModel(_ model:SeamailThread) -> BaseCellModel {
		let cellModel = SeamailThreadCellModel(withModel: model, reuse: "seamailThread")
		return cellModel
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
