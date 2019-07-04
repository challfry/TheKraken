//
//  KrakenDataSource.swift
//  Kraken
//
//  Created by Chall Fry on 6/16/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit

// This has to be an @objc protocol, which has cascading effects.
@objc protocol KrakenDataSourceSectionProtocol: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
	var dataSource: FilteringDataSource? { get set }
	var sectionName: String { get set }
	var sectionVisible: Bool { get set }
//	var numVisibleSections: Int { get set }	// May have to switch to this to handle sub-DS that has multiple sections?
		
	func append(_ cell: BaseCellModel)
	func internalRunUpdates(for collectionView: UICollectionView?, sectionOffset: Int)
}

class KrakenDataSource: NSObject {
	var enableAnimations = false			// Generally, set to true in viewDidAppear
	
	weak var collectionView: UICollectionView?
	weak var tableView: UITableView?
	weak var viewController: UIViewController? 			// So that cells can segue/present other VCs.

	func performSegue(withIdentifier: String, sender: AnyObject) {
		viewController?.performSegue(withIdentifier: withIdentifier, sender: sender)
	}

	var selectedCell: BaseCellModel?
	func setCellSelection(cell: BaseCollectionViewCell, newState: Bool) {
		// Only dealing with the single-select case; eventually create an enum with selection types?
		
		// If we're selecting a cell that isn't the current selected cell
		if newState, let currentSelection = selectedCell, currentSelection !== cell.cellModel {
			selectedCell = nil
			currentSelection.privateSelected = false
		}
		
		// If we're deselecting the currently selected cell
		if !newState, let currentSelection = selectedCell, currentSelection === cell.cellModel {
			selectedCell = nil
			currentSelection.privateSelected = false
		}
		
		if newState {
			selectedCell = cell.cellModel
			cell.cellModel?.privateSelected = true
		}
		
		if let indexPath = collectionView?.indexPath(for: cell) {
			collectionView?.selectItem(at: indexPath, animated: false, scrollPosition: .left)
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

	var itemsToRunAfterBatchUpdates: [() -> Void]?
	func scheduleBatchUpdateCompletionBlock(block: @escaping () -> Void) {
		if let ds = collectionView?.dataSource as? KrakenDataSource,  ds.itemsToRunAfterBatchUpdates != nil {
			ds.itemsToRunAfterBatchUpdates?.append(block)
			CollectionViewLog.debug("Scheduling block to run later, on addr: \(Unmanaged.passUnretained(ds).toOpaque())")
		}
		else {
			block()
		}
	}

// MARK: For subclasses to override

	func register(with cv: UICollectionView, viewController: BaseCollectionViewController?) {
		collectionView = cv
		self.viewController = viewController
		scheduleBatchUpdateCompletionBlock {
			if let ds = self as? UICollectionViewDataSource {
				cv.dataSource = ds
	//			cv.reloadData()
			}
			if let del = self as? UICollectionViewDelegate {
				cv.delegate = del
			}
		}
	}
	
	internal func internalRunUpdates(sectionOffset: Int) {

	}
}

// Debugging extensions
extension KrakenDataSource: UIScrollViewDelegate {

	// Dumps info about cell and CV sizes. Shouldn't be called in the app. To use:
	//			in LLDB: po <datasource>.debugCellHeights()
	func debugCellHeights() {
		guard let this = self as? (UICollectionViewDataSource & UICollectionViewDelegate & UICollectionViewDelegateFlowLayout),
				let cv = collectionView else { return }
		let sectionCount = this.numberOfSections?(in: cv) ?? 1
		var totalHeight: CGFloat = 0.0
		var debugString = ""
		for sectionIndex in  0..<sectionCount {
			let cellCount = this.collectionView(cv, numberOfItemsInSection: sectionIndex)
			var sectionHeight: CGFloat = 0.0
			for cellIndex in 0..<cellCount {
				let indexPath = IndexPath(row: cellIndex, section: sectionIndex)
				let cellSize = this.collectionView?(cv, layout:cv.collectionViewLayout, sizeForItemAt: indexPath)
				sectionHeight += cellSize?.height ?? 0
			}
			totalHeight += sectionHeight
			debugString.append("    Section \(sectionIndex): \(cellCount) cells, \(sectionHeight) height.\n")
		}
		CollectionViewLog.debug("CV: \(sectionCount) sections, totalHeight: \(totalHeight)\n\(debugString)")
	}
	
//	func scrollViewDidScroll(_ scrollView: UIScrollView) {
//		CollectionViewLog.debug("ContentOffset: \(scrollView.contentOffset.y) ContentSize: \(scrollView.contentSize.height)"
//				+ " ViewHeight: \(scrollView.bounds.size.height) MaxOffset: \(scrollView.contentSize.height - scrollView.bounds.size.height)" )
//	}

}
