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
// and can have knowledge of that that object is. Not for use with generic cells that just get told what text to put where,
// or for cells that have to save state back to their cellModel.
@objc protocol FetchedResultsBindingProtocol : KrakenCellBindingProtocol {
	var model: NSFetchRequestResult? { get set }
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
		model = withModel
		self.reuse = reuse
		super.init(bindingWith: bindingWith)

		self.shouldBeVisible = model != nil
	}
	
	override func reuseID() -> String {
		return reuse
	}
}

// Note: For some reason I couldn't put protocol conformance into extensions, and I didn't bother trying to figure out why.
// Why would I do such a terrible thing? Because you can put the methods in the class and move on. 
class FRCDataSourceSegment<FetchedObjectType>: KrakenDataSourceSegment, KrakenDataSourceSegmentProtocol,
		NSFetchedResultsControllerDelegate, 
		UICollectionViewDataSourcePrefetching where FetchedObjectType : NSManagedObject {
		
	var log = CollectionViewLog(instanceEnabled: false)

	var fetchRequest = NSFetchRequest<FetchedObjectType>()
	var frc: NSFetchedResultsController<FetchedObjectType>?
	var cellModels: [BaseCellModel] = []
	
	// Clients need to implement this to populate the cell's data from the model.
	var createCellModel: ((_ fromModel: FetchedObjectType) -> BaseCellModel)?
		
	override init() {
		fetchRequest.entity = FetchedObjectType.entity()
		fetchRequest.predicate = NSPredicate(value: false)
		fetchRequest.fetchBatchSize = 50
		super.init()
	}
	
	init(withCustomFRC: NSFetchedResultsController<FetchedObjectType>) {
		frc = withCustomFRC
		super.init()
//		frc?.delegate = self
	}
		
	// Configures the Fetch Request, kicks off the FRC, and sets up our cellModels with the initial FRC results.
	// Call this up front, and again whenever the predicate, sort, or factory function need to change.
	func activate(predicate: NSPredicate?, sort: [NSSortDescriptor]?, cellModelFactory: ((_ from: FetchedObjectType) -> BaseCellModel)?) {
		self.createCellModel = cellModelFactory

		if frc == nil {
			if let pred = predicate {
				fetchRequest.predicate = pred 
			}
			if let sortDescriptors = sort {
				fetchRequest.sortDescriptors = sortDescriptors
			}
			frc = NSFetchedResultsController(fetchRequest: fetchRequest, 
						managedObjectContext: LocalCoreData.shared.mainThreadContext, 
						sectionNameKeyPath: nil, cacheName: nil)
			frc?.delegate = self
		
			do {
				try frc?.performFetch()
			}
			catch {
				CoreDataLog.error("Couldn't fetch pending replies.", [ "error" : error ])
			}
		}

		//
		cellModels.removeAll()
		if let objects = frc?.fetchedObjects {
			for fetchedIndex in 0..<objects.count {
				if let cellModel = createCellModel?(objects[fetchedIndex]) {
					cellModels.append(cellModel)
				}
			}
			insertSections.insert(0)
			log.debug("Initial FRC objects:", ["objects" : objects])
		}
		else {
			log.error("No fetched objects during setup.")
		}
		dataSource?.collectionView?.reloadData()
	}
		
// MARK: FetchedResultsControllerDelegate
	var insertSections = IndexSet()
	var deleteSections = IndexSet()
	var insertCells = [IndexPath]()
	var deleteCells = [IndexPath]()
	var moveCells = [(IndexPath, IndexPath)]()			// from, to
	var reloadCells = [IndexPath]()	

	func controllerWillChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
	}
	
	func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, 
			didChange sectionInfo: NSFetchedResultsSectionInfo, atSectionIndex sectionIndex: Int, for type: NSFetchedResultsChangeType) {
		switch type {
		case .insert:
			insertSections.insert(sectionIndex)
		case .delete:
			deleteSections.insert(sectionIndex)
		default:
			fatalError()
		}
	}
	
	func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange anObject: Any,
			at indexPath: IndexPath?, for type: NSFetchedResultsChangeType, newIndexPath: IndexPath?) {
			
		log.debug("In FRC Callback", ["numCells" : self.cellModels.count, "type" : type.rawValue, 
				"indexPath" : indexPath ?? newIndexPath ?? "hmm"])

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
			moveCells.append((indexPath, newIndexPath))
		case .update:
			guard let indexPath = indexPath else { return }
			reloadCells.append(indexPath)
		@unknown default:
			fatalError()
		}
	}

	func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
		dataSource?.runUpdates()
	}

// MARK: UICollectionView Data Source
    func numberOfSections(in collectionView: UICollectionView) -> Int {
    	// TODO: This is wrong, and should be based on cellModels (frc changes immediately, cellModel changes
    	// defer until batchUpdates, this fn needs to return what the CV sees.)
    	return frc?.sections?.count ?? 0
    }

	func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
//		guard let sections =  frc?.sections else {
//			fatalError("No sections in fetchedResultsController")
//		}
		log.debug("numberOfItemsInSection", ["numObjects" : self.cellModels.count, "DS" : self])
		return cellModels.count
	}
	
	func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
		log.d("Asking for cell at indexpath", [ "cellModels" : self.cellModels.count, "indexPath" : indexPath ])
		if indexPath.row < cellModels.count {
			let cellModel = cellModels[indexPath.row]
			let reuseID = cellModel.reuseID()
			if dataSource?.registeredCellReuseIDs.contains(reuseID) == false {
				dataSource?.registeredCellReuseIDs.insert(reuseID)
				let classType = type(of: cellModel).validReuseIDDict[reuseID]
				classType?.registerCells(with: collectionView)
			}
			let cell = cellModel.makeCell(for: collectionView, indexPath: indexPath)
			return cell
		}
		else {
			log.error("Datasource doesn't have a built cellModel for requested indexPath.")
		}
				
		return UICollectionViewCell()
	}

// MARK: UICollectionView Data Source Prefetch

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

	func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, 
			sizeForItemAt indexPath: IndexPath) -> CGSize {
		if indexPath.row >= cellModels.count {
			return CGSize(width:414, height: 50)
		}
		let cellModel = cellModels[indexPath.row]

		if cellModel.cellSize.height > 0 {
			return cellModel.cellSize
		}
		else {
			if let protoCell = cellModel.makePrototypeCell(for: collectionView, indexPath: indexPath) {
				let newSize = protoCell.calculateSize()
				cellModel.cellSize = newSize
				cellModel.unbind(cell: protoCell)
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

	
	internal func internalRunUpdates(for collectionView: UICollectionView?, deleteOffset: Int, insertOffset: Int) {
		
		log.debug("internalRunUpdates for FRC:", ["deleteSections" : self.deleteSections,
				"insertSections" : self.insertSections, "deleteCells" : self.deleteCells, "insertCells" : self.insertCells,
				"reloadCells" : self.reloadCells, "moves" : self.moveCells])
		
		if deleteSections.count > 0 {
			collectionView?.deleteSections(addOffsetToIndexSet(deleteOffset, deleteSections))
		}
		if deleteCells.count > 0 {
			collectionView?.deleteItems(at: addSectionOffset(deleteOffset, deleteCells))
		}
		
		// Actually remove the cells from our CellModel array, in step with what we tell the CV.
		for index in deleteCells.sorted().reversed() {
			cellModels.remove(at: index.row)
		}
		
		for (from, to) in moveCells {
			let newFrom = IndexPath(row: from.row, section: from.section + deleteOffset)
			let newTo = IndexPath(row: to.row, section: to.section + insertOffset)
			collectionView?.moveItem(at: newFrom, to: newTo)
		}
		collectionView?.reloadItems(at: addSectionOffset(deleteOffset, reloadCells))
		collectionView?.insertSections(addOffsetToIndexSet(insertOffset, insertSections))
		collectionView?.insertItems(at: addSectionOffset(insertOffset, insertCells))
	
		// Now add the cells from our CellModel array, in step with what we tell the CV.
		
		if let objects = frc?.fetchedObjects {
			for index in insertCells.sorted() {
				if let cellModel = createCellModel?(objects[index.row]) {
					cellModels.insert(cellModel, at: index.row)
				}
			}
		}
		numVisibleSections = numVisibleSections + insertSections.count - deleteSections.count

		deleteSections.removeAll()
		insertSections.removeAll()
		deleteCells.removeAll()
		moveCells.removeAll()
		reloadCells.removeAll()
		insertCells.removeAll()

		log.debug("End of internalRunUpdates for FRC:", ["cells" : self.cellModels])
	}

}


