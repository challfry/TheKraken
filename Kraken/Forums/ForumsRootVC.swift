//
//  ForumsRootVC.swift
//  Kraken
//
//  Created by Chall Fry on 1/31/21.
//  Copyright © 2021 Chall Fry. All rights reserved.
//

import Foundation
import UIKit

class ForumsRootViewController: BaseCollectionViewController {
//	var forumsNavTitleButton: UIButton!
//	@IBOutlet weak var forumsFilterView: UIVisualEffectView!
//	@IBOutlet weak var forumsFilterViewTop: NSLayoutConstraint!
//	@IBOutlet weak var forumsFilterContainerView: UIView!
//	@IBOutlet weak var forumsFilterStackView: UIStackView!
//	@IBOutlet weak var forumsFilterHeightConstraint: NSLayoutConstraint!
		
	let categoryDataSource = KrakenDataSource()
		var loadingSegment = FilteringDataSourceSegment()
		var categorySegment = FRCDataSourceSegment<ForumCategory>()
 
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
		
		categoryDataSource.append(segment: categorySegment)
		categorySegment.loaderDelegate = self
		categorySegment.activate(predicate: NSPredicate(value: true), 
				sort: [NSSortDescriptor(key: "isAdmin", ascending: false),
				NSSortDescriptor(key: "title", ascending: true)], cellModelFactory: createCellModel)

		categoryDataSource.register(with: collectionView, viewController: self)

		knownSegues = Set([.showForumCategory, .modalLogin])
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
		let cellModel = ForumCategoryCellMdoel(category: model)
		cellModel.tapAction = { [weak self] cellModel in
			if let categoryCellModel = cellModel as? ForumCategoryCellMdoel {
				self?.performKrakenSegue(.showForumCategory, sender: categoryCellModel.category)
			}
		}
		return cellModel
	}
	    
// MARK: Actions
}

extension ForumsRootViewController: FRCDataSourceLoaderDelegate {
	func userIsViewingCell(at indexPath: IndexPath) {

	}
}

@objc class ForumCategoryCellMdoel: DisclosureCellModel {
	var category: ForumCategory
	
	init(category: ForumCategory) {
		self.category = category
		super.init()
		self.title = category.title
	}
}
