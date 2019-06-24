//
//  FilteringCollectionViewDataSource.swift
//  Kraken
//
//  Created by Chall Fry on 4/19/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit

@objc class FilteringDataSourceSection : NSObject, KrakenDataSourceSectionProtocol {
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
		let cellModel = visibleCellModels[indexPath.row]

		if let protoCell = cellModel.makePrototypeCell(for: collectionView, indexPath: indexPath) {
			let newSize = protoCell.calculateSize()
			cellModel.cellSize = newSize
			cellModel.unbind(cell: protoCell)
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
	
	// Only called by runUpdates, which is only in the top-level datasource
	func internalRunUpdates(for collectionView: UICollectionView?, sectionOffset: Int) {
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

@objc class FilteringDataSource: KrakenDataSource {
	@objc dynamic var allSections = NSMutableArray() // [FilteringDataSourceSection]()
	@objc dynamic var visibleSections = NSMutableArray() // [FilteringDataSourceSection]()
	@objc dynamic var oldVisibleSections: NSMutableArray? // [FilteringDataSourceSection]()
	
	var registeredCellReuseIDs = Set<String>()
	
	override init() {
		super.init()
		
		// Watch for section visibility changes; tell Collection to update
		allSections.tell(self, when: "*.sectionVisible") { observer, observed in
			let allSections = observer.allSections as! [KrakenDataSourceSectionProtocol]
			let newVisibleSections = allSections.compactMap() { model in model.sectionVisible ? model : nil }
			if observer.oldVisibleSections == nil {
				observer.oldVisibleSections = observer.visibleSections
			}
			observer.visibleSections = NSMutableArray(array: newVisibleSections)
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
	
	override func register(with cv: UICollectionView, viewController: BaseCollectionViewController? = nil) {
		super.register(with: cv, viewController: viewController)
		self.viewController = viewController
		cv.dataSource = self
		cv.delegate = self
	}

	
	private var updateScheduled = false
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
					
					//
//					print ("Start of Batch: \(self.visibleSections.count) sections, oldVis = \(self.oldVisibleSections?.count)" )
					
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
//						print ("SECTIONS: inserted \(insertedSections.count), deleted \(deletedSections.count)")
						self.oldVisibleSections = nil
					}
					
					for sectionIndex in 0 ..< self.visibleSections.count {
					 	let section = self.visibleSections[sectionIndex] as! KrakenDataSourceSectionProtocol
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

	@discardableResult func appendSection(section: KrakenDataSourceSectionProtocol) -> KrakenDataSourceSectionProtocol {
		section.dataSource = self
		allSections.add(section)
		return section
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
	
}

extension FilteringDataSource: UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout {
    func numberOfSections(in collectionView: UICollectionView) -> Int {
//		print ("Someone asked how many sections. Responded with \(visibleSections.count)")
		if oldVisibleSections == nil, visibleSections.count > 0 {
			oldVisibleSections = visibleSections
		}
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
				
		//
//		let x = collectionView.collectionViewLayout as! UICollectionViewFlowLayout
//		protoSize?.width = 100
//		print ("Cell Size: \(protoSize), cv: \(collectionView.bounds.size.width), content: \(collectionView.contentInset), section:\(x.sectionInset)")
				
		return protoSize ?? CGSize(width: 50, height: 50)
	}

}
