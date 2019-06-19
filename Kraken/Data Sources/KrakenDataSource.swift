//
//  KrakenDataSource.swift
//  Kraken
//
//  Created by Chall Fry on 6/16/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit

class KrakenDataSource: NSObject {
	var enableAnimations = false			// Generally, set to true in viewDidAppear
	
	weak var collectionView: UICollectionView?
	weak var tableView: UITableView?
	weak var viewController: UIViewController? 			// So that cells can segue/present other VCs.

	var selectedCell: BaseCellModel?
	func setCellSelection(cellModel: BaseCellModel, newState: Bool) {
		// Only dealing with the single-select case
		
		// If we're selecting a cell that isn't the current selected cell
		if newState, let currentSelection = selectedCell, currentSelection !== cellModel {
			selectedCell = nil
			currentSelection.privateSelected = false
		}
		
		if newState {
			selectedCell = cellModel
			cellModel.privateSelected = true
		}
	}


	var internalInvalidateLayout = false
	func invalidateLayout() {
		internalInvalidateLayout = true
		runUpdates(sectionOffset: 0)
	}
	
	// Always called from within a performBatchUpdates
	@objc dynamic var parentDataSource: FilteringDataSource?
	private var updateScheduled = false
	func runUpdates(sectionOffset: Int) {
		if let ds = parentDataSource {
			// If we're not top-level, tell upstream that updates need to be run. Remember, performBatchUpdates
			// must update everything -- when it's done, every section's cell count must add up.
			ds.runUpdates()
		}
		else {
			guard !updateScheduled else { return }	
			DispatchQueue.main.async {
				self.updateScheduled = false
				
				if !self.enableAnimations {
					UIView.setAnimationsEnabled(false)
				}
				
				self.collectionView?.performBatchUpdates( {
					self.internalRunUpdates(sectionOffset: sectionOffset)
				}, completion: nil)
				
				if !self.enableAnimations {
					UIView.setAnimationsEnabled(true)
				}
			}
		}
	}
	
	func sizeChanged(for cellModel: BaseCellModel) {
		cellModel.cellSize = CGSize(width: 0, height: 0)
					
		let context = UICollectionViewFlowLayoutInvalidationContext()
		context.invalidateFlowLayoutDelegateMetrics = true
		collectionView?.collectionViewLayout.invalidateLayout(with: context)
	}


// MARK: For subclasses to override

	func register(with cv: UICollectionView, viewController: BaseCollectionViewController?) {
		collectionView = cv
		self.viewController = viewController
	}
	
	internal func internalRunUpdates(sectionOffset: Int) {

	}
}
