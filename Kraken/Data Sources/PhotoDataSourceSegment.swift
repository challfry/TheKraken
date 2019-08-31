//
//  PhotoDataSourceSegment.swift
//  Kraken
//
//  Created by Chall Fry on 7/31/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit
import Photos

@objc protocol PhotoCollectionCellProtocol {
	var asset: PHAsset? { get set }
	var buttonHit: ((PhotoCollectionCellProtocol) -> Void)? { get set }
}

class PhotoDataSourceSegment: KrakenDataSourceSegment {

	var allPhotos: PHFetchResult<PHAsset>?
	var cellClass: BaseCollectionViewCell.Type?
	var reuseID: String?
	var buttonHitClosure: ((PhotoCollectionCellProtocol) -> Void)?

	var photoLibChangeObject: PHChange?
	var insertSections = IndexSet()
	var deleteSections = IndexSet()
	
		// Will be nil if no photo selected
	var selectedPhotoIndex: Int?

// MARK: Methods
	func activate(predicate: NSPredicate?, sort: [NSSortDescriptor]?, cellClass: BaseCollectionViewCell.Type,
			reuseID: String) {
		self.cellClass = cellClass
		self.reuseID = reuseID
		
		let allPhotosOptions = PHFetchOptions()
		allPhotosOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
		allPhotosOptions.includeAssetSourceTypes = [.typeUserLibrary, .typeCloudShared, .typeiTunesSynced] 
		allPhotos = PHAsset.fetchAssets(with: .image, options: allPhotosOptions)
		insertSections.insert(0)
		dataSource?.runUpdates()
	}
	
}

// MARK: - PHPhotoLibraryChangeObserver
extension PhotoDataSourceSegment: PHPhotoLibraryChangeObserver {

	func photoLibraryDidChange(_ changeInstance: PHChange) {
		DispatchQueue.main.async {
			if let allPhotos = self.allPhotos, let changes = changeInstance.changeDetails(for: allPhotos) {
				if changes.hasIncrementalChanges {
					self.photoLibChangeObject = changeInstance
					self.dataSource?.runUpdates()
				} else {
					// Reload the collection view if incremental diffs are not available.
					self.dataSource?.collectionView?.reloadData()
					self.allPhotos = changes.fetchResultAfterChanges
				}
			}
		}
	}
}

// MARK: - KrakenDataSourceSegmentProtocol
extension PhotoDataSourceSegment: KrakenDataSourceSegmentProtocol {
    func numberOfSections(in collectionView: UICollectionView) -> Int {
    	return numVisibleSections
    }

	func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
		return allPhotos?.count ?? 0
	}
	
	// The photo DSS doesn't use cellModels; the underlying model data is PHAsset objects. Just returning nil is okay.
	func cellModel(at indexPath: IndexPath) -> BaseCellModel? {
	//	let model = allPhotos?.object(at: indexPath.row)
		return nil
	}
	
	func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath, offsetPath: IndexPath) -> UICollectionViewCell {
		guard let reuse = reuseID else { return UICollectionViewCell() }
		if dataSource?.registeredCellReuseIDs.contains(reuse) == false {
			dataSource?.registeredCellReuseIDs.insert(reuse)
			cellClass?.registerCells(with: collectionView)
		}

		let cell = collectionView.dequeueReusableCell(withReuseIdentifier: reuse, for: indexPath) 
			as! PhotoCollectionCellProtocol & UICollectionViewCell
		cell.asset = allPhotos?.object(at: offsetPath.row)
		cell.buttonHit = buttonHitClosure				
		return cell
	}


	func internalRunUpdates(for cv: UICollectionView?, deleteOffset: Int, insertOffset: Int) {
	
		cv?.deleteSections(addOffsetToIndexSet(deleteOffset, deleteSections))
		cv?.insertSections(addOffsetToIndexSet(insertOffset, insertSections))
		numVisibleSections = numVisibleSections + insertSections.count - deleteSections.count
		deleteSections.removeAll()
		insertSections.removeAll()
	
		if let allPhotos = self.allPhotos, let changes = photoLibChangeObject?.changeDetails(for: allPhotos) {
			if changes.hasIncrementalChanges {
				// For indexes to make sense, updates must be in this order:
				// delete, insert, reload, move
				if let removed = changes.removedIndexes, removed.count > 0 {
					cv?.deleteItems(at: removed.map { IndexPath(item: $0, section:deleteOffset) })
				}
				if let inserted = changes.insertedIndexes, inserted.count > 0 {
					cv?.insertItems(at: inserted.map { IndexPath(item: $0, section:insertOffset) })
				}
//				if let changed = changes.changedIndexes, changed.count > 0 {
//					cv.reloadItems(at: changed.map { IndexPath(item: $0, section:insertOffset) })
//				}
				changes.enumerateMoves { fromIndex, toIndex in
					cv?.moveItem(at: IndexPath(item: fromIndex, section: deleteOffset),
											to: IndexPath(item: toIndex, section: insertOffset))
				}
				self.allPhotos = changes.fetchResultAfterChanges
			} 
		}
	}
}
