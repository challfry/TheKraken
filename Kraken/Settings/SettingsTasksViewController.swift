//
//  SettingsTasksViewController.swift
//  Kraken
//
//  Created by Chall Fry on 6/25/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit
import CoreData

class SettingsTasksViewController: BaseCollectionViewController  {
	var controller: NSFetchedResultsController<PostOperation>?
	let dataSource = KrakenDataSource()
		
    override func viewDidLoad() {
		super.viewDidLoad()
  		dataSource.register(with: collectionView, viewController: self)
		
		let context = LocalCoreData.shared.mainThreadContext
		let fetchRequest = NSFetchRequest<PostOperation>(entityName: "PostOperation")
		fetchRequest.sortDescriptors = [NSSortDescriptor(key: "originalPostTime", ascending: true)]
		controller = NSFetchedResultsController(fetchRequest: fetchRequest, managedObjectContext: context, 
				sectionNameKeyPath: nil, cacheName: nil)
		controller?.delegate = self
		do {
			try controller?.performFetch()
			
			if let tasks = controller?.fetchedObjects {
				var x = 0
				for task in tasks {
					x = x + 1
					let newSection = makeNewSection(for: task, sectionIndex: x)
					dataSource.append(segment: newSection)
				}
			}
		} catch {
			CoreDataLog.error("Failed to fetch entities for PostOp tasks.", ["error" : error])
		}
	}	
		
    override func viewWillAppear(_ animated: Bool) {
		dataSource.enableAnimations = true
	}
	
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
    	switch segue.identifier {
		case "EditTweet":
			if let destVC = segue.destination as? ComposeTweetViewController, let tweet = sender as? PostOpTweet {
				destVC.draftTweet = tweet
			}
		case "EditSeamailThread":
			if let destVC = segue.destination as? ComposeSeamailThreadVC, let thread = sender as? PostOpSeamailThread {
				destVC.threadToEdit = thread
			}
		default: break 
		}
	}
}

// SettingsTasks maps a simple array of tasks from the FRC to an array of sections in the CollectionView.
// Each item in the FRC array is a section (usually with 3 cells in it) in the CV.
extension SettingsTasksViewController: NSFetchedResultsControllerDelegate {

	func makeNewSection(for task: PostOperation, sectionIndex: Int) -> KrakenDataSourceSegment {
		let taskSection = FilteringDataSourceSegment()
		taskSection.segmentName = "\(sectionIndex)"
		
		if let reactionTask = task as? PostOpTweetReaction {
			if reactionTask.isAdd {
				taskSection.append(SettingsInfoCellModel("Add a \"Like\" reaction to this tweet:", taskIndex: sectionIndex))
			}
			else {
				taskSection.append(SettingsInfoCellModel("Cancel the \"Like\" on this tweet:", taskIndex: sectionIndex))
			}
			
			let model = TwitarrTweetCellModel(withModel:reactionTask.sourcePost, reuse: "tweet")
			model.isInteractive = false
			taskSection.append(model)
			taskSection.append(TaskEditButtonsCellModel(forTask: reactionTask, vc: self))
		}
		else if let postTask = task as? PostOpTweet {
			let cellModel = TwitarrTweetCellModel(withModel: postTask, reuse: "tweet")
			cellModel.isInteractive = false
			if postTask.tweetToEdit != nil {
				taskSection.append(SettingsInfoCellModel("Post an edit to your tweet:", taskIndex: sectionIndex))
			}
			else if let parentTweet = postTask.parent {
				let parentUsername = parentTweet.author.username
				taskSection.append(SettingsInfoCellModel("Post a reply to a tweet by @\(parentUsername):", taskIndex: sectionIndex))
			}
			else {
				taskSection.append(SettingsInfoCellModel("Post a new Twitarr tweet:", taskIndex: sectionIndex))
			}
			taskSection.append(cellModel)
			taskSection.append(TaskEditButtonsCellModel(forTask: postTask, vc: self))
		}
		else if let deleteTask = task as? PostOpTweetDelete {
			let cellModel = TwitarrTweetCellModel(withModel: deleteTask.tweetToDelete, reuse: "tweet")
			cellModel.isInteractive = false
			taskSection.append(SettingsInfoCellModel("Delete this Twitarr tweet of yours:", taskIndex: sectionIndex))
			taskSection.append(cellModel)
			taskSection.append(TaskEditButtonsCellModel(forTask: deleteTask, vc: self))
		}
		else if let seamailPostTheadTask = task as? PostOpSeamailThread {
			let cellModel = SeamailThreadCellModel(withModel: task, reuse: "seamailThread")
			cellModel.isInteractive = false
			taskSection.append(SettingsInfoCellModel("Start a new Seamail Thread:", taskIndex: sectionIndex))
			taskSection.append(cellModel)
			taskSection.append(TaskEditButtonsCellModel(forTask: seamailPostTheadTask, vc: self))
		}
		else if let seamailPostMessageTask = task as? PostOpSeamailMessage {
			let cellModel = SeamailMessageCellModel(withModel: task, reuse: "SeamailSelfMessageCell")
			// cellModel.isInteractive = false
			taskSection.append(SettingsInfoCellModel("Send a Seamail Message:", taskIndex: sectionIndex))
			taskSection.append(cellModel)
			taskSection.append(TaskEditButtonsCellModel(forTask: seamailPostMessageTask, vc: self))
		}
		
		return taskSection
	}

	func controllerWillChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
	}
	
//	func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, 
//			didChange sectionInfo: NSFetchedResultsSectionInfo, atSectionIndex sectionIndex: Int, for type: NSFetchedResultsChangeType) {
//		switch type {
//		case .insert:
//			insertSections.insert(sectionIndex)
//		case .delete:
//			deleteSections.insert(sectionIndex)
//		default:
//			fatalError()
//		}
//	}
	
	// Repeating comment from above: ROWS in the FRC map to SECTIONS in the CollectionView.
	// The FRC has 1 section, and if it has 12 objects, then the CV has 12 sections.
	func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange anObject: Any,
			at indexPath: IndexPath?, for type: NSFetchedResultsChangeType, newIndexPath: IndexPath?) {

		switch type {
		case .insert:
			guard let newIndexPath = newIndexPath, let task = anObject as? PostOperation else { return }
			let newSection = makeNewSection(for: task, sectionIndex: newIndexPath.row)
			dataSource.insertSegment(newSection, at: newIndexPath.row)
		case .delete:
			guard let indexPath = indexPath else { return }
			dataSource.deleteSegment(at: indexPath.row)
		case .move:
			guard let indexPath = indexPath,  let newIndexPath = newIndexPath else { return }
			if let section = dataSource.deleteSegment(at: indexPath.row) {
				dataSource.insertSegment(section, at: newIndexPath.row)
			}
		case .update: break;
//			guard let indexPath = indexPath else { return }
//			reloadCells.append(indexPath)
		@unknown default:
			fatalError()
		}
	}

	func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
		dataSource.runUpdates()

		var x = 0
		for section in dataSource.allSegments {
			x = x + 1
			if let filteringSection = section as? FilteringDataSourceSegment {
				for model in filteringSection.allCellModels {
					if let cellModel = model as? SettingsInfoCellModel {
						cellModel.taskIndex = x
					}
				}
			}
		}		
	}
}

// Cancel Action, Edit
class TaskEditButtonsCellModel: ButtonCellModel {
	var task: PostOperation?
	weak var viewController: BaseCollectionViewController?
	
	init(forTask: PostOperation, vc: BaseCollectionViewController) {
		task = forTask
		viewController = vc
		super.init(alignment: .right)
		
		if task is PostOpTweetReaction || task is PostOpTweetDelete {
		}
		else {
			setupButton(1, title: "Edit", action: editTaskHit)
		}
		setupButton(2, title: "Cancel", action: cancelTaskHit)
	}
	
	func editTaskHit() {
		if task is PostOpTweet {
			viewController?.performSegue(withIdentifier: "EditTweet", sender: task)
		}
		else if task is PostOpSeamailThread {
			viewController?.performSegue(withIdentifier: "EditSeamailThread", sender: task)
		}
	}
	
	func cancelTaskHit() {
		if let task = task {
			PostOperationDataManager.shared.remove(op: task)
		}
	}
}
