//
//  BaseCollectionViewCell.swift
//  Kraken
//
//  Created by Chall Fry on 4/16/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit


// Usually, cellModel:Cell:reuseID are 1:1:1. Multiple reuseIDs for a single cell class can work--make reuseID()
// return different values for different model data. Multiple models launching the same cell class works, and 
// a single cellModel could spin up different cell classes depending on model values, but you'd need to override makeCell.
// However, each reuseID must map to exactly one cell class (no subclasses), and for sanity's sake we're also making reuseIDs 1:1 with xib
// files for xib-based cells.
@objc class BaseCellModel: NSObject {
	class var validReuseIDDict: [String: BaseCollectionViewCell.Type] { return [:] }
	
	var bindingProtocol: Protocol?
	var observations = [EBNObservation]()
	@objc dynamic var shouldBeVisible = true
	@objc dynamic var privateSelected = false
	@objc dynamic var cellSize = CGSize(width: 0, height: 0)
	
	// Cells built from this model can use this to store their state data. State data includes stuff like text entered in text fields.
	// The dict is indexed by reuseID.
//	var cellStateStorage: [String : Any] = [:]

	// Setting this string to a non-nil value makes the Data Source code spit out more logging data about
	// this cell. Useful when you're trying to narrow down an issue that affects this cell specifically.
	var debugLogEnabler: String?
	
	init(bindingWith: Protocol?) {
		bindingProtocol = bindingWith
	}
	
	func reuseID(traits: UITraitCollection) -> String { return type(of: self).validReuseIDDict.first?.key ?? "" }

	func makeCell(for collectionView: UICollectionView, indexPath: IndexPath) -> BaseCollectionViewCell {
		if let str = debugLogEnabler {
			print("About to create cell: \(str) at indexpath: \(indexPath)")
		}

		let id = reuseID(traits: collectionView.traitCollection)
		// Get a cell and property bind it to the cell model
		let cell = collectionView.dequeueReusableCell(withReuseIdentifier: id, for: indexPath) as! BaseCollectionViewCell 
		CollectionViewLog.assert(cell.reuseIdentifier != nil, "Just dequeued a cell that has no reuseID.")
	
		cell.isBuildingCell = true
		cell.collectionViewSizeChanged(to: collectionView.bounds.size)	
		cell.dataSource = collectionView.dataSource as? KrakenDataSource
		cell.cellModel = self
		if let prot = self.bindingProtocol {
			cell.bind(to:self, with: prot)
		}
		cell.isBuildingCell = false
		return cell
	}
	
	// Makes a prototype cell, binds the cell to the cellModel. By overriding reuseID, subclasses can
	// have a single model that spawns different cell classes.
	func makePrototypeCell(for collectionView: UICollectionView, indexPath: IndexPath) -> BaseCollectionViewCell? {
		let id = reuseID(traits: collectionView.traitCollection)
		
		if let classType = type(of: self).validReuseIDDict[id], let cellInfo = classType.validReuseIDDict[id],
				let cell = cellInfo.prototypeCell {

			cell.isBuildingCell = true
			cell.collectionViewSizeChanged(to: collectionView.bounds.size)	
			cell.dataSource = collectionView.dataSource as? KrakenDataSource
			cell.cellModel = self
			if let prot = self.bindingProtocol {
				cell.copyProperties(from: self, in: prot)
			}
			cell.isBuildingCell = false
			
			if let selection = collectionView.indexPathsForSelectedItems, selection.contains(indexPath) {
				cell.isSelected = true
			}
			else {
				cell.isSelected = false
			}
			return cell
		}
		return nil
	}
	
	func updateCachedCellSize(for collectionView: UICollectionView) {
		// Do nothing by default
	}

	func cellTapped(dataSource: KrakenDataSource?, vc: UIViewController?) {
		// Do nothing by default
		
	}
	
	func addObservation(_ observation: EBNObservation?) {
		guard let obs = observation else { return }
		
		observations.append(obs)
	}
	
	func clearObservations() {
		observations.forEach { $0.stopObservations() } 
	}
	
	func unbind(cell: BaseCollectionViewCell) {
		if let prot = self.bindingProtocol {
			cell.unbind(self, from: prot)
			cell.clearObservations()
		}
		cell.cellModel = nil
		cell.dataSource = nil
	}
}

struct PrototypeCellInfo {
	var nib: UINib? = nil
	var cellClass: BaseCollectionViewCell.Type?
	var prototypeCell: BaseCollectionViewCell? = nil
	
	init(_ nibName: String?) {
		if let nibName = nibName {
			nib = UINib(nibName: nibName, bundle: nil)
			if let nibContents = nib?.instantiate(withOwner: nil, options: nil) {
				prototypeCell = (nibContents[0] as! BaseCollectionViewCell)
				prototypeCell?.isPrototypeCell = true
//				prototypeCell?.translatesAutoresizingMaskIntoConstraints = false
			}
		}
	}
	
	init(_ cellClass: BaseCollectionViewCell.Type) {
		self.cellClass = cellClass
		prototypeCell = cellClass.init(frame: CGRect(x: 0, y: 0, width: 414, height: 200))
		prototypeCell?.isPrototypeCell = true
	}
}

@objc class BaseCollectionViewCell: UICollectionViewCell {
	class var validReuseIDDict: [String : PrototypeCellInfo ] { return [:] }
	class func registerCells(with controller: UICollectionView) {
		for (reuseID, info) in self.validReuseIDDict {
			if let nib = info.nib {
				controller.register(nib, forCellWithReuseIdentifier: reuseID)
			}
			else {
				controller.register(info.cellClass, forCellWithReuseIdentifier: reuseID)
			}
		}
	}

	var cellModel: BaseCellModel? 							// Not all datasources use cell models
	weak var dataSource: KrakenDataSource?						
	@objc dynamic weak var viewController: UIViewController?  // For launching segues

	var observations = Set<EBNObservation>()
	var isPrototypeCell: Bool = false
	var calculatedSize: CGSize = CGSize(width: 0.0, height: 0.0)
	var isBuildingCell = false
	var customGR: UILongPressGestureRecognizer?
	var allowsHighlight: Bool = true
	var allowsSelection: Bool = false
	
// MARK: Methods
	required override init(frame: CGRect) {
		super.init(frame: frame)
//		self.translatesAutoresizingMaskIntoConstraints = false
//		contentView.translatesAutoresizingMaskIntoConstraints = false
	}
	
	required init?(coder aDecoder: NSCoder) {
		super.init(coder: aDecoder)
//		self.translatesAutoresizingMaskIntoConstraints = false
//		contentView.translatesAutoresizingMaskIntoConstraints = false
	}
	
	override func awakeFromNib() {
		super.awakeFromNib()
//		self.translatesAutoresizingMaskIntoConstraints = false
//		contentView.translatesAutoresizingMaskIntoConstraints = false
	}
	
	override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
		super.traitCollectionDidChange(previousTraitCollection)
		cellSizeChanged()
	}
	
	// Called on cell creation and then whenever the cv size changes.
	var fullWidth: Bool = true
	var fullWidthConstraint: NSLayoutConstraint?
		
	func collectionViewSizeChanged(to newSize: CGSize) {
		// Subclasses can set fullWidth in awakeFromNib; this then sets cell width to cv width
		if fullWidth {
		
			// We sometimes get called to set up our cells when the CollectionView still has a {0, 0} size.
			// Returning 0 width cells in this case causes immediate problems, but it appears that the cells are re-fetched
			// once the CV sizes itself. So, hard-coding 414 *should* be okay here? It won't make other-sized devices look bad?
			var width = newSize.width
			if newSize.width == 0 {
				width = 414
			}
		
			if let constraint = fullWidthConstraint {
				if constraint.constant != width {
					constraint.constant = width
				}
			}
			else {
				fullWidthConstraint = contentView.widthAnchor.constraint(equalToConstant: width)
				fullWidthConstraint?.priority = UILayoutPriority(rawValue: 900)
			}
		}
		fullWidthConstraint?.isActive = fullWidth
	}
	
	
	// Initiates a change in selection state. Only cells can do this, not models. But, state is saved in the model.
	// If the model doesn't pass this var back to the cell, no selection will be visible.
	@objc dynamic var privateSelected: Bool = false 
	func privateSelectCell(_ newState: Bool = true) {
		if let model = cellModel {
			if let ds = self.dataSource {
				ds.setCellSelection(cell: self, newState: newState)
			}
			else {
				model.privateSelected = true
			}
		}
	}
	
	// Subclasses can call from inside privateSelected to get 'standard' selection behavior.
	func standardSelectionHandler() {
		if let oldAnim = highlightAnimation {
			oldAnim.stopAnimation(true)
		}
		if privateSelected || isHighlighted {
			self.contentView.backgroundColor = UIColor(named: "Cell Background Selected")
		}
		else {
			if isPrototypeCell {
				self.contentView.backgroundColor = UIColor(named: "Cell Background")
			}
			else {
				let anim = UIViewPropertyAnimator(duration: 0.3, curve: .easeInOut) {
					self.contentView.backgroundColor = UIColor(named: "Cell Background")
				}
				anim.addCompletion {_ in self.highlightAnimation = nil }
				anim.isUserInteractionEnabled = true
				anim.isInterruptible = true
				anim.startAnimation()
				highlightAnimation = anim
			}
		}
	}
	
	// Subclasses can call this from inside isHighlighted to get stand highlight behavior.
	var highlightAnimation: UIViewPropertyAnimator?
	func standardHighlightHandler() {
		if isPrototypeCell { return }
		if let oldAnim = highlightAnimation {
			oldAnim.stopAnimation(true)
		}
		let anim = UIViewPropertyAnimator(duration: 0.3, curve: .easeInOut) {
			self.contentView.backgroundColor = self.isHighlighted ? UIColor(named: "Cell Background Selected") : 
					UIColor(named: "Cell Background")
		}
		anim.addCompletion {_ in self.highlightAnimation = nil }
		anim.isUserInteractionEnabled = true
		anim.isInterruptible = true
		anim.startAnimation()
		highlightAnimation = anim
	}
	
	func cellSizeChanged() {
		setNeedsLayout()
		if !isPrototypeCell, !isBuildingCell {
			dataSource?.sizeChanged(for: self)
		}	
	}

	// Returns a prototype cell that this class can manage. Doesn't set up that cell's data. Subclasses can define
	// multiple reuseIDs which will load different nibs/layouts.
	class func makePrototypeCell(for collectionView: UICollectionView, indexPath: IndexPath, reuseID: String) -> BaseCollectionViewCell? {		
		if let cellInfo = validReuseIDDict[reuseID], let cell = cellInfo.prototypeCell {
			if let dataSource = collectionView.dataSource as? KrakenDataSource {
				cell.dataSource = dataSource
			}
			if let selection = collectionView.indexPathsForSelectedItems, selection.contains(indexPath) {
				cell.isSelected = true
			}
			else {
				cell.isSelected = false
			}
			return cell
		}
		return nil
	}
	
	class func makePrototypeCell(reuseID: String) -> BaseCollectionViewCell? {		
		if let cellInfo = validReuseIDDict[reuseID], let cell = cellInfo.prototypeCell {
			return cell
		}
		return nil
	}
	
	func animateIfNotPrototype(withDuration: TimeInterval, block: @escaping () -> Void) {
		if self.isPrototypeCell {
			block()
		}
		else {
			UIView.animate(withDuration: withDuration, animations: block)
		}
	}
	
	func calculateSize() -> CGSize {
//		setNeedsLayout()
//		layoutIfNeeded()

		if let cvSize = dataSource?.collectionView?.bounds.size, fullWidth {
			let idealSize = CGSize(width: cvSize.width, height: 0)
			let size = contentView.systemLayoutSizeFitting(idealSize, 
					withHorizontalFittingPriority: .required, 
					verticalFittingPriority: .fittingSizeLevel)
			calculatedSize = size
			return size
		}
		let size = contentView.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
		calculatedSize = size
		return size
	}
	
	override func prepareForReuse() {
		isBuildingCell = true
		super.prepareForReuse()
		cellModel?.unbind(cell: self)
		isBuildingCell = false
	}
	
	func addObservation(_ observation: EBNObservation?) {
		guard let obs = observation else { return }
		
		observations.insert(obs)
	}
	
	func removeObservation(_ observation: EBNObservation?) {
		guard let obs = observation else { return }
		obs.stopObservations()
		observations.remove(obs)
	}
	
	func clearObservations() {
		observations.forEach { $0.stopObservations() } 
		observations.removeAll()
	}
	
	
	var isTakingTouchEvent = false
	var touchStartLoc: CGPoint?
	override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
		if allowsHighlight {
			isTakingTouchEvent = true
			isHighlighted = true
			touchStartLoc = touches.first?.location(in: self)
			return
		}
		super.touchesBegan(touches, with: event)
	}

	override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
		if isTakingTouchEvent {
//			if let start = touchStartLoc, let current = touches.first?.location(in: self),
//					abs(current.y - start.y) > 10.0 || abs(current.x - start.x) > 10.0
			if let current = touches.first?.location(in: self) {
				isHighlighted = self.point(inside: current, with: nil)
			}
			return
		}
		super.touchesMoved(touches, with: event)
	}

	override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
		if isTakingTouchEvent {
			if isHighlighted {
				cellModel?.cellTapped(dataSource: dataSource, vc: viewController)
				if allowsSelection {
					privateSelectCell(!privateSelected)
				}
			}
			isHighlighted = false
			isTakingTouchEvent = false
			return
		}
		super.touchesEnded(touches, with: event)
	}
	
	override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
		if isTakingTouchEvent {
			isHighlighted = false
			isTakingTouchEvent = false
			return
		}
		super.touchesCancelled(touches, with: event)
	}
}


