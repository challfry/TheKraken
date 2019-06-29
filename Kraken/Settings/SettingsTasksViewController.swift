//
//  SettingsTasksViewController.swift
//  Kraken
//
//  Created by Chall Fry on 6/25/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit
import CoreData

class SettingsTasksViewController: BaseCollectionViewController, NSFetchedResultsControllerDelegate {
	var controller: NSFetchedResultsController<PostOperation>?
	let dataSource = FilteringDataSource()
		
    override func viewDidLoad() {
		super.viewDidLoad()
  		dataSource.register(with: collectionView, viewController: self)
  		dataSource.viewController = self
		
		let context = LocalCoreData.shared.mainThreadContext
		let fetchRequest = NSFetchRequest<PostOperation>(entityName: "PostOperation")
		fetchRequest.sortDescriptors = [NSSortDescriptor(key: "originalPostTime", ascending: true)]
		controller = NSFetchedResultsController(fetchRequest: fetchRequest, managedObjectContext: context, 
				sectionNameKeyPath: nil, cacheName: nil)
		controller?.delegate = self
		do {
			try controller?.performFetch()
			controllerDidChangeContent(controller as! NSFetchedResultsController<NSFetchRequestResult>)
		} catch {
			fatalError("Failed to fetch entities: \(error)")
		}
	}
	
	
	
	func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
		if let tasks = controller.fetchedObjects {
			var x = 0
			for task in tasks {
				x = x + 1
				let taskSection = dataSource.appendSection(named: "\(x)")
				
				if let reactionTask = task as? PostOpTweetReaction {
					if reactionTask.isAdd {
						taskSection.append(SettingsInfoCellModel("\(x):  Add a \"Like\" reaction to this tweet:"))
					}
					else {
						taskSection.append(SettingsInfoCellModel("\(x):  Cancel the \"Like\" on this tweet:"))
					}
					
					let model = TwitarrTweetCellModel(withModel:reactionTask.sourcePost, reuse: "tweet")
					model.isInteractive = false
					taskSection.append(model)
				}
				else if let postTask = task as? PostOpTweet {
					let cellModel = TwitarrTweetCellModel(withModel: postTask, reuse: "tweet")
					cellModel.isInteractive = false
					taskSection.append(SettingsInfoCellModel("\(x): Post a new Twitarr tweet:"))
					taskSection.append(cellModel)
				}
				
			}		
		} 
	}

}
