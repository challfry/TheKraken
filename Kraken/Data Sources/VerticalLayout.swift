//
//  VerticalLayout.swift
//  Kraken
//
//  Created by Chall Fry on 5/22/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit

struct VerticalLayoutSection {
	var header: CGRect
	var cells: [CGRect]
	var footer: CGRect
	
	init() {
		header = CGRect.zero
		footer = CGRect.zero
		cells = []
	}
}

class VerticalLayout: UICollectionViewLayout {
	// Configuration
	var hasHeaders = false

	// Stored layout data
	private var privateContentSize: CGSize = CGSize(width: 0, height: 0)
	private var sectionPositions: [VerticalLayoutSection] = []
	private var previousSectionPositions: [VerticalLayoutSection] = []
	
			
// MARK: Methods		
	override func prepare() {
		guard let cv = collectionView, let ds = cv.dataSource, let del = cv.delegate else { return }
		
		previousSectionPositions = sectionPositions
		sectionPositions.removeAll()
		let cvWidth = cv.bounds.width
		
		// Iterate through each cell in each section, get the cell's size, and place each cell in a big stack.
		let flowDelegate = del as? UICollectionViewDelegateFlowLayout
		var pixelOffset: CGFloat = 0.0
		let sectionCount = ds.numberOfSections?(in: cv) ?? 1
		for sectionIndex in 0..<sectionCount {
						
			var section = VerticalLayoutSection()
			if let flowDel = del as? UICollectionViewDelegateFlowLayout {
				let headerSize = flowDel.collectionView?(cv, layout: self, referenceSizeForHeaderInSection: sectionIndex) ??
						CGSize.zero
				section.header = CGRect(x: 0, y: pixelOffset, width: headerSize.width, height: headerSize.height)
				pixelOffset += headerSize.height
			}

			let cellCount = ds.collectionView(cv, numberOfItemsInSection: sectionIndex)
			for cellIndex in 0..<cellCount {
				// In more generic code if sizeForItemAt isn't implemented we get the value from other sources.
				let cellSize = flowDelegate?.collectionView?(cv, layout: self, sizeForItemAt: 
						IndexPath(row: cellIndex, section: sectionIndex)) ?? CGSize(width: cvWidth, height: 50)
				section.cells.append(CGRect(x: CGFloat(0.0), y: pixelOffset, width: cvWidth, height: cellSize.height))
				pixelOffset += cellSize.height
			}
			sectionPositions.append(section)
		}
		
		privateContentSize = CGSize(width: cvWidth, height: pixelOffset)
	}
	
	override var collectionViewContentSize: CGSize {
		return privateContentSize
	}

	override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {	
		var result: [UICollectionViewLayoutAttributes] = []
		
		for (sectionIndex, section) in sectionPositions.enumerated() {
			if section.header.size.height > 0 {
				let val = UICollectionViewLayoutAttributes(forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, 
						with: IndexPath(row: 0, section: sectionIndex))
				val.isHidden = false
				val.frame = section.header
				result.append(val)
			}
		
			for (rowIndex, cellPosition) in section.cells.enumerated() {
				if cellPosition.intersects(rect) {
					let val = UICollectionViewLayoutAttributes(forCellWith: IndexPath(row: rowIndex, section: sectionIndex))
					val.isHidden = false
					val.frame = cellPosition
					result.append(val)
				}
			}
		}
		
		return result
	}
	
	override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
		let result = UICollectionViewLayoutAttributes(forCellWith: indexPath)
		
		let cellRect = sectionPositions[indexPath.section].cells[indexPath.row]
		result.frame = cellRect
		result.isHidden = false
		
		return result
	}
	
	override func layoutAttributesForSupplementaryView(ofKind elementKind: String, at indexPath: IndexPath) 
			-> UICollectionViewLayoutAttributes? {
		if indexPath.count < 2 || indexPath.row != 0 {
			return nil
		}
		
		let result = UICollectionViewLayoutAttributes(forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
							with: indexPath)
		let section = sectionPositions[indexPath.section]
		let cellRect = section.header
		result.frame = cellRect
		result.isHidden = cellRect.size.height == 0
		
		return result
	}
	
	// This makes the selection animations work correctly. 
	override func initialLayoutAttributesForAppearingItem(at itemIndexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
		if previousSectionPositions.count > itemIndexPath.section {
			let section = previousSectionPositions[itemIndexPath.section]
			if section.cells.count > itemIndexPath.row {
				let val = UICollectionViewLayoutAttributes(forCellWith: itemIndexPath)
				val.isHidden = false
				val.frame = section.cells[itemIndexPath.row]
				return val
			}
		}
		
		guard sectionPositions.count > itemIndexPath.section else { return nil }
		let section = sectionPositions[itemIndexPath.section]
		guard section.cells.count > itemIndexPath.row else { return nil }
		
		let val = UICollectionViewLayoutAttributes(forCellWith: itemIndexPath)
		val.isHidden = false
		val.frame = section.cells[itemIndexPath.row]
		return val
	}
	
	// This makes the selection animations work correctly. 
	override func initialLayoutAttributesForAppearingSupplementaryElement(ofKind elementKind: String, 
			at elementIndexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
		if elementKind == UICollectionView.elementKindSectionHeader, previousSectionPositions.count > elementIndexPath.section {
			let section = previousSectionPositions[elementIndexPath.section]
			let val = UICollectionViewLayoutAttributes(forSupplementaryViewOfKind:
					UICollectionView.elementKindSectionHeader, with: elementIndexPath)
			val.isHidden = false
			val.frame = section.header
			return val
		}

		guard sectionPositions.count > elementIndexPath.section else { return nil }
		let section = sectionPositions[elementIndexPath.section]
		let val = UICollectionViewLayoutAttributes(forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
				with: IndexPath(row: 0, section: elementIndexPath.section))
		val.isHidden = false
		val.frame = section.header
		return val
	}

	override func finalLayoutAttributesForDisappearingItem(at itemIndexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
		guard sectionPositions.count > itemIndexPath.section else { return nil }
		let section = sectionPositions[itemIndexPath.section]
		guard section.cells.count > itemIndexPath.row else { return nil }
		
		let val = UICollectionViewLayoutAttributes(forCellWith: itemIndexPath)
		val.isHidden = false
		val.frame = section.cells[itemIndexPath.row]
		return val
	}

// MARK: Insert/Delete handling

	var currentUpdateList: [UICollectionViewUpdateItem]?
	override func prepare(forCollectionViewUpdates updateItems: [UICollectionViewUpdateItem]) {
		currentUpdateList = updateItems
	}
	
	override func finalizeCollectionViewUpdates() {
		currentUpdateList = nil
	}

	override func indexPathsToInsertForSupplementaryView(ofKind elementKind: String) -> [IndexPath] {
		var result = [IndexPath]()
		if let updates = currentUpdateList {
			for update in updates {
				if update.updateAction == .insert, update.indexPathAfterUpdate?.count == 1, 
						let section = update.indexPathAfterUpdate?.section  {
					result.append(IndexPath(row: 0, section: section))
				}
			}
		}
		
		return result
	}
	
	override func indexPathsToDeleteForSupplementaryView(ofKind elementKind: String) -> [IndexPath] {
		var result = [IndexPath]()
		if let updates = currentUpdateList {
			for update in updates {
				if update.updateAction == .delete, update.indexPathBeforeUpdate?.count == 1, 
						let section = update.indexPathBeforeUpdate?.section  {
					result.append(IndexPath(row: 0, section: section))
				}
			}
		}
		
		return result
	}
	
//	override func initialLayoutAttributesForAppearingSupplementaryElement(ofKind elementKind: String, 
//			at elementIndexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
//				
//	}
	
//	override func finalLayoutAttributesForDisappearingSupplementaryElement(ofKind elementKind: String, 
//			at elementIndexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
//			
//	}

// MARK: Invalidation

	override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
		if let cv = collectionView, newBounds.size.width != cv.bounds.size.width {
			return true
		}
		return false
	}
	
	override func invalidateLayout() {
		super.invalidateLayout()
	}
	
	override func invalidateLayout(with context: UICollectionViewLayoutInvalidationContext) {
		super.invalidateLayout(with: context)
	}
	
}
