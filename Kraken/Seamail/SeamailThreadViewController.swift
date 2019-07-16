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
	
	var postingCell = TextViewCellModel("")
	var sendButtonCell: ButtonCellModel?

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
		frcDataSource.setup(viewController: self, collectionView: collectionView, frc: fetchedResults,
				createCellModel: createMessageCellModel, reuseID: "SeamailMessageCell")
		collectionView.register(UINib(nibName: "SeamailMessageCell", bundle: nil), forCellWithReuseIdentifier: "SeamailMessageCell")
		collectionView.register(UINib(nibName: "SeamailSelfMessageCell", bundle: nil), forCellWithReuseIdentifier: "SeamailSelfMessageCell")
				
		filterDataSource.collectionView = collectionView
		filterDataSource.viewController = self
		filterDataSource.appendSection(section: frcDataSource)
		let postingSection = filterDataSource.appendSection(named: "PostingSection")
		
		postingSection.append(postingCell)
		sendButtonCell = ButtonCellModel(title: "Send", action: sendButtonHit)
		postingSection.append(sendButtonCell!)
		filterDataSource.register(with: collectionView, viewController: self)
    }
    
	func createMessageCellModel(_ model:SeamailMessage) -> BaseCellModel {
			return SeamailMessageCellModel(withModel: model, reuse: "SeamailMessageCell")
	}
	
	func sendButtonHit() {
		print ("meh")
	}
	
}
