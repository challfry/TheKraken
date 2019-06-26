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
	
	override func awakeFromNib() {
		super.awakeFromNib()
		
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

	}

}
