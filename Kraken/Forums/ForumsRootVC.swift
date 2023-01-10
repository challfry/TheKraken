//
//  ForumsRootVC.swift
//  Kraken
//
//  Created by Chall Fry on 1/31/21.
//  Copyright © 2021 Chall Fry. All rights reserved.
//

import Foundation
import UIKit

class ForumsRootViewController: BaseCollectionViewController, GlobalNavEnabled {
//	var forumsNavTitleButton: UIButton!
//	@IBOutlet weak var forumsFilterView: UIVisualEffectView!
//	@IBOutlet weak var forumsFilterViewTop: NSLayoutConstraint!
//	@IBOutlet weak var forumsFilterContainerView: UIView!
//	@IBOutlet weak var forumsFilterStackView: UIStackView!
//	@IBOutlet weak var forumsFilterHeightConstraint: NSLayoutConstraint!
		
	let categoryDataSource = KrakenDataSource()
		var loadingSegment = FilteringDataSourceSegment()
		var categorySegment = FRCDataSourceSegment<ForumCategory>()
		var loggedInCategorySegment = FRCDataSourceSegment<ForumCategoryPivot>()
 
    var filterPopupVC: EmojiPopupViewController?
    
    lazy var loadingStatusCellModel: LoadingStatusCellModel = {
    	let cell = LoadingStatusCellModel()
    	cell.statusText = "Loading Categories"
    	cell.showSpinner = true
    	
    	CategoriesDataManager.shared.tell(cell, when: ["isPerformingLoad", "lastError"]) { observer, observed in 
    		observer.shouldBeVisible = observed.isPerformingLoad || observed.lastError != nil
    		observer.errorText = observed.lastError?.getCompleteError()
    	}?.execute()
     	
    	return cell
    }()
        

// MARK: Methods
	
	override func viewDidLoad() {
		super.viewDidLoad()
		
		categoryDataSource.append(segment: loadingSegment)
		loadingSegment.append(loadingStatusCellModel)
		
		categorySegment.loaderDelegate = self
		categorySegment.activate(predicate: NSPredicate(format: "visibleWhenLoggedOut == true"), 
				sort: [NSSortDescriptor(key: "sortIndex", ascending: true),
				NSSortDescriptor(key: "title", ascending: true)], cellModelFactory: createCellModel)
		categoryDataSource.append(segment: categorySegment)

		loggedInCategorySegment.loaderDelegate = self
		loggedInCategorySegment.activate(predicate: NSPredicate(value: false), 
				sort: [NSSortDescriptor(key: "sortIndex", ascending: true)],
				cellModelFactory: createCellModelFromPivot)
		categoryDataSource.append(segment: loggedInCategorySegment)

        CurrentUser.shared.tell(self, when: "loggedInUser", changeBlock:  { observer, observed in
			if let user = observed.loggedInUser {
				observer.loggedInCategorySegment.changePredicate(to: NSPredicate(format: "user.userID == %@", user.userID as CVarArg))
				observer.categorySegment.changePredicate(to: NSPredicate(value: false))
			}
			else {
				observer.loggedInCategorySegment.changePredicate(to: NSPredicate(value: false))
				observer.categorySegment.changePredicate(to: NSPredicate(format: "visibleWhenLoggedOut == true"))
			}
		})?.execute()

		categoryDataSource.register(with: collectionView, viewController: self)
	}
		
    override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		CategoriesDataManager.shared.checkRefresh()
	}
	
    override func viewDidAppear(_ animated: Bool) {
    	super.viewDidAppear(animated)
		categoryDataSource.enableAnimations = true
	}
	
	// Gets called from within collectionView:cellForItemAt:. Creates cell models from FRC result objects.
	func createCellModel(_ model: ForumCategory) -> BaseCellModel {
		let cellModel = ForumCategoryCellModel(category: model)
		cellModel.model = model
		cellModel.tapAction = { [weak self] cellModel in
			if let categoryCellModel = cellModel as? ForumCategoryCellModel {
				self?.performKrakenSegue(.showForumCategory, sender: categoryCellModel.category)
			}
		}
 //		CurrentUser.shared.tell(cellModel, when: "loggedInUser") { observer, observed in
 //			observer.shouldBeVisible = observed.loggedInUser == nil  		
// 		}
		return cellModel
	}
	    
	// Gets called from within collectionView:cellForItemAt:. Creates cell models from FRC result objects.
	func createCellModelFromPivot(_ model: ForumCategoryPivot) -> BaseCellModel {
		let cellModel = ForumCategoryCellModel(category: model.category)
		cellModel.model = model
		cellModel.tapAction = { [weak self] cellModel in
			if let categoryCellModel = cellModel as? ForumCategoryCellModel {
				self?.performKrakenSegue(.showForumCategory, sender: categoryCellModel.category)
			}
		}
//		CurrentUser.shared.tell(cellModel, when: "loggedInUser") { observer, observed in
 //			observer.shouldBeVisible = observed.loggedInUser != nil  		
 //		}
		return cellModel
	}
	    
// MARK: Navigation
	override var knownSegues : Set<GlobalKnownSegue> {
		Set<GlobalKnownSegue>([ .showForumCategory, .showForumThread, .modalLogin ])
	}
	
	@discardableResult func globalNavigateTo(packet: GlobalNavPacket) -> Bool {
		if let segue = packet.segue, [.showForumCategory, .showForumThread].contains(segue) {
			performKrakenSegue(segue, sender: packet.sender)
			return true
		}
		return false
	}


}

extension ForumsRootViewController: FRCDataSourceLoaderDelegate {
	func userIsViewingCell(at indexPath: IndexPath) {

	}
}

@objc class ForumCategoryCellModel: CategoryCellModel {
	var category: ForumCategory
	
	init(category: ForumCategory) {
		self.category = category
		super.init()
		self.title = category.title
		self.purpose = category.purpose
		self.numThreads = category.numThreads
	}
}
