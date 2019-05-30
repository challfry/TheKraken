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
	@objc dynamic var cellHeight = 0
	
	// Cells built from this model can use this to store their state data. State data includes stuff like text entered in text fields.
	// The dict is indexed by reuseID.
//	var cellStateStorage: [String : Any] = [:]
	
	init(bindingWith: Protocol?) {
		bindingProtocol = bindingWith
	}
	
	func reuseID() -> String { return type(of: self).validReuseIDDict.first?.key ?? "" }

	func makeCell(for collectionView: UICollectionView, indexPath: IndexPath) -> UICollectionViewCell {
	
		let id = reuseID()
		// Get a cell and property bind it to the cell model
		let cell = collectionView.dequeueReusableCell(withReuseIdentifier: id, for: indexPath) as! BaseCollectionViewCell 
		
		if let prot = self.bindingProtocol {
			cell.bind(to:self, with: prot)
		}
		cell.cellModel = self
		cell.collectionView = collectionView
		return cell
		
		
		// TODO: fix default cell
//		return  collectionView.dequeueReusableCell(withReuseIdentifier: "none", for: indexPath)
	}
	
	// Makes a prototype cell, binds the cell to the cellModel. By overriding reuseID, subclasses can
	// have a single model that spawns different cell classes.
	func makePrototypeCell(for collectionView: UICollectionView, indexPath: IndexPath) -> BaseCollectionViewCell? {
		let id = reuseID()
		
		if let classType = type(of: self).validReuseIDDict[id], let cellInfo = classType.validReuseIDDict[id],
				let cell = cellInfo.prototypeCell {
			if let prot = self.bindingProtocol {
				cell.bind(to:self, with: prot)
			}
			cell.cellModel = self
			cell.collectionView = collectionView
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
	@objc dynamic weak var viewController: BaseCollectionViewController?  // For launching segues
	
	var isPrototypeCell: Bool = false
	var calculatedHeight: CGFloat = 0.0
	var fullWidthConstraint: NSLayoutConstraint?
	var fullWidth: Bool = true
	    
	weak var collectionView: UICollectionView? {
		didSet {
			guard let width = collectionView?.bounds.width, width > 0 else { return }
			if fullWidth && fullWidthConstraint == nil {
				fullWidthConstraint = contentView.widthAnchor.constraint(equalToConstant: width)
			}
			fullWidthConstraint?.isActive = fullWidth
		}
	}
	
	func cellSizeChanged() {
		if !isPrototypeCell {
//			if let indexPath = collectionView?.indexPath(for: self) {
//				collectionView?.reloadItems(at: [indexPath])
//				collectionView?.collectionViewLayout.invalidateLayout()
				let context = UICollectionViewFlowLayoutInvalidationContext()
				context.invalidateFlowLayoutDelegateMetrics = true
				
				collectionView?.performBatchUpdates({ 
					collectionView?.collectionViewLayout.invalidateLayout(with: context)
				}, completion: nil)
			}
//		}
	}

	override func awakeFromNib() {
		super.awakeFromNib()
		contentView.translatesAutoresizingMaskIntoConstraints = false
	}
	
	// Returns a prototype cell that this class can manage. Doesn't set up that cell's data. Subclasses can define
	// multiple reuseIDs which will load different nibs/layouts.
	class func makePrototypeCell(for collectionView: UICollectionView, indexPath: IndexPath, reuseID: String) -> BaseCollectionViewCell? {		
		if let cellInfo = validReuseIDDict[reuseID], let cell = cellInfo.prototypeCell {
			cell.collectionView = collectionView
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
		calculatedHeight = size.height
		return size
	}
	
	override func prepareForReuse() {
		super.prepareForReuse()
		cellModel?.unbind(cell: self)
	}
}
