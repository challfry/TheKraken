//
//  BaseCollectionViewCell.swift
//  Kraken
//
//  Created by Chall Fry on 4/16/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit

struct NibAndClass {
	let cellClass: AnyClass
	var nib: UINib? = nil
	var prototypeCell: BaseCollectionViewCell? = nil
	
	init(_ cellClass: AnyClass, _ nibName: String?) {
		self.cellClass = cellClass
		if let nibName = nibName {
			nib = UINib(nibName: nibName, bundle: nil)
		}
	}
}

// Usually, cellModel:Cell:reuseID are 1:1:1. Multiple reuseIDs for a single cell class can work--make reuseID()
// return different values for different model data. Multiple models launching the same cell class works, and 
// a single cellModel could spin up different cell classes depending on model values, but you'd need to override makeCell.
// However, each reuseID must map to exactly one cell class (no subclasses), and for sanity's sake we're also making reuseIDs 1:1 with xib
// files for xib-based cells.
@objc class BaseCellModel: NSObject {
	class var validReuseIDDict: [String: NibAndClass] { return [:] }
	
	var bindingProtocol: Protocol?
	var observations = [EBNObservation]()
	@objc dynamic var shouldBeVisible = true
	
	init(bindingWith: Protocol?) {
		bindingProtocol = bindingWith
	}
	
	func reuseID() -> String { return type(of: self).validReuseIDDict.first?.key ?? "" }

	func makeCell(for collectionView: UICollectionView, indexPath: IndexPath) -> UICollectionViewCell {
	
		let id = reuseID()
		if let nibAndClass = type(of: self).validReuseIDDict[id] {
	
			// Register the nib if there is one, else register the cell class.
			if let nib = nibAndClass.nib  {
				collectionView.register(nib, forCellWithReuseIdentifier: id)
			}
			else {
				collectionView.register(nibAndClass.cellClass, forCellWithReuseIdentifier: id)
			}
		
			// Get a cell and property bind it to the cell model
			let cell = collectionView.dequeueReusableCell(withReuseIdentifier: id, for: indexPath) as! BaseCollectionViewCell
			if let prot = self.bindingProtocol {
				cell.bind(to:self, with: prot)
			}
			cell.cellModel = self
			
			return cell
		}
		
		// TODO: fix default cell
		return  collectionView.dequeueReusableCell(withReuseIdentifier: "none", for: indexPath)
	}
	
	func makePrototypeCell(for collectionView: UICollectionView, indexPath: IndexPath) -> BaseCollectionViewCell? {
		let id = reuseID()
		if var nibAndClass = type(of:self).validReuseIDDict[id] {
			if nibAndClass.prototypeCell == nil {
				if let nibContents = nibAndClass.nib?.instantiate(withOwner: nil, options: nil) {
					nibAndClass.prototypeCell = (nibContents[0] as! BaseCollectionViewCell)
				}
			}
			
			let cell = nibAndClass.prototypeCell!
			if let prot = self.bindingProtocol {
				cell.bind(to:self, with: prot)
			}
			cell.cellModel = self
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

@objc class BaseCollectionViewCell: UICollectionViewCell {
	class var validReuseIDDict: [String : UINib] { return [:] }

	var cellModel: BaseCellModel? 
	var calculatedHeight: CGFloat = 200.0
	    
	override func awakeFromNib() {
		super.awakeFromNib()
		contentView.translatesAutoresizingMaskIntoConstraints = false
		contentView.widthAnchor.constraint(equalToConstant: 414).isActive = true
		
	}

	override func preferredLayoutAttributesFitting(_ layoutAttributes: UICollectionViewLayoutAttributes) 
			-> UICollectionViewLayoutAttributes {
		let attrs = super.preferredLayoutAttributesFitting(layoutAttributes)
		setNeedsLayout()
		layoutIfNeeded()
		let size = contentView.systemLayoutSizeFitting(layoutAttributes.size)
		var frame = layoutAttributes.frame
		frame.size.height = ceil(size.height)
		calculatedHeight = frame.size.height
		attrs.frame = frame
//		print(frame)
		return attrs
	}
	
	func calculateHeight(for width: CGFloat) -> CGSize {
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
