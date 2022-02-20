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
		knownSegues = Set([.userProfile, .editTweetOp, .editForumPostDraft, .editSeamailThreadOp])
  		dataSource.register(with: collectionView, viewController: self)
		
		let context = LocalCoreData.shared.mainThreadContext
		let fetchRequest = NSFetchRequest<PostOperation>(entityName: "PostOperation")
		fetchRequest.sortDescriptors = [NSSortDescriptor(key: "originalPostTime", ascending: true)]
		controller = NSFetchedResultsController(fetchRequest: fetchRequest, managedObjectContext: context, 
				sectionNameKeyPath: nil, cacheName: nil)
		controller?.delegate = self

		// Rebuild the entire table if the logged in user changes.
		CurrentUser.shared.tell(self, when: "loggedInUser.username") { observer, observed in
			if let currentUsername = CurrentUser.shared.loggedInUser?.username {
				fetchRequest.predicate = NSPredicate(format: "author.username == %@", currentUsername)
			}
			else {
				fetchRequest.predicate = NSPredicate(value: false)
			}
		
			do {
				observer.dataSource.deleteAllSegments()
				try observer.controller?.performFetch()
				
				if let tasks = observer.controller?.fetchedObjects {
					var x = 0
					for task in tasks {
						x = x + 1
						let newSection = observer.makeNewSection(for: task, sectionIndex: x)
						observer.dataSource.append(segment: newSection)
					}
				}
			} catch {
				CoreDataLog.error("Failed to fetch entities for PostOp tasks.", ["error" : error])
			}
		}?.execute()
	}	
		
    override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		dataSource.enableAnimations = true
	}
	
	// This is the unwind segue handler for the profile edit VC
	@IBAction func dismissingProfileEditVC(segue: UIStoryboardSegue) {
	}
}

// SettingsTasks maps a simple array of tasks from the FRC to an array of sections in the CollectionView.
// Each item in the FRC array is a section (usually with 3 cells in it) in the CV.
extension SettingsTasksViewController: NSFetchedResultsControllerDelegate {

	func makeNewSection(for task: PostOperation, sectionIndex: Int) -> KrakenDataSourceSegment {
		let taskSection = FilteringDataSourceSegment()
		taskSection.segmentName = "\(sectionIndex)"
		
		switch task {
// Twittar
		case let reactionTask as PostOpTweetReaction:
			if reactionTask.reactionWord == "unlike" {
				taskSection.append(SettingsInfoCellModel("Cancel the \"Like\" on this tweet:", taskIndex: sectionIndex))
			}
			else {
				taskSection.append(SettingsInfoCellModel("Add a \"Like\" reaction to this tweet:", taskIndex: sectionIndex))
			}
			
			let model = TwitarrTweetCellModel(withModel:reactionTask.sourcePost)
			model.isInteractive = false
			taskSection.append(model)

		case let postTask as PostOpTweet:
			let cellModel = TwitarrTweetOpCellModel(withModel: postTask)
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
		
		case let deleteTask as PostOpTweetDelete:
			let cellModel = TwitarrTweetCellModel(withModel: deleteTask.tweetToDelete)
			cellModel.isInteractive = false
			taskSection.append(SettingsInfoCellModel("Delete this Twitarr tweet of yours:", taskIndex: sectionIndex))
			taskSection.append(cellModel)


// Forums
		case let postTask as PostOpForumPost:
			let cellModel = ForumPostOpCellModel(withModel: postTask)
			cellModel.isInteractive = false
			if postTask.editPost != nil {
				taskSection.append(SettingsInfoCellModel("Make an edit to your post:", taskIndex: sectionIndex))
			}
			else if let thread = postTask.thread {
				let infoCell = SettingsInfoCellModel("Post a reply in Forum thread", taskIndex: sectionIndex)
				let labelText = NSMutableAttributedString(string: "Title: ", attributes: [.font : UIFont.boldSystemFont(ofSize: 17.0) as Any])
				labelText.append(NSMutableAttributedString(string: thread.subject, attributes: [.font : UIFont.systemFont(ofSize: 17.0) as Any]))
				taskSection.append(infoCell)
			}
			else if let subject = postTask.subject {
				let infoCell = SettingsInfoCellModel("Post a new Forum thread", taskIndex: sectionIndex)
				let labelText = NSMutableAttributedString(string: "Title: ", attributes: [.font : UIFont.boldSystemFont(ofSize: 17.0) as Any])
				labelText.append(NSMutableAttributedString(string: subject, attributes: [.font : UIFont.systemFont(ofSize: 17.0) as Any]))
				infoCell.labelText = labelText
				taskSection.append(infoCell)
			}
			taskSection.append(cellModel)

		case let reactionTask as PostOpForumPostReaction:
			if reactionTask.reactionWord == "unlike" {
				taskSection.append(SettingsInfoCellModel("Cancel the \"Like\" on this Forum Post:", taskIndex: sectionIndex))
			}
			else {
				taskSection.append(SettingsInfoCellModel("Add a \"Like\" reaction to this Forum Post:", taskIndex: sectionIndex))
			}
			
			let model = ForumPostCellModel(withModel: reactionTask.sourcePost)
			model.isInteractive = false
			taskSection.append(model)
			

// Seamail		
		case let seamailPostTheadTask as PostOpSeamailThread:
			let cellModel = SeamailThreadCellModel(withModel: seamailPostTheadTask, reuse: "seamailThread")
			cellModel.isInteractive = false
			taskSection.append(SettingsInfoCellModel("Start a new Seamail Thread:", taskIndex: sectionIndex))
			taskSection.append(cellModel)
		
		case let seamailPostMessageTask as PostOpSeamailMessage:
			let cellModel = SeamailMessageCellModel(withModel: seamailPostMessageTask, reuse: "SeamailSelfMessageCell")
			// cellModel.isInteractive = false
			taskSection.append(SettingsInfoCellModel("Send a Seamail Message:", taskIndex: sectionIndex))
			taskSection.append(cellModel)



// Events
		case let eventFollowTask as PostOpEventFollow:
			taskSection.append(SettingsInfoCellModel(eventFollowTask.newState ? "Follow a Scheduled Event:" :
					"Unfollow a Scheduled Event", taskIndex: sectionIndex))
			if let event = eventFollowTask.event {
				let cellModel = EventCellModel(withModel: event)
				cellModel.isInteractive = false
				cellModel.disclosureLevel = 3
				taskSection.append(cellModel)
			}



			
		case let userCommentTask as PostOpUserComment:
			if let commentedOnUsername = userCommentTask.userCommentedOn?.username {
				taskSection.append(SettingsInfoCellModel("Add a personal User Comment for user \(commentedOnUsername)",
						taskIndex: sectionIndex))
			}
			else {
				taskSection.append(SettingsInfoCellModel("Add a personal User Comment", taskIndex: sectionIndex))
			}
			taskSection.append(LabelCellModel(userCommentTask.comment))
			
		case let userFavoritedTask as PostOpUserFavorite:
			if let favoritedUsername = userFavoritedTask.userBeingFavorited?.username {
				let headerCell = SettingsInfoCellModel("Favorite/Un-favorite a user", taskIndex: sectionIndex)
				userFavoritedTask.tell(headerCell, when: "isFavorite") { observer, observed in
					let str = observed.isFavorite ? "• Add \(favoritedUsername) to favorite users" : 
							"• Remove \(favoritedUsername) from favorite users"
					observer.labelText = NSAttributedString(string: str)
				}?.execute()
				taskSection.append(headerCell)
				let disclosureCell = DisclosureCellModel()
				disclosureCell.title = "See profile for \(favoritedUsername)"
				disclosureCell.tapAction = { cell in
					self.performKrakenSegue(.userProfile, sender: favoritedUsername)
				}
				taskSection.append(disclosureCell)
			}
			
		case let userProfileEditTask as PostOpUserProfileEdit:
			taskSection.append(SettingsInfoCellModel("Update your User Profile", taskIndex: sectionIndex))
			if let currentUser = CurrentUser.shared.loggedInUser {
				let displayNameCell = SingleValueCellModel("Display Name:")
				userProfileEditTask.tell(displayNameCell, when: "displayName") { observer, observed in 
					observer.value = observed.displayName
					observer.shouldBeVisible = observed.displayName != currentUser.displayName
				}?.execute()
				let realNameCell = SingleValueCellModel("Real Name:")
				userProfileEditTask.tell(realNameCell, when: "realName") { observer, observed in 
					observer.value = observed.realName
					observer.shouldBeVisible = observed.realName != currentUser.realName
				}?.execute()
				let pronounsCell = SingleValueCellModel("Pronouns:")
				userProfileEditTask.tell(pronounsCell, when: "pronouns") { observer, observed in 
					observer.value = observed.pronouns
					observer.shouldBeVisible = observed.pronouns != currentUser.pronouns
				}?.execute()
				let emailCell = SingleValueCellModel("Email:")
				userProfileEditTask.tell(emailCell, when: "email") { observer, observed in 
					observer.value = observed.email
					observer.shouldBeVisible = observed.email != currentUser.emailAddress
				}?.execute()
				let homeLocationCell = SingleValueCellModel("Home Location:")
				userProfileEditTask.tell(homeLocationCell, when: "homeLocation") { observer, observed in 
					observer.value = observed.homeLocation
					observer.shouldBeVisible = observed.homeLocation != currentUser.homeLocation
				}?.execute()
				let roomNumberCell = SingleValueCellModel("Room Number:")
				userProfileEditTask.tell(roomNumberCell, when: "roomNumber") { observer, observed in 
					observer.value = observed.roomNumber
					observer.shouldBeVisible = observed.roomNumber != currentUser.roomNumber
				}?.execute()
				
				taskSection.append(displayNameCell)
				taskSection.append(realNameCell)
				taskSection.append(pronounsCell)
				taskSection.append(emailCell)
				taskSection.append(homeLocationCell)
				taskSection.append(roomNumberCell)
			}
			
		case let userPhotoTask as PostOpUserPhoto:
			let infoCell = SettingsInfoCellModel("Change your User Avatar Photo", taskIndex: sectionIndex)
			let photoCell = SinglePhotoCellModel()
			taskSection.append(infoCell)
			taskSection.append(photoCell)
			
			userPhotoTask.tell(infoCell, when: "image") { observer, observed in 
				observer.titleText = observed.image == nil ? "Delete your User Avatar Photo" :
						"Change your User Avatar Photo"
				let infoString = observed.image == nil ? "The server will provide a default image." : ""
				observer.labelText = NSAttributedString(string: infoString)
			}?.execute()
			userPhotoTask.tell(photoCell, when: "image") { observer, observed in 
				observer.shouldBeVisible = observed.image != nil 
				if let imageData = observed.image {
					observer.image = UIImage(data: imageData as Data)
				}
				else {
					observer.image = nil
				}
			}?.execute()

		default:
			break			
		}
		
		// For all task types, put a status cell and a edit buttons cell underneath the task description.
		let labelCell = OperationStatusCellModel()
		labelCell.hideCancelButton = true
		task.tell(labelCell, when: "errorString") { observer, observed in
			observer.shouldBeVisible = observed.errorString != nil
			observer.statusText = "Server Error"
			if let error = observed.errorString {
				var errorText = "Server rejected this change, stating:\n    • \(error)"
				if TaskEditButtonsCellModel.taskCanBeEdited(task: task) {
					errorText.append("\n\nYou can try editing this item to fix the error and then re-send.")
				}
				observer.errorText = errorText
			}
		}?.execute()
		
		taskSection.append(labelCell)
		taskSection.append(TaskEditButtonsCellModel(forTask: task, vc: self))
		
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
		
		if TaskEditButtonsCellModel.taskCanBeEdited(task: forTask) {
			setupButton(1, title: "Edit", action: editTaskHit)
		}
		setupButton(2, title: "Cancel", action: cancelTaskHit)
	}
	
	class func taskCanBeEdited(task: PostOperation) -> Bool {
		if task is PostOpTweetReaction ||
				task is PostOpForumPostReaction || 
				task is PostOpTweetDelete || 
				task is PostOpForumPostDelete || 
				task is PostOpUserFavorite || 
				task is PostOpEventFollow {
			return false
		}
		return true
	}
	
	func editTaskHit() {
		if task is PostOpTweet {
			viewController?.performKrakenSegue(.editTweetOp, sender: task)
		}
		else if task is PostOpForumPost {
			viewController?.performKrakenSegue(.editForumPostDraft, sender: task)
		}
		else if task is PostOpSeamailThread {
			viewController?.performKrakenSegue(.editSeamailThreadOp, sender: task)
		}
		else if task is PostOpUserProfileEdit {
			viewController?.performKrakenSegue(.editUserProfile, sender: task)
		}
	}
	
	func cancelTaskHit() {
		if let task = task {
			PostOperationDataManager.shared.remove(op: task)
		}
	}
}
