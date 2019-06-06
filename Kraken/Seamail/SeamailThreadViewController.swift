//
//  SeamailThreadViewController.swift
//  Kraken
//
//  Created by Chall Fry on 5/15/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit
import CoreData

class SeamailThreadViewController: BaseCollectionViewController {

	var threadModel: SeamailThread?
	
	let frcDataSource = FetchedResultsControllerDataSource<SeamailMessage>()
	let filterDataSource = FilteringDataSource()
	let dataManager = SeamailDataManager.shared
	private let coreData = LocalCoreData.shared

    override func viewDidLoad() {
        super.viewDidLoad()
        
 		let fetchRequest = NSFetchRequest<SeamailMessage>(entityName: "SeamailMessage")
 		if let model = threadModel {
			fetchRequest.predicate = NSPredicate(format: "thread.id = '\(model.id)'")
		} 
		else {
			fetchRequest.predicate = NSPredicate(value: false)
		}
		fetchRequest.sortDescriptors = [ NSSortDescriptor(key: "timestamp", ascending: false)]
		let fetchedResults = NSFetchedResultsController(fetchRequest: fetchRequest,
				managedObjectContext: coreData.mainThreadContext, sectionNameKeyPath: nil, cacheName: nil)
		try? fetchedResults.performFetch()
		frcDataSource.setup(collectionView: collectionView, frc: fetchedResults,
				createCellModel: createMessageCellModel, reuseID: "SeamailMessageCell")
		frcDataSource.overrideReuseID = overrideReuseID
		collectionView.register(UINib(nibName: "SeamailMessageCell", bundle: nil), forCellWithReuseIdentifier: "SeamailMessageCell")
		collectionView.register(UINib(nibName: "SeamailSelfMessageCell", bundle: nil), forCellWithReuseIdentifier: "SeamailSelfMessageCell")
				
		filterDataSource.collectionView = collectionView
		filterDataSource.viewController = self
		filterDataSource.appendSection(named: "PostingSection")
		filterDataSource.appendSection(section: frcDataSource)
		collectionView.dataSource = filterDataSource
		collectionView.delegate = filterDataSource
    }
    
	func createMessageCellModel(_ model:SeamailMessage) -> BaseCellModel {
		return SeamailMessageCellModel(withModel: model, reuse: "SeamailMessageCell")
	}
    
    func overrideReuseID(_ model: SeamailMessage) -> String? {
    	if model.author.username == CurrentUser.shared.loggedInUser?.username {
    		return "SeamailSelfMessageCell"
    	}
    	else {
    		return "SeamailMessageCell"
    	}
    }
    
}
