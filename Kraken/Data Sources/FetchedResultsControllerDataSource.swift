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
		UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout, UICollectionViewDataSourcePrefetching
		where FetchedObjectType : NSFetchRequestResult, CellType : BaseCollectionViewCell {

	var vc: BaseCollectionViewController?
	var frc: NSFetchedResultsController<FetchedObjectType>?
	var collectionView: UICollectionView?	
	var setupCell: ((_ cell: UICollectionViewCell, _ fromModel: FetchedObjectType) -> Void)?
	var reuseID: String?
	
	private var collectionViewUpdateBlocks: [() -> Void] = []
	
	func setup(collectionView: UICollectionView, frc: NSFetchedResultsController<FetchedObjectType>, vc: BaseCollectionViewController?,
			setupCell: ((_ cell: UICollectionViewCell, _ fromModel: FetchedObjectType) -> Void)?, reuseID: String) {
		self.vc = vc
		self.frc = frc
		self.collectionView = collectionView
		self.setupCell = setupCell
		self.reuseID = reuseID		
	}
			
// MARK: FetchedResultsControllerDelegate
	func controllerWillChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
	}

	func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, 
			didChange sectionInfo: NSFetchedResultsSectionInfo, atSectionIndex sectionIndex: Int, for type: NSFetchedResultsChangeType) {
		switch type {
		case .insert:
			collectionViewUpdateBlocks.append { self.collectionView?.insertSections(IndexSet(integer: sectionIndex)) }
		case .delete:
			collectionViewUpdateBlocks.append { self.collectionView?.deleteSections(IndexSet(integer: sectionIndex)) }
		default:
			fatalError()
		}
	}
	
	func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange anObject: Any,
			at indexPath: IndexPath?, for type: NSFetchedResultsChangeType, newIndexPath: IndexPath?) {

		switch type {
		case .insert:
			guard let newIndexPath = newIndexPath else { return }
			collectionViewUpdateBlocks.append( { self.collectionView?.insertItems(at: [newIndexPath]) })
		case .delete:
			guard let indexPath = indexPath else { return }
			collectionViewUpdateBlocks.append( { self.collectionView?.deleteItems(at: [indexPath]) })
		case .move:
			guard let indexPath = indexPath,  let newIndexPath = newIndexPath else { return }
			collectionViewUpdateBlocks.append( { self.collectionView?.moveItem(at: indexPath, to: newIndexPath) })
		case .update:
			guard let indexPath = indexPath else { return }
			collectionViewUpdateBlocks.append( { self.collectionView?.reloadItems(at: [indexPath]) })
		@unknown default:
			fatalError()
		}
	}

	func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
		collectionView?.performBatchUpdates({
			self.collectionViewUpdateBlocks.forEach { $0() }
			self.collectionViewUpdateBlocks.removeAll(keepingCapacity: false)
		}, completion: nil)
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
		if let reuseID = reuseID, let object = frc?.object(at: indexPath) {
			let cell = collectionView.dequeueReusableCell(withReuseIdentifier: reuseID, for: indexPath) 
			if let baseCell = cell as? BaseCollectionViewCell {
				baseCell.collectionViewSize = collectionView.bounds.size
				baseCell.viewController = vc
			}
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
	
		if let reuseID = reuseID, let model = frc?.object(at: indexPath),
				 let protoCell = CellType.makePrototypeCell(for: collectionView, indexPath: indexPath, reuseID: reuseID) {
			setupCell?(protoCell, model)
			let newSize = protoCell.calculateSize()
						
   			return newSize
		}

		return CGSize(width:414, height: 50)
	}
	
}
