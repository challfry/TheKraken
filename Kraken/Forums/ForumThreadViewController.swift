//
//  ForumThreadViewController.swift
//  Kraken
//
//  Created by Chall Fry on 12/4/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit

class ForumThreadViewController: BaseCollectionViewController {
	@IBOutlet weak var postButton: UIBarButtonItem!
	
	// ThreadModel is what we're modelling, but you can set threadModelID and we'll load that thread ID 
	// and set threadModel ourselves.
	@objc dynamic var threadModel: ForumThread?
	@objc dynamic var threadModelID: UUID?
	
	var highestRefreshedIndex: Int = 0

	let threadDataSource = KrakenDataSource()
	var threadSegment = FRCDataSourceSegment<ForumPost>()
	var loadingSegment = FilteringDataSourceSegment()

    lazy var loadTimeCellModel: ForumsLoadTimeCellModel = {
    	let cell = ForumsLoadTimeCellModel()
    	cell.refreshButtonAction = {
			if let tm = self.threadModel {
				self.postButton.isEnabled = !tm.locked
				let lastKnownPost = tm.posts.count
				ForumPostDataManager.shared.loadThreadPosts(for: tm, fromOffset: lastKnownPost) { thread, lastIndex in
					self.highestRefreshedIndex = lastIndex
					cell.lastLoadTime = Date()
				}
			}
    	}
    	
    	self.tell(cell, when: "threadModel.lastUpdateTime") { observer, observed in 
    		observer.lastLoadTime = observed.threadModel?.lastUpdateTime
    	}?.execute()
    	return cell
    }()
    
	override func viewDidLoad() {
        super.viewDidLoad()
		// First add the segment with all the posts
		threadDataSource.append(segment: threadSegment)
		threadSegment.loaderDelegate = self

		// Then add the loading segment
		loadingSegment.append(loadTimeCellModel)
		threadDataSource.append(segment: loadingSegment)

		// Then register the whole thing.
		threadDataSource.register(with: collectionView, viewController: self)

		self.tell(self, when: "threadModel") { observer, observed in 
			observer.title = observed.threadModel?.subject ?? "Thread"
			var threadPredicate: NSPredicate
			if let tm = observed.threadModel {
				threadPredicate = NSPredicate(format: "thread.id == %@", tm.id as CVarArg)
			}
			else {
				threadPredicate = NSPredicate(value: false)
			}
			observer.threadSegment.activate(predicate: threadPredicate, 
					sort: [ NSSortDescriptor(key: "id", ascending: true)], cellModelFactory: observer.createCellModel)
			observer.postButton.isEnabled = observed.threadModel?.locked == false
		}?.execute()
    }
    
    override func viewWillAppear(_ animated: Bool) {
    	super.viewWillAppear(animated)

		ForumPostDataManager.shared.loadThreadPosts(for: threadModel, forID: threadModelID, fromOffset: 0) { thread, lastIndex in
    		self.threadModel = thread
			self.highestRefreshedIndex = lastIndex
			self.loadTimeCellModel.lastLoadTime = Date()
		}
	}
	
	override func viewDidAppear(_ animated: Bool) {
    	super.viewDidAppear(animated)
		threadDataSource.enableAnimations = true
	}
	
	override func viewWillDisappear(_ animated: Bool) {
    	super.viewWillDisappear(animated)
		if let tm = threadModel {
			tm.updateLastReadTime()
		}
	}
	
	// Gets called from within collectionView:cellForItemAt:. Creates cell models from FRC result objects.
	func createCellModel(_ model: ForumPost) -> BaseCellModel {
		let cellModel = ForumPostCellModel(withModel: model)
		cellModel.viewController = self
		return cellModel
	}

	@IBAction func postButtonTapped(_ sender: Any) {
		performKrakenSegue(.composeForumPost, sender: threadModel)
	}
	
// MARK: Navigation
	override var knownSegues : Set<GlobalKnownSegue> {
		Set<GlobalKnownSegue>([ .composeForumPost, .editForumPost, .tweetFilter, .userProfile_User, .userProfile_Name,
				.modalLogin, .reportContent, .showLikeOptions ])
	}		
	
	// This is the unwind segue from the compose view.
	@IBAction func dismissingPostingView(_ segue: UIStoryboardSegue) {
	}	
}

extension ForumThreadViewController: FRCDataSourceLoaderDelegate {
	func userIsViewingCell(at indexPath: IndexPath) {
		if let tm = threadModel,  indexPath.row + 10 > highestRefreshedIndex, 
				highestRefreshedIndex + 1 < tm.postCount, !ForumsDataManager.shared.isPerformingLoad {
			ForumPostDataManager.shared.loadThreadPosts(for: tm, fromOffset: highestRefreshedIndex + 1) { thread, lastIndex in
				self.highestRefreshedIndex = lastIndex
				self.loadTimeCellModel.lastLoadTime = Date()
			}
		}
	}
}

