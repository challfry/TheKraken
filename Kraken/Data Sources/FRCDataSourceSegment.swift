//
//  FetchedResultsControllerDataSource.swift
//  Kraken
//
//  Created by Chall Fry on 5/13/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit
import CoreData
import os

// A simple cell model and binding protocol. Useful for when your cell can set itself up from data in the model object
// and can have knowledge of what that object is. Not for use with generic cells that just get told what text to put where,
// or for cells that have to save state back to their cellModel.
@objc protocol FetchedResultsBindingProtocol : KrakenCellBindingProtocol {
	var model: NSFetchRequestResult? { get set }
}

fileprivate class FRCDifference {
	var id: NSManagedObjectID
	var isInsertOrDelete: Bool
	var oldIndexPath: IndexPath?
	var newIndexPath: IndexPath?
	
	init(_ objectID: NSManagedObjectID) {
		id = objectID
		isInsertOrDelete = false
	}
}

fileprivate class FRCSection {
	var name: String				// Matches NSFetchedResultsSectionInfo.name
	var cellModels: [BaseCellModel]

	var isInsertOrDelete: Bool
	var oldIndex: Int?
	var newIndex: Int?
	
	init(_ name: String) {
		self.name = name
		cellModels = []
		isInsertOrDelete = false
	}

}

class FetchedResultsCellModel : BaseCellModel, FetchedResultsBindingProtocol {
	@objc dynamic var model: NSFetchRequestResult? {
		didSet {
			// Hide the cell if we don't have anything to show
			shouldBeVisible = model != nil
		}
	}
	var reuse: String
	
	init(withModel: NSFetchRequestResult?, reuse: String, bindingWith: Protocol = FetchedResultsBindingProtocol.self) {
		self.reuse = reuse
		super.init(bindingWith: bindingWith)
		model = withModel
		self.shouldBeVisible = model != nil
	}
	
	override func reuseID(traits: UITraitCollection) -> String {
		return reuse
	}
}

protocol FRCDataSourceLoaderDelegate {
	func userIsViewingCell(at: IndexPath)
}

@objc class FRCDataSourceSegmentObservationWrapper: NSObject {
	@objc dynamic var isEmpty: Bool = true
}

// Note: For some reason I couldn't put protocol conformance into extensions, and I didn't bother trying to figure out why.
// Why would I do such a terrible thing? Because you can put the methods in the class and move on. 
class FRCDataSourceSegment<FetchedObjectType>: KrakenDataSourceSegment, KrakenDataSourceSegmentProtocol,
		NSFetchedResultsControllerDelegate, 
		UICollectionViewDataSourcePrefetching where FetchedObjectType : NSManagedObject {
		
	var log = CollectionViewLog(instanceEnabled: false)

	var fetchRequest = NSFetchRequest<FetchedObjectType>()
	var frc: NSFetchedResultsController<FetchedObjectType>?
	fileprivate var cellModelSections: [FRCSection] = []
	
	// Hack to make isEmpty an observable property.
	var wrapper =  FRCDataSourceSegmentObservationWrapper()
	
	// Clients need to implement this to populate the cell's data from the model.
	var createCellModel: ((_ fromModel: FetchedObjectType) -> BaseCellModel)?
	
	// 
	var loaderDelegate: FRCDataSourceLoaderDelegate? = nil
		
	var insertSections = IndexSet()
	var deleteSections = IndexSet()
	var moveSections = [(Int, Int)]()			// from, to
	var insertCells = [IndexPath]()
	var deleteCells = [IndexPath]()
	var moveCells = [(IndexPath, IndexPath)]()			// from, to
	var reloadCells = [IndexPath]()	

	override init() {
		fetchRequest.entity = FetchedObjectType.entity()
		fetchRequest.predicate = NSPredicate(value: false)
		fetchRequest.fetchBatchSize = 50
		super.init()
	}
	
	init(withCustomFRC: NSFetchedResultsController<FetchedObjectType>) {
		frc = withCustomFRC
		fetchRequest = withCustomFRC.fetchRequest
		super.init()
//		frc?.delegate = self
	}
		
	// Configures the Fetch Request, kicks off the FRC, and sets up our cellModels with the initial FRC results.
	// Call this up front, and again whenever the predicate, sort, or factory function need to change.
	func activate(predicate: NSPredicate?, sort: [NSSortDescriptor]?, 
			cellModelFactory: ((_ from: FetchedObjectType) -> BaseCellModel)?, sectionNameKeyPath: String? = nil) {
		self.createCellModel = cellModelFactory

		if let pred = predicate {
			fetchRequest.predicate = pred 
			log.d("New predicate \(pred)")
		}
		if let sortDescriptors = sort {
			fetchRequest.sortDescriptors = sortDescriptors
		}		
		
		
		if frc == nil {
			frc = NSFetchedResultsController(fetchRequest: fetchRequest, 
						managedObjectContext: LocalCoreData.shared.mainThreadContext, 
						sectionNameKeyPath: sectionNameKeyPath, cacheName: nil)
			frc?.delegate = self
		}
		
		do {
			try frc?.performFetch()
		}
		catch {
			CoreDataLog.error("Couldn't fetch pending replies.", [ "error" : error ])
		}

		// performFetch completely changes the result set; any previous adds/removes are no longer valid
		deleteSections.removeAll()
		insertSections.removeAll()
		moveSections.removeAll()
		deleteCells.removeAll()
		moveCells.removeAll()
		reloadCells.removeAll()
		insertCells.removeAll()

		// After performFetch(), the FRC does not send change batches for the initial results.
		// We don't need to update cellModelSections here, but we do need to gather changes and schedule an update.
		if cellModelSections.count == 0 {
			// Easy case, new DS
			if let sections = frc?.sections {
				if sections.count > 1 || sections.count == 1 && sections[0].numberOfObjects > 0 {
					insertSections.insert(integersIn:0..<sections.count)
				}
			}
		}
		else {
			if let frcSections = frc?.sections {
				log.d("New fetch found \(frcSections.count) sections")
				log.d("    sectionNames: \(frcSections.map { $0.name  })")
				
				// Handle Sections
				let newSectionNames: Set<String> = Set(frcSections.map { $0.name } )
				for (sectionIndex, section) in cellModelSections.enumerated() {
					section.oldIndex = sectionIndex
					section.isInsertOrDelete = newSectionNames.contains(section.name)
				}
				let oldSectionNames = cellModelSections.map { $0.name }
				var oldSectionDict = Dictionary(zip(oldSectionNames, cellModelSections)) { first, second in return first } 
				var commonSections: [FRCSection] = []
				var newSectionArray: [FRCSection] = []
				for (sectionIndex, section) in frcSections.enumerated() {
					if let commonSection = oldSectionDict.removeValue(forKey: section.name) {
						commonSection.newIndex = sectionIndex
						commonSections.append(commonSection)
						newSectionArray.append(commonSection)
					}
					else {
						let newSection = FRCSection(section.name)
						newSection.isInsertOrDelete	= true
						insertSections.insert(sectionIndex)
						newSectionArray.append(newSection)
					}
				}
				for section in cellModelSections {
					if !newSectionNames.contains(section.name), let oldIndex = section.oldIndex {
						deleteSections.insert(oldIndex)
					}
				}
				var newSectionIterator = newSectionArray.makeIterator()
				var oldSectionIterator = cellModelSections.makeIterator()
				var newSection = newSectionIterator.next()
				var oldSection = oldSectionIterator.next()
				while newSection != nil && oldSection != nil {
					while let nv = newSection, nv.isInsertOrDelete {
						newSection = newSectionIterator.next()
					}
					while let ov = oldSection, ov.isInsertOrDelete {
						oldSection = oldSectionIterator.next()
					}
					if oldSection?.name == newSection?.name {			
						newSection = newSectionIterator.next()
						oldSection = oldSectionIterator.next()
					}
					else {
						if let nv = newSection, let newIndex = nv.newIndex, let oldIndex = nv.oldIndex {
							moveSections.append((oldIndex, newIndex))
							newSection = newSectionIterator.next()
							nv.isInsertOrDelete	= true
						}
					}
				}
				
			
				// Step 1: Make a dict of all the objectIDs in the old state
				var oldCellDict: [ NSManagedObjectID : FRCDifference ] = [:]
				for (sectionIndex, section) in cellModelSections.enumerated() {
					for (cellIndex, cellModel) in section.cellModels.enumerated() {
						if let frcCellModel = cellModel as? FetchedResultsBindingProtocol,
								let model = frcCellModel.model as? NSManagedObject {
							let diff = FRCDifference(model.objectID)
							diff.oldIndexPath = IndexPath(row: cellIndex, section: sectionIndex)
							oldCellDict[model.objectID] = diff
						}
					}
				}
				log.d("oldCellDict \(oldCellDict)")
				
				// Step 2: Iterate through the new objects, generate differences between old and new. 
				var newCellArray: [FRCDifference] = []
				var commonCells: [ NSManagedObjectID : FRCDifference ] = [:]
				for (sectionIndex, section) in frcSections.enumerated() {
					var insertsThisSection: [IndexPath] = []
					if let cellArray = section.objects as? [NSManagedObject] {
						for (cellIndex, model) in cellArray.enumerated() {
							if let commonDiffObject = oldCellDict.removeValue(forKey: model.objectID) {
								// This is a cell common to old and new
								commonDiffObject.newIndexPath = IndexPath(row: cellIndex, section: sectionIndex)
								newCellArray.append(commonDiffObject) 
								commonCells.updateValue(commonDiffObject, forKey: model.objectID)
							}
							else {
								// Cells in new that aren't in old are inserts
								insertsThisSection.append(IndexPath(row: cellIndex, section: sectionIndex))
								let insertObj = FRCDifference(model.objectID)
								insertObj.isInsertOrDelete = true
								insertObj.newIndexPath = IndexPath(row: cellIndex, section: sectionIndex)
								newCellArray.append(insertObj)
							}
						}
					}
					
					insertCells.append(contentsOf: insertsThisSection)
				}
				
				// Step 3: Iterate the old cells again, mark deletes
				var oldCellArray: [FRCDifference] = []
				for (sectionIndex, section) in cellModelSections.enumerated() {
					for (cellIndex, cellModel) in section.cellModels.enumerated() {
						var deletesThisSection: [IndexPath] = []
					//	var foundCommonCellThisSection: Bool = false
						if let frcCellModel = cellModel as? FetchedResultsBindingProtocol,
								let model = frcCellModel.model as? NSManagedObject {
							if let commonDiffObject = commonCells[model.objectID] {
								commonDiffObject.oldIndexPath = IndexPath(row: cellIndex, section: sectionIndex)
								oldCellArray.append(commonDiffObject) 
						//		foundCommonCellThisSection = true
							} 
							else if let oldDiffObject = oldCellDict[model.objectID] {
								oldDiffObject.isInsertOrDelete = true
								oldCellArray.append(oldDiffObject)
								if let oldPath = oldDiffObject.oldIndexPath {
									deletesThisSection.append(oldPath)
								}
							}
							else {
								log.error("Diffing error. Each cell got put into one of 2 dictionaries, and now this cell is in neither of them.")
							}
						}
						
						deleteCells.append(contentsOf: deletesThisSection)
					}
				}
				
				// Step 4: Dual Iterate. New until common cell, then old until common cell, then either Move Op to the
				// index in new, or increment both old and new if they're the same cell.
				var newIterator = newCellArray.makeIterator()
				var oldIterator = oldCellArray.makeIterator()
				var newValue: FRCDifference? = newIterator.next()
				var oldValue: FRCDifference? = oldIterator.next()
				while newValue != nil && oldValue != nil {
					while let nv = newValue, nv.isInsertOrDelete {
						newValue = newIterator.next()
					}
					while let ov = oldValue, ov.isInsertOrDelete {
						oldValue = oldIterator.next()
					}
					if oldValue?.id == newValue?.id {
						// TODO: Check the case where this cell is 'next' in both new and old, and yet we need to perform a
						// move because it crosses sections in one but not the other.
					
						newValue = newIterator.next()
						oldValue = oldIterator.next()
					}
					else {
						if let nv = newValue, let newIndexPath = nv.newIndexPath, let oldIndexPath = nv.oldIndexPath {
							moveCells.append((oldIndexPath, newIndexPath))
							newValue = newIterator.next()
							nv.isInsertOrDelete	= true
						}
						
					}
				}
				
				// Step 5: Iterate old cells a third time, process deletes, look for deleted sections?. 
//				let deletedPaths = oldCellDict.values
//				log.d("deletedpaths \(deletedPaths)")
//				for sectionIndex in 0..<cellModelSections.count {
//					let pathsThisSection = deletedPaths.filter { $0.section == sectionIndex }
//					if pathsThisSection.count == cellModelSections[sectionIndex].count {
//						// All the cells in this section have been deleted
//						deleteSections.insert(sectionIndex)
//					}
//					else if pathsThisSection.count > 0 {
//						deleteCells.append(contentsOf: pathsThisSection)
//					}
//				}
			}
		}
		dataSource?.runUpdates()
		wrapper.isEmpty = frc?.fetchedObjects?.isEmpty ?? true
	}
	
	func changePredicate(to: NSPredicate) {
		activate(predicate: to, sort: fetchRequest.sortDescriptors, cellModelFactory: createCellModel)
	}
	
	func indexPathNearest(to: FetchedResultsBindingProtocol) -> IndexPath? {
		guard let model = to.model as? FetchedObjectType else { return nil }
	
		if let exactResult = frc?.indexPath(forObject: model) {
			return exactResult
		}
		
		if let desc = frc?.fetchRequest.sortDescriptors?[0],
				let closeObject = frc?.fetchedObjects?.first(where: { desc.compare($0, to: model) != .orderedAscending }),
				let closeResult = frc?.indexPath(forObject: closeObject) {
			return closeResult
		}
		
		return nil
	}
		
// MARK: FetchedResultsControllerDelegate
	func controllerWillChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
	}
	
	func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, 
			didChange sectionInfo: NSFetchedResultsSectionInfo, atSectionIndex sectionIndex: Int, for type: NSFetchedResultsChangeType) {
		log.debug("In FRC Section Change Delegate Callback", ["numSections" : self.cellModelSections.count,
				 "type" : type.rawValue, "section" : sectionIndex ])
		switch type {
		case .insert:
			insertSections.insert(sectionIndex)
		case .delete:
			deleteSections.insert(sectionIndex)
		//		case .move:  -- Apple docs say sections will never use .move
		default:
			fatalError()
		}
	}
	
	func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange anObject: Any,
			at indexPath: IndexPath?, for type: NSFetchedResultsChangeType, newIndexPath: IndexPath?) {
		
		let sec0Count = cellModelSections.count > 0 ? cellModelSections[0].cellModels.count : 0			
		log.debug("In FRC Callback", ["numSections" : self.cellModelSections.count, "section0Count" : sec0Count,
				 "type" : type.rawValue, "indexPath" : indexPath ?? newIndexPath ?? "hmm"])
				 
		if let obj = anObject as? NSManagedObject, obj.objectID.isTemporaryID {
			return
		}

		switch type {
		case .insert:
			guard let newIndexPath = newIndexPath else { return }
			insertCells.append(newIndexPath)
		case .delete:
			guard let indexPath = indexPath else { return }
			if let index = reloadCells.firstIndex(of: indexPath) {
				reloadCells.remove(at: index)
			}	
			deleteCells.append(indexPath)
		case .move:
			guard let indexPath = indexPath,  let newIndexPath = newIndexPath else { return }
			// If the from and to index paths are the same -- wait, why is the FRC calling us?
			if indexPath == newIndexPath { return }
			moveCells.append((indexPath, newIndexPath))
			log.debug("FRC Callback added move from \(indexPath) to \(newIndexPath)")
		case .update:
			guard let indexPath = indexPath else { return }
			reloadCells.append(indexPath)
		@unknown default:
			fatalError()
		}
	}

	func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
//		if insertCells.count > 0 || moveCells.count > 0 || deleteCells.count > 0 ||
//				insertSections.count > 0 || deleteSections.count > 0 {
			dataSource?.runUpdates()
//		}
//		else {
//			log.d("Not scheduling update in response to FRC content change; change is only reloads.")
//		}
		wrapper.isEmpty = frc?.fetchedObjects?.isEmpty ?? true
	}

// MARK: UICollectionView Data Source
    func numberOfSections(in collectionView: UICollectionView) -> Int {
		log.debug("NumberOfSections for FRC: \(self.cellModelSections.count)")
    	return cellModelSections.count
    }

	func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
		guard cellModelSections.count > section else { 
			log.error("Datasource was asked numberOfItemsInSection for bad section #.")
			return 0 
		}
		
		let numItems = cellModelSections[section].cellModels.count
		log.debug("numberOfItemsInSection", ["offsetSection" : section, "numObjects" : numItems, "DS" : self])
		return numItems
	}
	
	func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath, offsetPath: IndexPath) -> UICollectionViewCell {
		guard cellModelSections.count > offsetPath.section else { 
			log.error("Datasource was asked cellForItemAt for bad section #.")
			return UICollectionViewCell()
		}
		let section = cellModelSections[offsetPath.section]
		guard section.cellModels.count > offsetPath.row else { 
			log.error("Datasource was asked cellForItemAt for bad item #.")
			return UICollectionViewCell()
		}

		log.d("Asking for cell at indexpath", [ "indexPath" : indexPath ])
		let cellModel = section.cellModels[offsetPath.row]
		
		// If this reuseID isn't registered with the CV yet, ask the cell model to register its cell classes and reuseIDs.
		let reuseID = cellModel.reuseID(traits: collectionView.traitCollection)
		if dataSource?.registeredCellReuseIDs[reuseID] == nil {
			let classType = type(of: cellModel).validReuseIDDict[reuseID]
			classType?.registerCells(with: collectionView)
			dataSource?.registeredCellReuseIDs[reuseID] = classType
		}
		let cell = cellModel.makeCell(for: collectionView, indexPath: indexPath)
		return cell
	}
	


// MARK: UICollectionView Data Source Prefetch

	// Not currently used.
	func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
		log.d("Prefetch at: \(indexPaths)", ["DS" : self])
	}

	func collectionView(_ collectionView: UICollectionView, cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {
		log.d("Cancel Prefetch at: \(indexPaths)", ["DS" : self])
	}
		
// MARK: UICollectionView Delegate

	func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
		log.debug("shouldSelectItemAt", ["indexPath" : indexPath, "DS" : self])
		return true
	}
	
	func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
		log.debug("didSelectItemAt", ["indexPath" : indexPath, "DS" : self])
	}
	
	func collectionView(_ collectionView: UICollectionView, shouldDeselectItemAt indexPath: IndexPath) -> Bool {
		log.debug("shouldDeselectItemAt", ["indexPath" : indexPath, "DS" : self])
		return true
	}

	func collectionView(_ collectionView: UICollectionView, didDeselectItemAt indexPath: IndexPath) {
		log.debug("didDeselectItemAt", ["indexPath" : indexPath, "DS" : self])
	}

	func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, 
			forItemAt indexPath: IndexPath) {
		loaderDelegate?.userIsViewingCell(at: indexPath)
	}

	func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, 
			sizeForItemAt indexPath: IndexPath) -> CGSize {
		guard cellModelSections.count > indexPath.section else { 
			log.error("Datasource was asked sizeForItemAt for bad section #.")
			return CGSize(width:414, height: 50)
		}
		let section = cellModelSections[indexPath.section]
		guard section.cellModels.count > indexPath.row else { 
			log.error("Datasource was asked sizeForItemAt for bad item #.")
			return CGSize(width:414, height: 50)
		}
		let cellModel = section.cellModels[indexPath.row]
		
		// Give the cell model a chance to update its cache
		cellModel.updateCachedCellSize(for: collectionView)

		if cellModel.cellSize.height > 0 {
			return cellModel.cellSize
		}
		else {
			if let protoCell = cellModel.makePrototypeCell(for: collectionView, indexPath: indexPath) {
				let newSize = protoCell.calculateSize()
				cellModel.cellSize = newSize
				log.debug("New size for cell at \(indexPath) is \(newSize)", ["DS" : self])
							
				return newSize
			}
		}

		return CGSize(width:414, height: 50)
	}
	
// MARK: KrakenDataSourceSectionProtocol
	func append(_ cell: BaseCellModel) {
		log.debug("Can't append cells to this data source")
	}

	override func invalidateLayoutCache() {
		cellModelSections.forEach { $0.cellModels.forEach { $0.cellSize = CGSize(width: 0, height: 0) } }
	}
	
	func cellModel(at indexPath: IndexPath) -> BaseCellModel? {
		if indexPath.section >= cellModelSections.count { return nil }
		let section = cellModelSections[indexPath.section]
		if indexPath.row >= section.cellModels.count { return nil }
		return section.cellModels[indexPath.row]
	}
	
	internal func internalRunUpdates(for collectionView: UICollectionView?, deleteOffset: Int, insertOffset: Int) {
		
		log.debug("internalRunUpdates for FRC:", ["deleteSections" : self.deleteSections, "moveSections" : self.moveSections,
				"insertSections" : self.insertSections, "deleteCells" : self.deleteCells, "insertCells" : self.insertCells,
				"reloadCells" : self.reloadCells, "moves" : self.moveCells])

// -- The Part Where We Tell the CollectionView About The Changes

		// Special case for when there's no sections 
		if insertCells.count > 0, cellModelSections.count == 0 {
			insertSections.insert(0)
		}
		
		// Tell the CV about all the changes. Be sure to offset the section indices by our segment start values.
		if deleteSections.count > 0 {
			collectionView?.deleteSections(addOffsetToIndexSet(deleteOffset, deleteSections))
		}
		for (from, to) in moveSections {
			collectionView?.moveSection(from + deleteOffset, toSection: to + insertOffset)
		}
		if deleteCells.count > 0 {
			collectionView?.deleteItems(at: addSectionOffset(deleteOffset, deleteCells))
		}
		for (from, to) in moveCells {
			let newFrom = IndexPath(row: from.row, section: from.section + deleteOffset)
			let newTo = IndexPath(row: to.row, section: to.section + insertOffset)
			collectionView?.moveItem(at: newFrom, to: newTo)
		}
		// Ignore reloads. Our cells are set up to dynamically update and shouldn't need reloading.
//		collectionView?.reloadItems(at: addSectionOffset(deleteOffset, reloadCells))
		if insertSections.count > 0 {
			collectionView?.insertSections(addOffsetToIndexSet(insertOffset, insertSections))
		}
		if insertCells.count > 0 {
			// Filter out any cells being inserted into a section that's being inserted. The CV queries us for how 
			// many cells are in the section after the update is done, and we add cells to our internal list just below.
			insertCells = insertCells.filter { !insertSections.contains($0.section) }
			collectionView?.insertItems(at: addSectionOffset(insertOffset, insertCells))
		}
		
// The Part Where We Update Our Internal Model To Match The Changes

		// Unbind the cells we'll be deleting
		for index in deleteCells {
			if index.section >= cellModelSections.count || index.row >= cellModelSections[index.section].cellModels.count {
				continue
			}
			let elem = cellModelSections[index.section].cellModels[index.row]
			let path = IndexPath(row: index.row, section: index.section + deleteOffset)
			if let cell = collectionView?.cellForItem(at: path) as? BaseCollectionViewCell {
				elem.unbind(cell: cell)
			}
		}
		
		// Decompose moves into deletes and inserts to apply them to cellModels. While doing it, preserve
		// the cells being moved. insertsAndMoves contains nil for actual inserts, or the cell being moved for moves.
		var insertsAndMoves = [(IndexPath, BaseCellModel?)]()
		insertCells.forEach { insertsAndMoves.append(($0, nil)) }
		moveCells.forEach { 
			deleteCells.append($0) 
			let cm = cellModelSections[$0.section].cellModels[$0.row]
			insertsAndMoves.append(($1, cm))
		}
		
		// Decompose section moves into deletes and inserts to apply them to sections.
		var sectionInsertsAndMoves = [(Int, FRCSection?)]()
		insertSections.forEach { sectionInsertsAndMoves.append(($0, nil)) }
		moveSections.forEach { (from, to) in
			deleteSections.insert(from) 
			let sec = cellModelSections[from]
			sectionInsertsAndMoves.append((to, sec))
		}
	
		// Actually remove the cells from our CellModel array, in step with what we tell the CV.
		// Luckily, we can delete all the cells first, and then delete sections.
		for index in deleteCells.sorted().reversed() {
			if index.section >= cellModelSections.count || index.row >= cellModelSections[index.section].cellModels.count {
				continue
			}
			cellModelSections[index.section].cellModels.remove(at: index.row)
		}
		for index in deleteSections.sorted().reversed() {
			cellModelSections.remove(at: index)
		}
		
		// Now add the cells to our CellModel array, in step with what we tell the CV.
		// Again, we should be able to process all the sections first, then the cells.
		if let frcSections = frc?.sections {
			let sortedSectionInsertsAndMoves = sectionInsertsAndMoves.sorted { $0.0 < $1.0 }
			for (sectionIndex, moveSection) in sortedSectionInsertsAndMoves {
				if let section = moveSection {
					cellModelSections.insert(section, at: sectionIndex)
					log.debug("Moved section.", ["FRC" : self, "numCells" : section.cellModels.count, "destination" : sectionIndex])
				}
				else if let frcObjects = frcSections[sectionIndex].objects as? [FetchedObjectType] {
					// Create a new section and populate it with the FRC's objects
					let section = FRCSection(frcSections[sectionIndex].name)
					cellModelSections.insert(section, at: sectionIndex)
					for item in frcObjects {
						if item.objectID.isTemporaryID {
							continue
						}
						if let cellModel = createCellModel?(item) {
							section.cellModels.append(cellModel)
						}
					}
					log.debug("Newly inserted section.", ["FRC" : self, "numCells" : section.cellModels.count, "offsetIndex" : sectionIndex])
				}
				
			}
			
			let sortedInsertsAndMoves = insertsAndMoves.sorted { $0.0 < $1.0 }
			for (insertIndexPath, insertObject) in sortedInsertsAndMoves {
				// If we have an object to insert this is actually a move
				if let movingCellModel = insertObject {
					cellModelSections[insertIndexPath.section].cellModels.insert(movingCellModel, at: insertIndexPath.row)
				}
				else if let frcSection = frcSections[insertIndexPath.section].objects as? [FetchedObjectType],
						let cellModel = createCellModel?(frcSection[insertIndexPath.row]) {
					
					// Not sure if this the best idea; ideally the insert always works. The CV is likely to throw
					// if the count is off and we just append.
					if cellModelSections[insertIndexPath.section].cellModels.count >= insertIndexPath.row {
						cellModelSections[insertIndexPath.section].cellModels.insert(cellModel, at: insertIndexPath.row)
					}
					else {
						cellModelSections[insertIndexPath.section].cellModels.append(cellModel)
					}
				}
			}
		}
		numVisibleSections = numVisibleSections + insertSections.count - deleteSections.count
		log.debug("Inside internalRunUpdates: \(self.numVisibleSections) sections.")

		deleteSections.removeAll()
		insertSections.removeAll()
		moveSections.removeAll()
		deleteCells.removeAll()
		moveCells.removeAll()
		reloadCells.removeAll()
		insertCells.removeAll()

		log.debug("End of internalRunUpdates for FRC:")
	}

}


