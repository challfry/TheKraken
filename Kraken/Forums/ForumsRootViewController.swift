//
//  ForumsRootViewController.swift
//  Kraken
//
//  Created by Chall Fry on 3/20/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit

class ForumsRootViewController: BaseCollectionViewController {

	let threadDataSource = KrakenDataSource()
	var loadingSegment = FilteringDataSourceSegment()
	var threadSegment = FRCDataSourceSegment<ForumThread>()
	
	override func viewDidLoad() {
		super.viewDidLoad()

		threadDataSource.append(segment: loadingSegment)
		loadingSegment.append(ForumsLoadTimeCellModel())
		
		threadDataSource.append(segment: threadSegment)
		threadSegment.activate(predicate: NSPredicate(value: true), 
				sort: [ NSSortDescriptor(key: "lastPostTime", ascending: false)], cellModelFactory: createCellModel)

		threadDataSource.register(with: collectionView, viewController: self)

		setupGestureRecognizer()
	}
	
	override func viewDidAppear(_ animated: Bool) {
		ForumsDataManager.shared.loadForumThreads(fromOffset: 0) {
			
		}
	}

	// Gets called from within collectionView:cellForItemAt:. Creates cell models from FRC result objects.
	func createCellModel(_ model:ForumThread) -> BaseCellModel {
		let cellModel = ForumsThreadCellModel(with: model)
		return cellModel
	}
	
	// Set up data in destination view controllers when we're about to segue to them.
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
		if segue.identifier == "ShowForumThread", let destVC = segue.destination as? ForumThreadViewController,
				let threadModel = sender as? ForumThread {
//			destVC.threadModel = threadModel
		}
    }

}

