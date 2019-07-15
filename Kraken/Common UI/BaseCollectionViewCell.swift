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
	
	init(bindingWith: Protocol?) {
		bindingProtocol = bindingWith
	}
	
	func reuseID() -> String { return type(of: self).validReuseIDDict.first?.key ?? "" }

	func makeCell(for collectionView: UICollectionView, indexPath: IndexPath) -> BaseCollectionViewCell {
		let id = reuseID()
		// Get a cell and property bind it to the cell model
		let cell = collectionView.dequeueReusableCell(withReuseIdentifier: id, for: indexPath) as! BaseCollectionViewCell 
		CollectionViewLog.assert(cell.reuseIdentifier != nil, "Just dequeued a cell that has no reuseID.")
	
		cell.isBuildingCell = true
		cell.collectionViewSizeChanged(to: collectionView.bounds.size)	
		cell.dataSource = collectionView.dataSource as? KrakenDataSource
		if let prot = self.bindingProtocol {
			cell.bind(to:self, with: prot)
		}
		cell.cellModel = self
		cell.isBuildingCell = false
		return cell
	}
	
	// Makes a prototype cell, binds the cell to the cellModel. By overriding reuseID, subclasses can
	// have a single model that spawns different cell classes.
	func makePrototypeCell(for collectionView: UICollectionView, indexPath: IndexPath) -> BaseCollectionViewCell? {
		let id = reuseID()
		
		if let classType = type(of: self).validReuseIDDict[id], let cellInfo = classType.validReuseIDDict[id],
				let cell = cellInfo.prototypeCell {

			cell.collectionViewSizeChanged(to: collectionView.bounds.size)	
			cell.dataSource = collectionView.dataSource as? KrakenDataSource
			if let prot = self.bindingProtocol {
				cell.bind(to:self, with: prot)
			}
			cell.cellModel = self
			
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

	func cellTapped() {
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
	}
}

struct PrototypeCellInfo {
	var nib: UINib? = nil
	var prototypeCell: BaseCollectionViewCell? = nil
	
	init(_ nibName: String?) {
		if let nibName = nibName {
			nib = UINib(nibName: nibName, bundle: nil)
			if let nibContents = nib?.instantiate(withOwner: nil, options: nil) {
				prototypeCell = (nibContents[0] as! BaseCollectionViewCell)
				prototypeCell?.isPrototypeCell = true
			}
		}
	}
}

@objc class BaseCollectionViewCell: UICollectionViewCell {
	class var validReuseIDDict: [String : PrototypeCellInfo ] { return [:] }
	class func registerCells(with controller: UICollectionView) {
		for (reuseID, info) in self.validReuseIDDict {
			if let nib = info.nib {
				controller.register(nib, forCellWithReuseIdentifier: reuseID)
			}
		}
	}

	var cellModel: BaseCellModel? 							// Not all datasources use cell models
	var dataSource: KrakenDataSource?						// May not be top-level DS
	@objc dynamic weak var viewController: UIViewController?  // For launching segues

	var observations = Set<EBNObservation>()
	var isPrototypeCell: Bool = false
	var calculatedSize: CGSize = CGSize(width: 0.0, height: 0.0)
	var isBuildingCell = false
	var customGR: UILongPressGestureRecognizer?
	
	override func awakeFromNib() {
		super.awakeFromNib()
		contentView.translatesAutoresizingMaskIntoConstraints = false
		self.translatesAutoresizingMaskIntoConstraints = false
	}
	
	// Called on cell creation and then whenever the cv size changes.
	var fullWidth: Bool = true
	var fullWidthConstraint: NSLayoutConstraint?
	func collectionViewSizeChanged(to newSize: CGSize) {
		// Subclasses can set fullWidth in awakeFromNib; this then sets cell width to cv width
		if fullWidth && fullWidthConstraint == nil {
			fullWidthConstraint = contentView.widthAnchor.constraint(equalToConstant: newSize.width)
		}
		fullWidthConstraint?.isActive = fullWidth
	}
	
	
	// Initiates a change in selection state. Only cells can do this, not models. But, state is saved in the model.
	// If the model doesn't pass this var back to the cell, no selection will be visible.
	@objc dynamic var privateSelected: Bool = false 
	func privateSelectCell(_ newState: Bool = true) {
		if let model = cellModel {
			model.privateSelected = true
			if let ds = self.dataSource {
				ds.setCellSelection(cell: self, newState: newState)
			}
		}
	}
	
	func cellSizeChanged() {
		setNeedsLayout()
		if !isPrototypeCell, !isBuildingCell, let model = cellModel {
			dataSource?.sizeChanged(for: model)
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
	
	func calculateSize() -> CGSize {
		setNeedsLayout()
		layoutIfNeeded()
		
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
	
}

extension BaseCollectionViewCell: UIGestureRecognizerDelegate {

	func setupGestureRecognizer() {	
		let tapper = UILongPressGestureRecognizer(target: self, action: #selector(BaseCollectionViewCell.cellTapped))
		tapper.minimumPressDuration = 0.05
		tapper.numberOfTouchesRequired = 1
		tapper.numberOfTapsRequired = 0
		tapper.allowableMovement = 10.0
		tapper.delegate = self
		tapper.name = "BaseCollectionViewCell Long Press"
		addGestureRecognizer(tapper)
		customGR = tapper
	}

	override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
		// need to call super if it's not our recognizer
		if gestureRecognizer != customGR {
			return super.gestureRecognizerShouldBegin(gestureRecognizer)
		}
		let hitPoint = gestureRecognizer.location(in: self)
		if !point(inside:hitPoint, with: nil) {
			return false
		}		
		return true
	}

	@objc func cellTapped(_ sender: UILongPressGestureRecognizer) {
		if sender.state == .began {
			isHighlighted = point(inside:sender.location(in: self), with: nil)
		}
		else if sender.state == .changed {
			isHighlighted = point(inside:sender.location(in: self), with: nil)
		}
		else if sender.state == .ended {
			if (isHighlighted) {
				isSelected = true
			}
			isHighlighted = false
		}
		else if sender.state == .cancelled {
			isHighlighted = false	
		}
	}
}


