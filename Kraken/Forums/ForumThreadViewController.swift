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
	var threadModel: ForumThread?

	let threadDataSource = KrakenDataSource()
	var loadingSegment = FilteringDataSourceSegment()
	var threadSegment = FRCDataSourceSegment<ForumPost>()

    override func viewDidLoad() {
        super.viewDidLoad()
		knownSegues = Set([.composeForumPost, .editForumPost, .tweetFilter, .userProfile])
		title = threadModel?.subject ?? "Thread"

		threadDataSource.append(segment: loadingSegment)
		loadingSegment.append(ForumsLoadTimeCellModel())

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
		threadDataSource.register(with: collectionView, viewController: self)

		setupGestureRecognizer()
//		knownSegues = Set([.showForumThread])
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
}
