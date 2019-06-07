//
//  FetchedResultsControllerDataSource.swift
//  Kraken
//
//  Created by Chall Fry on 5/13/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit
import CoreData

// A simple cell model and binding protocol. Useful for when your cell can set itself up from data in the model object
// and can have knowledge of that that object is. Not for use with generic cells that just get told what text to put where,
// or for cells that have to save state back to their cellModel.
@objc protocol FetchedResultsBindingProtocol {
	var model: NSFetchRequestResult? { get set }
}

class FetchedResultsCellModel : BaseCellModel, FetchedResultsBindingProtocol {
	@objc dynamic var model: NSFetchRequestResult?
	var reuse: String
	
	init(withModel: NSFetchRequestResult, reuse: String) {
		model = withModel
		self.reuse = reuse
		super.init(bindingWith: FetchedResultsBindingProtocol.self)
	}
	
	override func reuseID() -> String {
		return reuse
	}
}

// Note: For some reason I couldn't put protocol conformance into extensions, and I didn't bother trying to figure out why.
// Why would I do such a terrible thing? Because you can put the methods in the class and move on. 
class FetchedResultsControllerDataSource<FetchedObjectType>: NSObject, NSFetchedResultsControllerDelegate, 
		UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout, UICollectionViewDataSourcePrefetching,
		FilteringDataSourceSectionProtocol, KrakenDataSourceProtocol
		where FetchedObjectType : NSFetchRequestResult {

	var frc: NSFetchedResultsController<FetchedObjectType>?
	var collectionView: UICollectionView?
	var cellModels: [BaseCellModel] = []
	var enableAnimations = false			// Generally, set to true in viewDidAppear
	
	// Clients need to implement this to populate the cell's data from the model.
	var createCellModel: ((_ fromModel: FetchedObjectType) -> BaseCellModel)?
	
	// Clients of this class can set the reuseID of the cells this DS produces. Use this in the case where all the cells
	// are the same. Or, clients can provide a closure to set a reuse type per cell. The models in a FRC are still all
	// the same type, but if some of the cells should look different, use this.
	var reuseID: String?
	var overrideReuseID: ((_ usingModel: FetchedObjectType) -> String?)?
		
	func setup(collectionView: UICollectionView, frc: NSFetchedResultsController<FetchedObjectType>,
			createCellModel: ((_ from: FetchedObjectType) -> BaseCellModel)?, reuseID: String) {
		self.frc = frc
		self.collectionView = collectionView
		self.createCellModel = createCellModel
		self.reuseID = reuseID
		
		//
		if let objects = frc.fetchedObjects {
			for fetchedIndex in 0..<objects.count {
				if let cellModel = createCellModel?(objects[fetchedIndex]) {
					cellModels.append(cellModel)
				}
			}
		}
	}
	
	private var internalInvalidateLayout = false
	func invalidateLayout() {
		internalInvalidateLayout = true
		if let cv = collectionView {
			runUpdates(for: cv, sectionOffset: 0)
		} 
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
		if let cv = collectionView {
			runUpdates(for: cv, sectionOffset: 0)
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
		if indexPath.row < cellModels.count {
			let cellModel = cellModels[indexPath.row]
			let cell = cellModel.makeCell(for: collectionView, indexPath: indexPath)
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
		if indexPath.row >= cellModels.count {
			return CGSize(width:414, height: 50)
		}
		let cellModel = cellModels[indexPath.row]

		//
		if indexPath.row == 0 {
			print("Current Size: \(cellModel.cellSize)")
		}	
		
		if cellModel.cellSize.height > 0 {
			return cellModel.cellSize
		}
		else {
			if let protoCell = cellModel.makePrototypeCell(for: collectionView, indexPath: indexPath) {
				let newSize = protoCell.calculateSize()
				cellModel.cellSize = newSize
				cellModel.unbind(cell: protoCell)
				print ("New size for cell at \(indexPath) is \(newSize)")
							
		if indexPath.row == 0 {
			print("New Size: \(cellModel.cellSize)")
		}	
		
				return newSize
			}
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

	// Always called from within a performBatchUpdates
	private var updateScheduled = false
	func runUpdates(for collectionView: UICollectionView?, sectionOffset: Int) {
		if let ds = dataSource {
			// If we're not top-level, tell upstream that updates need to be run. Remember, performBatchUpdates
			// must update everything -- when it's done, every section's cell count must add up.
			ds.runUpdates()
		}
		else {
			guard !updateScheduled else { return }	
			DispatchQueue.main.async {
				self.updateScheduled = false
				if let cv = self.collectionView {
					if !self.enableAnimations {
						UIView.setAnimationsEnabled(false)
					}
					cv.performBatchUpdates( {
						self.internalRunUpdates(for: collectionView, sectionOffset: sectionOffset)
					}, completion: nil)
					if !self.enableAnimations {
						UIView.setAnimationsEnabled(true)
					}
				}
			}
		}
	}
	
	internal func internalRunUpdates(for collectionView: UICollectionView?, sectionOffset: Int) {
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
		
		if internalInvalidateLayout {
			internalInvalidateLayout = false
			let context = UICollectionViewFlowLayoutInvalidationContext()
			context.invalidateFlowLayoutDelegateMetrics = true
			collectionView?.collectionViewLayout.invalidateLayout(with: context)
		}
	}

}


