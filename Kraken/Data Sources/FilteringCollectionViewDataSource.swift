//
//  FilteringCollectionViewDataSource.swift
//  Kraken
//
//  Created by Chall Fry on 4/19/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit

// This has to be an @objc protocol, which has cascading effects.
@objc protocol FilteringDataSourceSectionProtocol: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
	var dataSource: FilteringDataSource? { get set }
	var sectionName: String { get set }
	var sectionVisible: Bool { get set }
		
	func append(_ cell: BaseCellModel)
	func runUpdates(for collectionView: UICollectionView?, sectionOffset: Int)
}

@objc class FilteringDataSourceSection : NSObject, FilteringDataSourceSectionProtocol {
	var dataSource: FilteringDataSource?
	var sectionName: String = ""

	@objc dynamic var allCellModels = NSMutableArray() // [BaseCellModel]()
	var visibleCellModels = [BaseCellModel]()
	@objc dynamic var oldVisibleCellModels: [BaseCellModel]?

	@objc dynamic var sectionVisible = false
	var forceSectionVisible: Bool? {	// If this is nil, section is visible iff it has any visible cells. T/F overrides.
		didSet { updateVisibility() }
	}
		
	override init() {
		super.init()
		
		// Watch for visibility OR height updates in cells; tell DS to go runupdates.
		allCellModels.tell(self, when: ["*.shouldBeVisible", "*.cellHeight"]) { observer, observed in
			let cells = observer.allCellModels as! [BaseCellModel]
			let newVisibleCells = cells.compactMap() { model in model.shouldBeVisible ? model : nil }
			if observer.oldVisibleCellModels == nil {
				observer.oldVisibleCellModels = observer.visibleCellModels	
			}
			observer.visibleCellModels = newVisibleCells
			
			observer.updateVisibility()
			observer.dataSource?.runUpdates()
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
	@discardableResult func append<T: BaseCellModel>(cell: T) -> T {
		allCellModels.add(cell)
		return cell
	}
	
	func append(_ cell: BaseCellModel) {
		allCellModels.add(cell)
	}
	
	func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, 
			sizeForItemAt indexPath: IndexPath) -> CGSize {
		let model = visibleCellModels[indexPath.row]

		if let protoCell = model.makePrototypeCell(for: collectionView, indexPath: indexPath) {
			let newSize = protoCell.calculateSize()
			model.unbind(cell: protoCell)
   			return newSize
		}

		return CGSize(width:collectionView.bounds.size.width, height: 50)
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
	
	// 
	func runUpdates(for collectionView: UICollectionView?, sectionOffset: Int) {
		var deletes = [IndexPath]()
		var inserts = [IndexPath]()
		if let oldModels = oldVisibleCellModels {
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
			collectionView?.deleteItems(at: deletes)
			collectionView?.insertItems(at: inserts)
			oldVisibleCellModels = nil
		}
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
			let allSections = observer.allSections as! [FilteringDataSourceSectionProtocol]
			let newVisibleSections = allSections.compactMap() { model in model.sectionVisible ? model : nil }
			if observer.oldVisibleSections == nil {
				observer.oldVisibleSections = observer.visibleSections
			}
			observer.visibleSections = NSMutableArray(array: newVisibleSections)
			observer.runUpdates()
		}
		
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
	
	func register(with cv: UICollectionView) {
		collectionView = cv
		cv.dataSource = self
		cv.delegate = self
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
						print ("inserted \(insertedSections) \ndeleted \(deletedSections)")
						self.oldVisibleSections = nil
					}
					
					for sectionIndex in 0 ..< self.visibleSections.count {
					 	let section = self.visibleSections[sectionIndex] as! FilteringDataSourceSectionProtocol
						if insertedSections.contains(sectionIndex) {
							// Run and discard cell-level updates on this just-inserted section
							section.runUpdates(for: nil, sectionOffset: sectionIndex)
							continue
						}
						section.runUpdates(for: cv, sectionOffset: sectionIndex)
					}
				}, completion: nil)

				if !self.enableAnimations {
					UIView.setAnimationsEnabled(true)
				}
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

	@discardableResult func appendSection(section: FilteringDataSourceSectionProtocol) -> FilteringDataSourceSectionProtocol {
		section.dataSource = self
		allSections.add(section)
		return section
	}
	
	// Returns cell, for chaining
	@discardableResult func appendCell<T: BaseCellModel>(_ cell: T, toSection name: String) -> T {
		let sections = allSections as! [FilteringDataSourceSectionProtocol]
		if let section = sections.first(where: { $0.sectionName == name } ) {
			section.append(cell)
		}
		return cell
	}
		
	func section(named: String) -> FilteringDataSourceSectionProtocol? {
		for section in allSections {
			if let section = section as? FilteringDataSourceSectionProtocol, section.sectionName == named {
				return section
			}
		}
		return nil
	}

}

extension FilteringDataSource: UICollectionViewDataSource, UICollectionViewDelegate,  UICollectionViewDelegateFlowLayout {
    func numberOfSections(in collectionView: UICollectionView) -> Int {
		if oldVisibleSections == nil {
			oldVisibleSections = visibleSections
		}

    	return visibleSections.count
    }

	func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
		let sections = visibleSections as! [FilteringDataSourceSectionProtocol]
		let count = sections[section].collectionView(collectionView, numberOfItemsInSection: 0)
		return count
	}
	
	func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
		let sections = visibleSections as! [FilteringDataSourceSectionProtocol]
		let sectionPath = IndexPath(row: indexPath.row, section: 0)
		let resultCell = sections[indexPath.section].collectionView(collectionView, cellForItemAt: sectionPath)
		if let cell = resultCell as? BaseCollectionViewCell, let vc = viewController as? BaseCollectionViewController {
			cell.viewController = vc
		}
		return resultCell
	}
	
//	func collectionView(_ collectionView: UICollectionView, didHighlightItemAt indexPath: IndexPath) {
//		let sections = visibleSections as! [FilteringDataSourceSectionProtocol]
//		let model = sections[indexPath.section].visibleCellModels[indexPath.row]
//		model.cellTapped()
//	}

	func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, 
			sizeForItemAt indexPath: IndexPath) -> CGSize {
		let sections = visibleSections as! [FilteringDataSourceSectionProtocol]
		let sectionPath = IndexPath(row: indexPath.row, section: 0)
//		let protoSize = sections[indexPath.section].sizeForCell(for: collectionView, indexPath: sectionPath)
		let protoSize = sections[indexPath.section].collectionView?(collectionView, 
				layout: collectionView.collectionViewLayout, sizeForItemAt: sectionPath)
		return protoSize ?? CGSize(width: 50, height: 50)
	}

}
