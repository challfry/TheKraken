//
//  FilteringCollectionViewDataSource.swift
//  Kraken
//
//  Created by Chall Fry on 4/19/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit

@objc class FilteringDataSourceSection : NSObject {
	let dataSource: FilteringDataSource
	var sectionName: String = ""

	dynamic var allCellModels = NSMutableArray() // [BaseCellModel]()
	var visibleCellModels = [BaseCellModel]()
	dynamic var oldVisibleCellModels: [BaseCellModel]?

	@objc dynamic var sectionVisible = false
	var forceSectionVisible: Bool? {	// If this is nil, section is visible iff it has any visible cells. T/F overrides.
		didSet { updateVisibility() }
	}
		
	init(_ dataSource: FilteringDataSource) {
		self.dataSource = dataSource
		super.init()
		
		// Watch for visibility OR height updates in cells; tell DS to go runupdates.
		allCellModels.tell(self, when: ["*.shouldBeVisible", "*.cellHeight"]) { observer, observed in
			let cells = observer.allCellModels as! [BaseCellModel]
			let newVisibleCells = cells.compactMap() { model in model.shouldBeVisible ? model : nil }
			observer.oldVisibleCellModels = observer.visibleCellModels	
			observer.visibleCellModels = newVisibleCells
			
			observer.updateVisibility()
			dataSource.runUpdates()
		}
	}
	
	func updateVisibility() {
		// Determine section visibility
		if let forceVis = forceSectionVisible {
			sectionVisible = forceVis
		}
		else {
			sectionVisible = !visibleCellModels.isEmpty
		}
	}
	
	// Returns input cell, for chaining
	@discardableResult func append<T: BaseCellModel>(_ cell: T) -> T{
		allCellModels.add(cell)
		return cell
	}
}

@objc class FilteringDataSource: NSObject {
	@objc dynamic var allSections = NSMutableArray() // [FilteringDataSourceSection]()
	@objc dynamic var visibleSections = NSMutableArray() // [FilteringDataSourceSection]()
	@objc dynamic var oldVisibleSections: NSMutableArray? // [FilteringDataSourceSection]()
	
	weak var collectionView: UICollectionView?
	weak var tableView: UITableView?
	weak var viewController: UIViewController? 			// So that cells can segue/present other VCs.
	var enableAnimations = false			// Generally, set to true in viewDidAppear
	var registeredCellReuseIDs = Set<String>()
	
	override init() {
		super.init()
		
		// Watch for section visibility changes; tell Collection to update
		allSections.tell(self, when: "*.sectionVisible") { observer, observed in
			let allSections = observer.allSections as! [FilteringDataSourceSection]
			let newVisibleSections = allSections.compactMap() { model in model.sectionVisible ? model : nil }
			observer.oldVisibleSections = observer.visibleSections
			observer.visibleSections = NSMutableArray(array: newVisibleSections)
			observer.runUpdates()
		}
		
		// Watch for sections that have updates to cell visibility; run updates.
		self.tell(self, when: ["visibleSections.*.oldVisibleCellModels", "oldVisibleSections"]) { observer, observed in
			observer.runUpdates()
		}
	}
	
	var updateScheduled = false
	func runUpdates() {
		guard !updateScheduled else { return }
		DispatchQueue.main.async {
			self.updateScheduled = false
			if let cv = self.collectionView {
				if !self.enableAnimations {
					UIView.setAnimationsEnabled(false)
				}

				cv.performBatchUpdates( {
					var deletedSections = IndexSet()
					var insertedSections = IndexSet()
					if let oldSections = self.oldVisibleSections {
						for sectionIndex in 0 ..< oldSections.count {
							if !self.visibleSections.contains(oldSections[sectionIndex]) {
								deletedSections.insert(sectionIndex)
							}
						}
						for sectionIndex in 0 ..< self.visibleSections.count {
							if !oldSections.contains(self.visibleSections[sectionIndex]) {
								insertedSections.insert(sectionIndex)
							}
						}
						cv.deleteSections(deletedSections)
						cv.insertSections(insertedSections)
						self.oldVisibleSections = nil
					}
					
					var deletedCells = [IndexPath]()
					var insertedCells = [IndexPath]()
					for sectionIndex in 0 ..< self.visibleSections.count {
					 	let section = self.visibleSections[sectionIndex] as! FilteringDataSourceSection
						if insertedSections.contains(sectionIndex) {
							section.oldVisibleCellModels = nil
							continue
						}
						
						if let oldModels = section.oldVisibleCellModels {
							for cellIndex in 0 ..< oldModels.count {
								if !section.visibleCellModels.contains(oldModels[cellIndex]) {
									deletedCells.append(IndexPath(indexes:[sectionIndex, cellIndex]))
								}
							}
							for cellIndex in 0 ..< section.visibleCellModels.count {
								if !oldModels.contains(section.visibleCellModels[cellIndex]) {
									insertedCells.append(IndexPath(indexes:[sectionIndex, cellIndex]))
								}
							}
							section.oldVisibleCellModels = nil
						}
					}
					cv.deleteItems(at: deletedCells)
					cv.insertItems(at: insertedCells)
				}, completion: nil)

				if !self.enableAnimations {
					UIView.setAnimationsEnabled(true)
				}
			}
		}
		
		// something something TableView
	}
	
	@discardableResult func appendSection(named: String) -> FilteringDataSourceSection {
		let newSection = FilteringDataSourceSection(self)
		newSection.sectionName = named
		allSections.add(newSection)
		return newSection
	}
	
	func appendCell(_ cell: BaseCellModel, toSection name: String) {
		let sections = allSections as! [FilteringDataSourceSection]
		if let section = sections.first(where: { $0.sectionName == name } ) {
			section.allCellModels.add(cell)
		}
	}
		
	func section(named: String) -> FilteringDataSourceSection? {
		for section in allSections {
			if let section = section as? FilteringDataSourceSection, section.sectionName == named {
				return section
			}
		}
		return nil
	}

}

extension FilteringDataSource: UICollectionViewDataSource, UICollectionViewDelegate,  UICollectionViewDelegateFlowLayout {
    func numberOfSections(in collectionView: UICollectionView) -> Int {
    	return visibleSections.count
    }

	func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
		let sections = visibleSections as! [FilteringDataSourceSection]
		return sections[section].visibleCellModels.count
	}
	
	func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
		let sections = visibleSections as! [FilteringDataSourceSection]
		let model = sections[indexPath.section].visibleCellModels[indexPath.row]
		let reuseID = model.reuseID()
		if !registeredCellReuseIDs.contains(reuseID) {
			registeredCellReuseIDs.insert(reuseID)
			let classType = type(of: model).validReuseIDDict[reuseID]
			classType?.registerCells(with: collectionView)
		}
		return model.makeCell(for: collectionView, indexPath: indexPath)
	}
	
	func collectionView(_ collectionView: UICollectionView, didHighlightItemAt indexPath: IndexPath) {
		let sections = visibleSections as! [FilteringDataSourceSection]
		let model = sections[indexPath.section].visibleCellModels[indexPath.row]
		model.cellTapped()
	}

	func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, 
			sizeForItemAt indexPath: IndexPath) -> CGSize {
		let sections = visibleSections as! [FilteringDataSourceSection]
		let model = sections[indexPath.section].visibleCellModels[indexPath.row]

		if let protoCell = model.makePrototypeCell(for: collectionView, indexPath: indexPath) {
			let newSize = protoCell.calculateSize()
			model.unbind(cell: protoCell)
   			return newSize
		}

		return CGSize(width:414, height: 50)
	}

}
