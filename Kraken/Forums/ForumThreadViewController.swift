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
	
	// Not set up for the threadModel to change while the VC is visible.
	@objc dynamic var threadModel: ForumThread?

	let threadDataSource = KrakenDataSource()
	var threadSegment = FRCDataSourceSegment<ForumPost>()
	var loadingSegment = FilteringDataSourceSegment()

    lazy var loadTimeCellModel: ForumsLoadTimeCellModel = {
    	let cell = ForumsLoadTimeCellModel()
    	cell.refreshButtonAction = {
			if let tm = self.threadModel {
				self.postButton.isEnabled = !tm.locked
				let lastKnownPost = tm.posts.count
				ForumsDataManager.shared.loadThreadPosts(for: tm, fromOffset: lastKnownPost) {
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
		knownSegues = Set([.composeForumPost, .editForumPost, .tweetFilter, .userProfile])
		title = threadModel?.subject ?? "Thread"

		// First add the segment with all the posts
		threadDataSource.append(segment: threadSegment)
		var threadPredicate: NSPredicate
		if let tm = threadModel {
			threadPredicate = NSPredicate(format: "thread.id == %@", tm.id)
		}
		else {
			threadPredicate = NSPredicate(value: false)
		}
		threadSegment.activate(predicate: threadPredicate, 
					sort: [ NSSortDescriptor(key: "timestamp", ascending: true)], cellModelFactory: createCellModel)

		// Then add the loading segment
		loadingSegment.append(loadTimeCellModel)
		threadDataSource.append(segment: loadingSegment)

		// Then register the whole thing.
		threadDataSource.register(with: collectionView, viewController: self)
		setupGestureRecognizer()
    }
    
    override func viewWillAppear(_ animated: Bool) {
    	super.viewWillAppear(animated)
    	
		threadDataSource.enableAnimations = true

		if let tm = threadModel {
			postButton.isEnabled = !tm.locked
			ForumsDataManager.shared.loadThreadPosts(for: tm, fromOffset: 0) {
			
			}
					
		}
	}
	
	override func viewWillDisappear(_ animated: Bool) {
		if let tm = threadModel {
			tm.updateLastReadTime()
		}
	}
	
	// Gets called from within collectionView:cellForItemAt:. Creates cell models from FRC result objects.
	func createCellModel(_ model:ForumPost) -> BaseCellModel {
		let cellModel = ForumPostCellModel(withModel: model)
		cellModel.viewController = self
		return cellModel
	}

	@IBAction func postButtonTapped(_ sender: Any) {
		performKrakenSegue(.composeForumPost, sender: threadModel)
	}
	
	// This is the unwind segue from the compose view.
	@IBAction func dismissingPostingView(_ segue: UIStoryboardSegue) {
	}	
}
