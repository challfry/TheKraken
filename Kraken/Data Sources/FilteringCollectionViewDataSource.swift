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
}


@objc class FilteringDataSourceSection : NSObject, KrakenDataSourceSectionProtocol {
	var dataSource: FilteringDataSource?
	var sectionName: String = ""

	@objc dynamic var allCellModels = NSMutableArray() // [BaseCellModel]()
	var visibleCellModels = [BaseCellModel]()
//	@objc dynamic var oldVisibleCellModels: [BaseCellModel]?

	@objc dynamic var sectionVisible = false
	var forceSectionVisible: Bool? {	// If this is nil, section is visible iff it has any visible cells. T/F overrides.
		didSet { updateVisibility() }
	}
		
	override init() {
		super.init()
		
		// Watch for visibility OR height updates in cells; tell DS to go runupdates.
		allCellModels.tell(self, when: ["*.shouldBeVisible", "*.cellHeight"]) { observer, observed in
			observer.updateVisibility()
			observer.dataSource?.runUpdates()
		}
	}
	
	func updateVisibility() {
		// Determine section visibility. Force can set visibility on or off
		if let forceVis = forceSectionVisible {
			sectionVisible = forceVis
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
			sectionVisible = hasVisibleCells
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
		
		Log.debug("sizeForItemAt", ["height" : cellSize.height, "path" : indexPath])
		return cellSize
	}
	
	func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
		return visibleCellModels.count
	}
	
	func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
		let model = visibleCellModels[indexPath.row]
		let reuseID = model.reuseID()
		
		if dataSource?.registeredCellReuseIDs.contains(reuseID) == false {
			dataSource?.registeredCellReuseIDs.insert(reuseID)
			let classType = type(of: model).validReuseIDDict[reuseID]
			classType?.registerCells(with: collectionView)
		}
		return model.makeCell(for: collectionView, indexPath: indexPath)
	}
	
	// Only called by runUpdates, which is only in the top-level datasource
	func internalRunUpdates(for collectionView: UICollectionView?, sectionOffset: Int) {
		let cells = allCellModels as! [BaseCellModel]
		let newVisibleCells = cells.compactMap() { model in model.shouldBeVisible ? model : nil }
		let oldModels = visibleCellModels	
		visibleCellModels = newVisibleCells

		var deletes = [IndexPath]()
		var inserts = [IndexPath]()
		for cellIndex in 0 ..< oldModels.count {
			if !visibleCellModels.contains(oldModels[cellIndex]) {
				deletes.append(IndexPath(row: cellIndex, section: sectionOffset))
			}
		}
		for cellIndex in 0 ..< visibleCellModels.count {
			if !oldModels.contains(visibleCellModels[cellIndex]) {
				inserts.append(IndexPath(row: cellIndex, section: sectionOffset))
			}
		}
		if collectionView != nil {
			Log.debug("Inserts: \(inserts) Deletes: \(deletes) \nModels: \(self.visibleCellModels)")
		}
		else {
			Log.debug("THROWING AWAY Inserts: \(inserts) Deletes: \(deletes) \nModels: \(self.visibleCellModels)")
		}
		collectionView?.deleteItems(at: deletes)
		collectionView?.insertItems(at: inserts)
	}
}

@objc class FilteringDataSource: KrakenDataSource {
	@objc dynamic var allSections = NSMutableArray() // [FilteringDataSourceSection]()
	@objc dynamic var visibleSections = NSMutableArray() // [FilteringDataSourceSection]()
	
	var registeredCellReuseIDs = Set<String>()
	
	override init() {
		super.init()
		
		// Watch for section visibility changes; tell Collection to update
		allSections.tell(self, when: "*.sectionVisible") { observer, observed in
			observer.runUpdates()
		}?.execute()
		
		// Watch for sections that have updates to cell visibility; run updates.
//		self.tell(self, when: ["visibleSections.*.oldVisibleCellModels", "oldVisibleSections"]) { observer, observed in
//			let hasCellChanges = observed.visibleSections.reduce(true) { state, section in 
//				return state && (section as! FilteringDataSourceSection).oldVisibleCellModels != nil
//			}
//			
//			if observed.oldVisibleSections != nil || hasCellChanges {
//				observer.runUpdates()
//			}
//		}
	}	
	
	private var updateScheduled = false
	func runUpdates() {
		guard !updateScheduled else { return }
		updateScheduled = true
		DispatchQueue.main.async {
			self.updateScheduled = false
			
			// Are we currently the datasource for this collectionView?
			guard let cv = self.collectionView, cv.dataSource === self else {
				let allSections = self.allSections as! [KrakenDataSourceSectionProtocol]
				let newVisibleSections = allSections.compactMap() { model in model.sectionVisible ? model : nil }
				self.visibleSections = NSMutableArray(array: newVisibleSections)
				return
			}
		
			if !self.enableAnimations {
				UIView.setAnimationsEnabled(false)
			}

			cv.performBatchUpdates( {
				if self.itemsToRunAfterBatchUpdates == nil {
					self.itemsToRunAfterBatchUpdates = []
				}

				// Update visible sections, create locals for new and old visible sections for diffing
				let allSections = self.allSections as! [KrakenDataSourceSectionProtocol]
				let newVisibleSections = allSections.compactMap() { model in model.sectionVisible ? model : nil }
				let oldVisibleSections = self.visibleSections as! [KrakenDataSourceSectionProtocol]
				self.visibleSections = NSMutableArray(array: newVisibleSections)
			
				//
				Log.debug("Start of performBatchUpdates:", ["DS" : self, 
						"New Sections" : newVisibleSections.count, "Old Sections" : oldVisibleSections.count])
				
				var deletedSections = IndexSet()
				var insertedSections = IndexSet()
				for sectionIndex in 0 ..< oldVisibleSections.count {
					if !newVisibleSections.contains(where: { $0 === oldVisibleSections[sectionIndex] }) {
						deletedSections.insert(sectionIndex)
					}
				}
				for sectionIndex in 0 ..< newVisibleSections.count {
					if !oldVisibleSections.contains(where: { $0 === newVisibleSections[sectionIndex] }) {
						insertedSections.insert(sectionIndex)
					}
				}
				cv.deleteSections(deletedSections)
				cv.insertSections(insertedSections)
				Log.debug("SECTIONS: inserted \(insertedSections.count), deleted \(deletedSections.count)", 
						["DS" : self])				
				
				for sectionIndex in 0 ..< newVisibleSections.count {
					let section = newVisibleSections[sectionIndex] 
					if insertedSections.contains(sectionIndex) {
						// Run and discard cell-level updates on this just-inserted section
						section.internalRunUpdates(for: nil, sectionOffset: sectionIndex)
						continue
					}
					section.internalRunUpdates(for: cv, sectionOffset: sectionIndex)
				}
				
				if self.internalInvalidateLayout {
					self.internalInvalidateLayout = false
					let context = UICollectionViewFlowLayoutInvalidationContext()
					context.invalidateFlowLayoutDelegateMetrics = true
					self.collectionView?.collectionViewLayout.invalidateLayout(with: context)
				}
			
				Log.debug("End of batch", ["DS" : self])
			}, completion: { completed in
				Log.debug("After batch.", ["DS" : self, "blocks" : self.itemsToRunAfterBatchUpdates as Any])
				self.itemsToRunAfterBatchUpdates?.forEach { $0() }
				self.itemsToRunAfterBatchUpdates = nil
			})

			if !self.enableAnimations {
				UIView.setAnimationsEnabled(true)
			}
		}
		
		// something something TableView
	}
	
	@discardableResult func appendSection(named: String) -> FilteringDataSourceSection {
		let newSection = FilteringDataSourceSection()
		newSection.dataSource = self
		newSection.sectionName = named
		allSections.add(newSection)
		return newSection
	}

	@discardableResult func appendSection(section: KrakenDataSourceSectionProtocol) -> KrakenDataSourceSectionProtocol {
		section.dataSource = self
		allSections.add(section)
		return section
	}
	
	// Inserts the given section into allSections at a position just before the visible section with the given index.
	// That is, if the allSections section before the visible section at visibleIndex is hidden, insert happens between 
	// those 2 sections.
	@discardableResult func insertSection(_ section: KrakenDataSourceSectionProtocol, atVisibleIndex: Int) -> KrakenDataSourceSectionProtocol {
		section.dataSource = self
		if atVisibleIndex >= visibleSections.count {
			appendSection(section: section)
			return section
		}
		let object = visibleSections.object(at: atVisibleIndex)
		let allSectionsIndex = allSections.indexOfObjectIdentical(to: object)
		allSections.insert(section, at: allSectionsIndex)
		return section
	}
	
	// Inserts the given section into allSections at the given allSections index. Remember that this may not match 
	// the visibleSections indexes!
	@discardableResult func insertSection(_ section: KrakenDataSourceSectionProtocol, at index: Int) -> KrakenDataSourceSectionProtocol {
		section.dataSource = self
		allSections.insert(section, at: index)
		return section
	}
	
	// Returns deleted object; useful for implementing move as delete/inert
	@discardableResult func deleteSection(at index: Int) -> KrakenDataSourceSectionProtocol? {
		let result = allSections[index] as? KrakenDataSourceSectionProtocol
		allSections.removeObject(at: index)
		return result
	}
	
	// Returns cell, for chaining
	@discardableResult func appendCell<T: BaseCellModel>(_ cell: T, toSection name: String) -> T {
		let sections = allSections as! [KrakenDataSourceSectionProtocol]
		if let section = sections.first(where: { $0.sectionName == name } ) {
			section.append(cell)
		}
		return cell
	}
		
	func section(named: String) -> KrakenDataSourceSectionProtocol? {
		for section in allSections {
			if let section = section as? KrakenDataSourceSectionProtocol, section.sectionName == named {
				return section
			}
		}
		return nil
	}
	
	// Returns the cell for a given cell model, iff the cell is currently built by the CV.
	func cell(forModel: BaseCellModel) -> BaseCollectionViewCell? {
		var resultCell: BaseCollectionViewCell?
		collectionView?.visibleCells.forEach { cell in
			if let baseCell = cell as? BaseCollectionViewCell, baseCell.cellModel === forModel {
				resultCell = baseCell
			}
		}
		return resultCell
	}
	
}

extension FilteringDataSource: UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout {
    func numberOfSections(in collectionView: UICollectionView) -> Int {
		Log.debug("numberOfSections", ["count" : self.visibleSections.count, "DS" : self])
    	return visibleSections.count
    }

	func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
		let sections = visibleSections as! [KrakenDataSourceSectionProtocol]
		let count = sections[section].collectionView(collectionView, numberOfItemsInSection: 0)
		return count
	}
	
	func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
		let sections = visibleSections as! [KrakenDataSourceSectionProtocol]
		let sectionPath = IndexPath(row: indexPath.row, section: 0)
		let resultCell = sections[indexPath.section].collectionView(collectionView, cellForItemAt: sectionPath)
		if let cell = resultCell as? BaseCollectionViewCell, let vc = viewController as? BaseCollectionViewController {
			cell.viewController = vc
		}
		return resultCell
	}
	
//	func collectionView(_ collectionView: UICollectionView, didHighlightItemAt indexPath: IndexPath) {
//		let sections = visibleSections as! [KrakenDataSourceSectionProtocol]
//		let model = sections[indexPath.section].visibleCellModels[indexPath.row]
//		model.cellTapped()
//	}

	func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, 
			sizeForItemAt indexPath: IndexPath) -> CGSize {
		let sections = visibleSections as! [KrakenDataSourceSectionProtocol]
		let sectionPath = IndexPath(row: indexPath.row, section: 0)
//		let protoSize = sections[indexPath.section].sizeForCell(for: collectionView, indexPath: sectionPath)
		let protoSize = sections[indexPath.section].collectionView?(collectionView, 
				layout: collectionView.collectionViewLayout, sizeForItemAt: sectionPath)
								
		return protoSize ?? CGSize(width: 50, height: 50)
	}

}
