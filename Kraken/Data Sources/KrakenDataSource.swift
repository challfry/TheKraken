//
//  KrakenDataSource.swift
//  Kraken
//
//  Created by Chall Fry on 6/16/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit
import os


@objc protocol KrakenCellBindingProtocol {
	var privateSelected: Bool { get set }
}

// All this lets us make a thing where we have a base class that can define vars, a protocol that defines
// methods subclasses need to implement, and a type that composites the two. Kinda ugly, and it requires that
// subclasses conform to the protocol, but it gets us close to an ABC as cleanly as possible.
protocol KrakenDataSourceSegmentProtocol: UICollectionViewDelegateFlowLayout {
	func internalRunUpdates(for collectionView: UICollectionView?, deleteOffset: Int, insertOffset: Int)
	func cellModel(at indexPath: IndexPath) -> BaseCellModel?
	
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int
	func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath, offsetPath: IndexPath) -> UICollectionViewCell
}

@objc class KrakenDataSourceSegment: NSObject {	
	weak var dataSource: KrakenDataSource? 
	var segmentName: String = ""
	@objc dynamic var numVisibleSections: Int = 0
	var sectionOffset: Int = 0
	
	func pathToLocal(_ global: IndexPath) -> IndexPath {
		return IndexPath(row: global.row, section: global.section - sectionOffset)
	}
	
	func addOffsetToIndexSet(_ offset: Int, _ indexes: IndexSet) -> IndexSet {
		var result = IndexSet()
		for index in indexes { result.insert(index + offset) }
		return result
	}
	
	func addSectionOffset(_ offset: Int, _ paths:[IndexPath]) -> [IndexPath] {
		let result = paths.map { return IndexPath(row:$0.row, section: $0.section + offset) }
		return result
	}
	
	func invalidateLayoutCache() { }
}
typealias KrakenDSS = KrakenDataSourceSegment & KrakenDataSourceSegmentProtocol

class KrakenDataSource: NSObject {

	var enableAnimations = false			// Generally, set to true in viewDidAppear
	weak var collectionView: UICollectionView?
	weak var tableView: UITableView?
	weak var viewController: UIViewController? 			// So that cells can segue/present other VCs.

	// AllSegments can be updated immediately. 
	// visibleSegments and sectionsPerSegment must only be updated inside runUpdates.
	@objc dynamic var allSegments = NSMutableArray() // [KrakenDataSourceSegmentProtocol]()
	var visibleSegments = [KrakenDSS]()

	var registeredCellReuseIDs = Set<String>()
	var log = CollectionViewLog(instanceEnabled: false)
	var buildSupplementaryView: ((UICollectionView, String, IndexPath, BaseCellModel?) -> UICollectionReusableView)?

	override init() {
		super.init()
		
		// Watch for section visibility changes; tell Collection to update
//		allSegments.tell(self, when: "*.numVisibleSections") { observer, observed in
//			observer.runUpdates()
//			self.log.debug("Scheduling runUpdates due to section visibility change.", ["DS" : self])
//		}?.execute()
	}	

	// Sets this DS up at the DS for the given collectionView.
	func register(with cv: UICollectionView, viewController: BaseCollectionViewController?) {
		collectionView = cv
		self.viewController = viewController
		
		// Changing the data source for a CV causes issues if it happens while a batchUpdates animation block
		// it taking place. So, we defer the DS change in that case.
		scheduleBatchUpdateCompletionBlock {
			self.log.debug("Setting new datasource.", ["DS" : self])
			self.privateRunUpdates()				// Clear out any updates just before setting ourselves as the DS
			cv.dataSource = self
			cv.delegate = self

			// It appears (rdar://47325370) that prefetch may not work if estimatedSize is set.
//			cv.prefetchDataSource = self
//			cv.isPrefetchingEnabled = true
			cv.reloadData()
		}
	}
	
	func performKrakenSegue(_ id: GlobalKnownSegue, sender: Any?) {
		if let vc = viewController as? BaseCollectionViewController {
			vc.performKrakenSegue(id, sender: sender)
		}
	}

// MARK: Segments	
	@discardableResult func appendFilteringSegment(named: String) -> FilteringDataSourceSegment {
		let newSegment = FilteringDataSourceSegment()
		newSegment.dataSource = self
		newSegment.segmentName = named
		allSegments.add(newSegment)
		return newSegment
	}

	@discardableResult func append<T: KrakenDataSourceSegment>(segment: T) -> T {
		segment.dataSource = self
		allSegments.add(segment)
		return segment
	}

	// Inserts the given segment into allSegments at the given allSegments index. Remember that this may not match 
	// 
	@discardableResult func insertSegment(_ segment: KrakenDataSourceSegment, at index: Int) -> KrakenDataSourceSegment {
		segment.dataSource = self
		allSegments.insert(segment, at: index)
		return segment
	}
	
	// Returns deleted object; useful for implementing move as delete/inert
	// Index is a SEGMENT index not a SECTION index.
	@discardableResult func deleteSegment(at index: Int) -> KrakenDataSourceSegment? {
		let result = allSegments[index] as? KrakenDataSourceSegment
		allSegments.removeObject(at: index)
		return result
	}
	
	// Don't delete visibleSegments directly; this happens during performUpdates().
	func deleteAllSegments() {
		allSegments.removeAllObjects()
	}
	
	// Gets a segment from the array, by name
	func segment(named: String) -> KrakenDataSourceSegment? {
		for segment in allSegments {
			if let segment = segment as? KrakenDataSourceSegment, segment.segmentName == named {
				return segment
			}
		}
		return nil
	}

	// Returns the cell for a given cell model, iff the cell is currently built by the CV.
	func cell(forModel: BaseCellModel) -> BaseCollectionViewCell? {
		var resultCell: BaseCollectionViewCell?
		collectionView?.visibleCells.forEach { cell in
			if let baseCell = cell as? BaseCollectionViewCell, baseCell.cellModel === forModel {
				resultCell = baseCell
			}
		}
		return resultCell
	}
	
	// Returns a tuple of a segment and the offset within that segment.
	// These values are in terms of 'what the CV currently sees', and may not incorporate recent changes
	// to cells and segments (which get resolved in the next performBatchUpdates).
	private func segmentAndOffset(forSection section: Int) -> (KrakenDSS, Int)? {
		var sectionOffset = 0
		for segment in visibleSegments {
			let nextSectionOffset = sectionOffset + segment.numVisibleSections
			if nextSectionOffset > section {
				let returnValue = (segment, section - sectionOffset)
				return returnValue
			} 
			sectionOffset = nextSectionOffset
		}
		log.error("Couldn't find segment for segmentAndOffset")
		return nil
	}

	private func segmentAndOffset(forIndexPath path: IndexPath) -> (KrakenDSS, IndexPath)? {
		var sectionOffset = 0
		for segment in visibleSegments {
			let nextSectionOffset = sectionOffset + segment.numVisibleSections
			if nextSectionOffset > path.section {
				let returnValue = (segment, IndexPath(row: path.row, section: path.section - sectionOffset))
				return returnValue
			} 
			sectionOffset = nextSectionOffset
		}
		log.error("Couldn't find segment for segmentAndOffset")
		return nil
	}
	
	var selectedCell: BaseCellModel?
	func setCellSelection(cell: BaseCollectionViewCell, newState: Bool) {
		// Only dealing with the single-select case; eventually create an enum with selection types?
		
		// If we're selecting a cell that isn't the current selected cell
		if newState, let currentSelection = selectedCell, currentSelection !== cell.cellModel {
			selectedCell = nil
			currentSelection.privateSelected = false
		}
		
		// If we're deselecting the currently selected cell
		if !newState, let currentSelection = selectedCell, currentSelection === cell.cellModel {
			selectedCell = nil
			currentSelection.privateSelected = false
		}
		
		if newState {
			selectedCell = cell.cellModel
			cell.cellModel?.privateSelected = true
		}
		
//		if let indexPath = collectionView?.indexPath(for: cell) {
//			collectionView?.selectItem(at: indexPath, animated: false, scrollPosition: [])
//		}
	}

// MARK: Updating Content

	var internalInvalidateLayout = false
	func invalidateLayout() {
		internalInvalidateLayout = true
		if let segments = allSegments as? [KrakenDSS] {
			segments.forEach { $0.invalidateLayoutCache() }
		}
		runUpdates()
	}
	
	private var updateScheduled = false
	private var animationsRunning = false
	func runUpdates() {
		guard !updateScheduled else { return }
		updateScheduled = true
		DispatchQueue.main.async {
			self.privateRunUpdates()
		}
	}
	
	fileprivate func privateRunUpdates() {
								
		let updateBlock = {
			// Are we currently the datasource for this collectionview? If not, don't tell the CV about
			// any updates.
			var cv: UICollectionView?
			if self.collectionView?.dataSource === self {
				cv = self.collectionView
			}
			self.log.debug("Start of batch", ["DS" : self, "cv" : cv as Any])
		
			// Update visible sections, create locals for new and old visible sections for diffing
			let allSegments = self.allSegments as! [KrakenDSS]
								
			// Find deleted segments and delete their sections.
			var allSegmentIndex = 0
			var visibleSegmentIndex = 0
			var deleteOffset = 0
			var insertOffset = 0
			var deletedSegmentSections = IndexSet()
			while visibleSegmentIndex < self.visibleSegments.count || allSegmentIndex < allSegments.count {
				if visibleSegmentIndex < self.visibleSegments.count, allSegmentIndex < allSegments.count {
					let visibleSegment = self.visibleSegments[visibleSegmentIndex]
					let allSegment = allSegments[allSegmentIndex]
					if visibleSegment === allSegment {
						let preUpdateSections = visibleSegment.numVisibleSections
						visibleSegment.internalRunUpdates(for: cv, 
								deleteOffset: deleteOffset, insertOffset: insertOffset)
						deleteOffset += preUpdateSections
						insertOffset += visibleSegment.numVisibleSections
						visibleSegmentIndex += 1
						allSegmentIndex += 1
						continue
					}

				} 
				
				// We can't runUpdates on segments that have been deleted; they may not delete their sections
				// as they don't know they've been removed.
				if visibleSegmentIndex < self.visibleSegments.count {
					let visibleSegment = self.visibleSegments[visibleSegmentIndex]
					if !allSegments.contains { $0 === visibleSegment } {
						let nextDeleteOffset = deleteOffset + visibleSegment.numVisibleSections
						deletedSegmentSections.insert(integersIn: deleteOffset..<nextDeleteOffset)
						visibleSegmentIndex += 1
						deleteOffset = nextDeleteOffset
						continue
					}
				}

				if allSegmentIndex < allSegments.count {
					let allSegment = allSegments[allSegmentIndex]
					if !self.visibleSegments.contains { $0 === allSegment } {
						allSegment.internalRunUpdates(for: cv, 
								deleteOffset: deleteOffset, insertOffset: insertOffset)
						allSegmentIndex += 1
						insertOffset += allSegment.numVisibleSections
						continue
					}
					self.log.error("Shouldn't ever get here. Segment Merge algorithm failed?")
				}
			}
			if deletedSegmentSections.count > 0 {
				cv?.deleteSections(deletedSegmentSections)
				self.log.debug("Deleting sections due to segment deletion", ["sections" : deletedSegmentSections])
			}
			
			if self.internalInvalidateLayout {
				self.internalInvalidateLayout = false
				let context = UICollectionViewFlowLayoutInvalidationContext()
				context.invalidateFlowLayoutDelegateMetrics = true
				cv?.collectionViewLayout.invalidateLayout(with: context)
			}
		
			self.visibleSegments = allSegments
			var sectionOffset = 0
			for segment in allSegments {
				segment.sectionOffset = sectionOffset
				sectionOffset += segment.numVisibleSections
			}

			self.log.debug("End of batch", ["DS" : self])
		}
		
		if self.collectionView?.dataSource === self {
			if self.animationsRunning {
				self.updateScheduled = true
				return
			}
		
			var disabledAnimations = false
			if !self.enableAnimations {
				UIView.setAnimationsEnabled(false)
				disabledAnimations = true
			}
			
			self.collectionView?.performBatchUpdates( {
				self.animationsRunning = true
				updateBlock()
				self.updateScheduled = false
			}, completion: { completed in
				self.animationsRunning = false
				self.log.debug("After batch.", ["DS" : self, "blocks" : self.itemsToRunAfterBatchUpdates as Any])
				self.itemsToRunAfterBatchUpdates.forEach { $0() }
				self.itemsToRunAfterBatchUpdates.removeAll()
				if self.updateScheduled {
					self.log.debug("Immediately running a new performUpdates", ["DS" : self])
					self.updateScheduled = false
					self.runUpdates()
				}
			})

			if disabledAnimations {
				UIView.setAnimationsEnabled(true)
			}
		}
		else {
			updateBlock()
			self.updateScheduled = false
		}
		
		// something something TableView
	}
	
	
	func sizeChanged(for cellModel: BaseCellModel) {
		cellModel.cellSize = CGSize(width: 0, height: 0)
		
//		log.debug("scroll pos: \(self.collectionView!.contentOffset.y)")
		let context = UICollectionViewFlowLayoutInvalidationContext()
		context.invalidateFlowLayoutDelegateMetrics = true
		self.collectionView?.collectionViewLayout.invalidateLayout(with: context)
		UIView.animate(withDuration: 0.3) {
			self.collectionView?.layoutIfNeeded()
		}
//		log.debug("scroll pos2: \(self.collectionView!.contentOffset.y)")
	}

	var itemsToRunAfterBatchUpdates: [() -> Void] = []
	func scheduleBatchUpdateCompletionBlock(block: @escaping () -> Void) {
		// If we're not the current datasource for this CV, we must tell the *other* datasource to run the block.
		if let ds = collectionView?.dataSource as? KrakenDataSource {
			ds.itemsToRunAfterBatchUpdates.append(block)
			ds.runUpdates()
			log.debug("Scheduling block to run later, on addr: \(Unmanaged.passUnretained(ds).toOpaque())")
		}
		else {
			block()
		}
	}
	
//	override var debugDescription: String {
//		let mirror = Mirror(reflecting: self)
//		var result = ""
//		withUnsafePointer(to: self) {
//			result += "\(type(of: self)): <\($0))>\n"	
//			for child in mirror.children {
//				if let propName = child.label {
//					result += "    \(propName): \(child.value)\n"
//				}
//			}
//		}
//		return result
//	}
}

// MARK: - CV Datasource
extension KrakenDataSource: UICollectionViewDataSource {
    func numberOfSections(in collectionView: UICollectionView) -> Int {
		let sectionCount = visibleSegments.reduce(0) { $0 + $1.numVisibleSections }
		log.debug("numberOfSections", ["count" : sectionCount, "DS" : self])
    	return sectionCount
    }

	func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
		var returnValue = 0
		if let (segment, offset) = segmentAndOffset(forSection: section) {
			returnValue = segment.collectionView(collectionView, numberOfItemsInSection: offset)
		}
		return returnValue
	}
	
	func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
		log.debug("Asking for cell.", ["DS" : self, "path" : indexPath])
		if let (segment, offsetPath) = segmentAndOffset(forIndexPath: indexPath) {
			let resultCell = segment.collectionView(collectionView, cellForItemAt: indexPath, offsetPath: offsetPath)
			if let cell = resultCell as? BaseCollectionViewCell, let vc = viewController as? BaseCollectionViewController {
				cell.viewController = vc
			}
			
			//
			if resultCell.bounds.size.width > 1000 || resultCell.bounds.size.height > 1000 {
				log.debug("This cell has a very strange size.", ["cell" : resultCell])
			}
			
			return resultCell
		}
		log.error("Couldn't create cell.")
		return UICollectionViewCell()
	}
	
	// Unlike cells, supplementary view types need to be registered directly with the CV. You also need to
	// set up a callback.
	func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, 
			at indexPath: IndexPath) -> UICollectionReusableView {
		log.d("Asking for supplementary view at:", [ "indexPath" : indexPath ])

		if let (segment, offsetPath) = segmentAndOffset(forIndexPath: indexPath) {
			
			// Get the cell model from the segment; it's okay if it comes back nil
			let cellModel = segment.cellModel(at: offsetPath)
			if let result = buildSupplementaryView?(collectionView, kind, indexPath, cellModel) {	
				return result
			}
		}
		
		return UICollectionReusableView()	
	}
	
}

// MARK: CV Datasource Prefetch
extension KrakenDataSource: UICollectionViewDataSourcePrefetching {

	// Not currently used. 
	func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
		log.d("Prefetch at: \(indexPaths)", ["DS" : self])
	}

	func collectionView(_ collectionView: UICollectionView, cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {
		log.d("Cancel Prefetch at: \(indexPaths)", ["DS" : self])
	}
}
	

// MARK: - CV Delegate
extension KrakenDataSource: UICollectionViewDelegate, UICollectionViewDelegateFlowLayout {
	
//	func collectionView(_ collectionView: UICollectionView, didHighlightItemAt indexPath: IndexPath) {
//		let sections = visibleSections as! [KrakenDataSourceSegmentProtocol]
//		let model = sections[indexPath.section].visibleCellModels[indexPath.row]
//		model.cellTapped()
//	}

	func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
		log.debug("shouldSelectItemAt", ["indexPath" : indexPath, "DS" : self])
		return true
	}
	
	func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
		log.debug("didSelectItemAt", ["indexPath" : indexPath, "DS" : self])
	}

	func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, 
			sizeForItemAt indexPath: IndexPath) -> CGSize {
		var protoSize = CGSize(width: 50, height: 50)
		if let (segment, offsetPath) = segmentAndOffset(forIndexPath: indexPath) {
			protoSize = segment.collectionView?(collectionView, 
					layout: collectionView.collectionViewLayout, sizeForItemAt: offsetPath) ??
					CGSize(width: 50, height: 50)
		}								

		//
		if protoSize.width > 1000 || protoSize.height > 1000 {
			log.debug("This cell has a very strange size.", ["indexPath" : indexPath])
		}
			

		return protoSize
	}
	
	func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
		if let (segment, offsetPath) = segmentAndOffset(forIndexPath: indexPath) {
			segment.collectionView?(collectionView, willDisplay: cell, forItemAt: offsetPath)
		}								
	}

}

// MARK: - Debugging extensions
extension KrakenDataSource: UIScrollViewDelegate {

	// Dumps info about cell and CV sizes. Shouldn't be called in the app. To use:
	//			in LLDB: po <datasource>.debugCellHeights()
	func debugCellHeights() {
		guard let cv = collectionView else { return }
		let sectionCount = self.numberOfSections(in: cv)
		var totalHeight: CGFloat = 0.0
		var debugString = ""
		for sectionIndex in  0..<sectionCount {
			let cellCount = self.collectionView(cv, numberOfItemsInSection: sectionIndex)
			var sectionHeight: CGFloat = 0.0
			for cellIndex in 0..<cellCount {
				let indexPath = IndexPath(row: cellIndex, section: sectionIndex)
				let cellSize = self.collectionView(cv, layout:cv.collectionViewLayout, sizeForItemAt: indexPath)
				sectionHeight += cellSize.height
			}
			totalHeight += sectionHeight
			debugString.append("    Section \(sectionIndex): \(cellCount) cells, \(sectionHeight) height.\n")
		}
		log.debug("CV: \(sectionCount) sections, totalHeight: \(totalHeight)\n\(debugString)")
	}
	
//	func scrollViewDidScroll(_ scrollView: UIScrollView) {
//		log.debug("ContentOffset: \(scrollView.contentOffset.y) ContentSize: \(scrollView.contentSize.height)"
//				+ " ViewHeight: \(scrollView.bounds.size.height) MaxOffset: \(scrollView.contentSize.height - scrollView.bounds.size.height)" )
//	}

}
