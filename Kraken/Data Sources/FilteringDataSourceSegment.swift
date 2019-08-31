//
//  FilteringCollectionViewDataSource.swift
//  Kraken
//
//  Created by Chall Fry on 4/19/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit
import os

fileprivate struct Log: LoggingProtocol {	
	static var logObject = OSLog.init(subsystem: "com.challfry.Kraken", category: "CollectionView")
	static var isEnabled = CollectionViewLog.isEnabled && false
	var instanceEnabled: Bool = false	
}


@objc class FilteringDataSourceSegment : KrakenDataSourceSegment, KrakenDataSourceSegmentProtocol {

	@objc dynamic var allCellModels = NSMutableArray() // [BaseCellModel]()
	var visibleCellModels = [BaseCellModel]()
	var log = CollectionViewLog(instanceEnabled: false)

	var forceSectionVisible: Bool? {	// If this is nil, section is visible iff it has any visible cells. T/F overrides.
		didSet { dataSource?.runUpdates() }
	}
		
	override init() {
		super.init()
		
		// Watch for visibility OR height updates in cells; tell DS to go runupdates.
		allCellModels.tell(self, when: ["*.shouldBeVisible", "*.cellHeight"]) { observer, observed in
			observer.dataSource?.runUpdates()
		}
	}
	
	// Returns input cell, for chaining
	@discardableResult func append<T: BaseCellModel>(cell: T) -> T {
		allCellModels.add(cell)
		return cell
	}
	
	func append(_ cell: BaseCellModel) {
		allCellModels.add(cell)
	}
	
	@discardableResult func insert<T: BaseCellModel>(cell: T, at: Int) -> T {
		allCellModels.insert(cell, at: at)
		return cell
	}
	
	func delete(at: Int) {
		allCellModels.removeObject(at: at)
	}
	
	override func invalidateLayoutCache() {
		let cells = allCellModels as! [BaseCellModel]
		cells.forEach { $0.cellSize = CGSize(width: 0, height: 0) }
	}

	func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, 
			sizeForItemAt indexPath: IndexPath) -> CGSize {
		let cellModel = visibleCellModels[indexPath.row]

		var cellSize: CGSize
		if cellModel.cellSize.height > 0 {
			cellSize = cellModel.cellSize
		}
		else if let protoCell = cellModel.makePrototypeCell(for: collectionView, indexPath: indexPath) {
			cellSize = protoCell.calculateSize()
			cellModel.cellSize = cellSize
			cellModel.unbind(cell: protoCell)
		}
		else {
			cellSize = CGSize(width:collectionView.bounds.size.width, height: 50)
		}
		
		log.debug("sizeForItemAt", ["height" : cellSize.height, "path" : indexPath])
		return cellSize
	}
	
	func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
		return visibleCellModels.count
	}
	
	func cellModel(at indexPath: IndexPath) -> BaseCellModel? {
		// This DSS only supports one section
		return visibleCellModels[indexPath.row]
	}
	
	func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath, offsetPath: IndexPath) -> UICollectionViewCell {
		let model = visibleCellModels[offsetPath.row]
		let reuseID = model.reuseID()
		
		if dataSource?.registeredCellReuseIDs.contains(reuseID) == false {
			dataSource?.registeredCellReuseIDs.insert(reuseID)
			let classType = type(of: model).validReuseIDDict[reuseID]
			classType?.registerCells(with: collectionView)
		}
		return model.makeCell(for: collectionView, indexPath: indexPath)
	}
	
	// Only called by runUpdates, which is only in the top-level datasource. Therefore, only called from within
	// performBatchUpdates(). Delete and Insert offsets are section offsets ot use when deleting/inserting; our 
	// section 0 isn't section 0 in the CV.
	func internalRunUpdates(for collectionView: UICollectionView?, deleteOffset: Int, insertOffset: Int) {
		let cells = allCellModels as! [BaseCellModel]
		let newVisibleCells = cells.compactMap() { model in model.shouldBeVisible ? model : nil }
		let oldModels = visibleCellModels	
		visibleCellModels = newVisibleCells

		// Determine section visibility. Force can set visibility on or off
		var newShouldBeVisible = true
		if let forceVis = forceSectionVisible {
			newShouldBeVisible = forceVis
		}
		else {
			// Otherwise, the section is visible iff it has a visible cell
			var hasVisibleCells = false
			let cells = allCellModels as! [BaseCellModel]
			for cell in cells {	// In non-degenerate cases this will break really early, as most cells are visible
				if cell.shouldBeVisible {
					hasVisibleCells = true
					break
				}
			}
			newShouldBeVisible = hasVisibleCells
		}
		if newShouldBeVisible && numVisibleSections == 0 {
			collectionView?.insertSections(IndexSet(integer: insertOffset))
			log.debug("Filtering Segment inserting sections", ["sections" : insertOffset, "DS" : self.dataSource ?? ""])
		}
		else if !newShouldBeVisible && numVisibleSections == 1 {
			collectionView?.deleteSections(IndexSet(integer: deleteOffset))
			log.debug("Filtering Segment deleting sections", ["sections" : deleteOffset, "DS" : self.dataSource ?? ""])
		}
		numVisibleSections = newShouldBeVisible ? 1 : 0
		

		var deletes = [IndexPath]()
		var inserts = [IndexPath]()
		for cellIndex in 0 ..< oldModels.count {
			if !visibleCellModels.contains(oldModels[cellIndex]) {
				deletes.append(IndexPath(row: cellIndex, section: deleteOffset))
			}
		}
		for cellIndex in 0 ..< visibleCellModels.count {
			if !oldModels.contains(visibleCellModels[cellIndex]) {
				inserts.append(IndexPath(row: cellIndex, section: insertOffset))
			}
		}
		if collectionView != nil {
			log.debug("Inserts: \(inserts) Deletes: \(deletes) \nModels: \(self.visibleCellModels)")
		}
		else {
			log.debug("THROWING AWAY Inserts: \(inserts) Deletes: \(deletes) \nModels: \(self.visibleCellModels)")
		}
		collectionView?.deleteItems(at: deletes)
		collectionView?.insertItems(at: inserts)
	}
}

