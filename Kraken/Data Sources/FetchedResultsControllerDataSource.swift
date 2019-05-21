//
//  FetchedResultsControllerDataSource.swift
//  Kraken
//
//  Created by Chall Fry on 5/13/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit
import CoreData

class FetchedResultsControllerDataSource<FetchedObjectType, CellType>: NSObject, NSFetchedResultsControllerDelegate, 
		UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout, UICollectionViewDataSourcePrefetching,
		FilteringDataSourceSectionProtocol
		where FetchedObjectType : NSFetchRequestResult, CellType : BaseCollectionViewCell {

	var frc: NSFetchedResultsController<FetchedObjectType>?
	var collectionView: UICollectionView?	
	var setupCell: ((_ cell: CellType, _ fromModel: FetchedObjectType) -> Void)?
	var overrideReuseID: ((_ usingModel: FetchedObjectType) -> String?)?
	var reuseID: String?
	
	
	private var collectionViewUpdateBlocks: [() -> Void] = []
	
	func setup(collectionView: UICollectionView, frc: NSFetchedResultsController<FetchedObjectType>,
			setupCell: ((_ cell: CellType, _ fromModel: FetchedObjectType) -> Void)?, reuseID: String) {
		self.frc = frc
		self.collectionView = collectionView
		self.setupCell = setupCell
		self.reuseID = reuseID
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

		switch type {
		case .insert:
			guard let newIndexPath = newIndexPath else { return }
			insertCells.append(newIndexPath)
		case .delete:
			guard let indexPath = indexPath else { return }
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
		if let ds = dataSource {
			// If we're not top-level, tell upstream that updates need to be run. Remember, performBatchUpdates
			// must update everything -- when it's done, every section's cell count must add up.
			ds.runUpdates()
		}
		else if let cv = collectionView {
			// If we're the top-level, performBatchUpdates ourselves
			cv.performBatchUpdates({
				self.runUpdates(for: cv, sectionOffset: 0)
				self.collectionViewUpdateBlocks.removeAll(keepingCapacity: false)
			}, completion: nil)
		} 
	}

// MARK: UICollectionView Data Source
    func numberOfSections(in collectionView: UICollectionView) -> Int {
    	return frc?.sections?.count ?? 0
    }

	func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
		guard let sections =  frc?.sections else {
			fatalError("No sections in fetchedResultsController")
		}
		let sectionInfo = sections[section]
		return sectionInfo.numberOfObjects
	}
	
	func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
		if let object = frc?.object(at: indexPath), let reuseID = overrideReuseID?(object) ?? self.reuseID {
			let cell = collectionView.dequeueReusableCell(withReuseIdentifier: reuseID, for: indexPath) as! CellType
			cell.collectionViewSize = collectionView.bounds.size
			setupCell?(cell, object)
			return cell
		}
		
		return UICollectionViewCell()
	}

// MARK: UICollectionView Data Source Prefetch

	func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
		print ("Prefetch at: \(indexPaths)")
	}

	func collectionView(_ collectionView: UICollectionView, cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {
		print ("Cancel \(indexPaths)")
	}
		
// MARK: UICollectionView Delegate

	func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
		print (indexPath)
		return true
	}
	
	func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
		print (indexPath)
	}

	func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, 
			sizeForItemAt indexPath: IndexPath) -> CGSize {
		if let model = frc?.object(at: indexPath), let reuseID = overrideReuseID?(model) ?? self.reuseID,
				let protoCell = CellType.makePrototypeCell(for: collectionView, indexPath: indexPath, reuseID: reuseID) as? CellType {
			setupCell?(protoCell, model)
			let newSize = protoCell.calculateSize()
						
   			return newSize
		}

		return CGSize(width:414, height: 50)
	}
	
// MARK: FilteringDataSourceSectionProtocol
	var dataSource: FilteringDataSource?
	var sectionName: String = ""
	@objc dynamic var sectionVisible = true

	func append(_ cell: BaseCellModel) {
		print("Can't append cells to this data source")
	}

	func runUpdates(for collectionView: UICollectionView?, sectionOffset: Int) {

		func addOffsetToIndexSet(_ indexes: IndexSet) -> IndexSet {
			var result = IndexSet()
			for index in indexes { result.insert(index + sectionOffset) }
			return result
		}
		func addSectionOffset(_ paths:[IndexPath]) -> [IndexPath] {
			let result = paths.map { return IndexPath(row:$0.row, section: $0.section + sectionOffset) }
			return result
		}

		collectionView?.deleteSections(addOffsetToIndexSet(deleteSections))
		collectionView?.deleteItems(at: addSectionOffset(deleteCells))
		for (from, to) in moveCells {
			let newFrom = IndexPath(row: from.row, section: from.section + sectionOffset)
			let newTo = IndexPath(row: to.row, section: to.section + sectionOffset)
			collectionView?.moveItem(at: newFrom, to: newTo)
		}
		collectionView?.reloadItems(at: addSectionOffset(reloadCells))
		collectionView?.insertSections(addOffsetToIndexSet(insertSections))
		collectionView?.insertItems(at: addSectionOffset(insertCells))
	
		deleteSections.removeAll()
		insertSections.removeAll()
		deleteCells.removeAll()
		moveCells.removeAll()
		reloadCells.removeAll()
		insertCells.removeAll()
	}

}
