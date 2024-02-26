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
  		var personalCatsSegment = FilteringDataSourceSegment()

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
        
    lazy var searchCellModel: ForumSearchCellModel = {
		ForumSearchCellModel(searchAction: doSearch)
    }()
    
    lazy var favoriteForumsCellModel: DisclosureCellModel = {
    	let disclosureCell = DisclosureCellModel()
		disclosureCell.title = "Favorite Forums"
    	disclosureCell.tapAction = { cell in
			self.performKrakenSegue(.showForumFilterPack, sender: ForumsDataManager.shared.getFilterPack(filter: .favorite))
    	}
    	return disclosureCell
    }()
    
    lazy var recentForumsCellModel: DisclosureCellModel = {
    	let disclosureCell = DisclosureCellModel()
		disclosureCell.title = "Recent Forums"
    	disclosureCell.tapAction = { cell in
			self.performKrakenSegue(.showForumFilterPack, sender: ForumsDataManager.shared.getFilterPack(filter: .recent))
    	}
    	return disclosureCell
    }()
    
    lazy var ownedForumsCellModel: DisclosureCellModel = {
    	let disclosureCell = DisclosureCellModel()
		disclosureCell.title = "Forums You Created"
    	disclosureCell.tapAction = { cell in
			self.performKrakenSegue(.showForumFilterPack, sender: ForumsDataManager.shared.getFilterPack(filter: .userCreated))
    	}
    	return disclosureCell
    }()

    lazy var userPostedForumsCellModel: DisclosureCellModel = {
    	let disclosureCell = DisclosureCellModel()
		disclosureCell.title = "Forums You Posted In"
    	disclosureCell.tapAction = { cell in
			self.performKrakenSegue(.showForumFilterPack, sender: ForumsDataManager.shared.getFilterPack(filter: .userPosted))
    	}
    	return disclosureCell
    }()
    lazy var mutedForumsCellModel: DisclosureCellModel = {
    	let disclosureCell = DisclosureCellModel()
		disclosureCell.title = "Muted Forums"
    	disclosureCell.tapAction = { cell in
			self.performKrakenSegue(.showForumFilterPack, sender: ForumsDataManager.shared.getFilterPack(filter: .muted))
    	}
    	return disclosureCell
    }()

// MARK: Methods
	
	override func viewDidLoad() {
		super.viewDidLoad()
		
		categoryDataSource.append(segment: loadingSegment)
		loadingSegment.append(loadingStatusCellModel)
		loadingSegment.append(searchCellModel)
		
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

  		categoryDataSource.append(segment: personalCatsSegment)
		personalCatsSegment.append(LabelCellModel("Personal Categories", fontTraits: .traitBold))
		personalCatsSegment.append(favoriteForumsCellModel)
		personalCatsSegment.append(recentForumsCellModel)
		personalCatsSegment.append(ownedForumsCellModel)
		personalCatsSegment.append(userPostedForumsCellModel)
		personalCatsSegment.append(mutedForumsCellModel)

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
	
	override func viewWillDisappear(_ animated: Bool) {
		resignActiveTextEntry()
	}
	
	// Gets called from within collectionView:cellForItemAt:. Creates cell models from FRC result objects.
	func createCellModel(_ model: ForumCategory) -> BaseCellModel {
		let cellModel = CategoryCellModel(category: model)
		cellModel.model = model
		cellModel.tapAction = { [weak self] cellModel in
//			if let categoryCellModel = cellModel as? CategoryCellModel {
				self?.performKrakenSegue(.showForumCategory, sender: cellModel.category)
//			}
		}
 //		CurrentUser.shared.tell(cellModel, when: "loggedInUser") { observer, observed in
 //			observer.shouldBeVisible = observed.loggedInUser == nil  		
// 		}
		return cellModel
	}
	    
	// Gets called from within collectionView:cellForItemAt:. Creates cell models from FRC result objects.
	func createCellModelFromPivot(_ model: ForumCategoryPivot) -> BaseCellModel {
		let cellModel = CategoryCellModel(category: model.category)
		cellModel.model = model
		cellModel.tapAction = { [weak self] cellModel in
//			if let categoryCellModel = cellModel as? CategoryCellModel {
				self?.performKrakenSegue(.showForumCategory, sender: cellModel.category)
//			}
		}
//		CurrentUser.shared.tell(cellModel, when: "loggedInUser") { observer, observed in
 //			observer.shouldBeVisible = observed.loggedInUser != nil  		
 //		}
		return cellModel
	}
	    
// MARK: Navigation
	override var knownSegues : Set<GlobalKnownSegue> {
		Set<GlobalKnownSegue>([ .showForumCategory, .showForumFilterPack, .showForumThread, .modalLogin ])
	}
	
	@discardableResult func globalNavigateTo(packet: GlobalNavPacket) -> Bool {
		if let segue = packet.segue, [.showForumCategory, .showForumThread, .showForumFilterPack].contains(segue) {
			performKrakenSegue(segue, sender: packet.sender)
			return true
		}
		return false
	}

    func doSearch(text: String) {
    	resignActiveTextEntry()
		performKrakenSegue(.showForumFilterPack, sender: ForumsDataManager.shared.getFilterPack(search: text))
    }
}

extension ForumsRootViewController: FRCDataSourceLoaderDelegate {
	func userIsViewingCell(at indexPath: IndexPath) {

	}
}

//@objc class ForumCategoryCellModel: CategoryCellModel {
//	var category: ForumCategory
//	
//	init(category: ForumCategory) {
//		self.category = category
//		super.init()
//		self.title = category.title
//		self.purpose = category.purpose
//		self.numThreads = category.numThreads
//	}
//}
