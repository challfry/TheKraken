//
//  LabelCell.swift
//  Kraken
//
//  Created by Chall Fry on 7/7/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit

@objc protocol LabelCellProtocol {
	dynamic var labelText: NSAttributedString? { get set }
}

@objc class LabelCellModel: BaseCellModel, LabelCellProtocol {	
	private static let validReuseIDs = [ "LabelCell" : LabelCell.self ]
	override class var validReuseIDDict: [String: BaseCollectionViewCell.Type ] { return validReuseIDs }

	dynamic var labelText: NSAttributedString?
	
	init(_ titleLabel: NSAttributedString) {
		labelText = titleLabel
		super.init(bindingWith: LabelCellProtocol.self)
	}
	
	init(_ titleLabel: String) {
		labelText = NSAttributedString(string: titleLabel)
		super.init(bindingWith: LabelCellProtocol.self)
	}
}

class LabelCell: BaseCollectionViewCell, LabelCellProtocol {
	@IBOutlet var label: UILabel!
	private static let cellInfo = [ "LabelCell" : PrototypeCellInfo("LabelCell") ]
	override class var validReuseIDDict: [ String: PrototypeCellInfo ] { return cellInfo }
	
	var labelText: NSAttributedString? {
		didSet { 
			label.attributedText = labelText 
			cellSizeChanged()
		}
	}
}


// MARK: Cell with two labels, a bold title and a normal value.

@objc protocol SingleValueCellProtocol {
	var title: String? { get set }
	var value: String? { get set }
}

@objc class SingleValueCellModel: BaseCellModel, SingleValueCellProtocol {
	private static let validReuseIDs = [ "SingleValue" : SingleValueCell.self ]
	override class var validReuseIDDict: [String: BaseCollectionViewCell.Type ] { return validReuseIDs }

	dynamic var title: String?
	dynamic var value: String?
	
	init(_ titleStr: String, _ valueStr: String? = nil) {
		title = titleStr
		value = valueStr
		super.init(bindingWith: SingleValueCellProtocol.self)
	}
}

class SingleValueCell: BaseCollectionViewCell, SingleValueCellProtocol {
	@IBOutlet var titleLabel: UILabel!
	@IBOutlet var valueLabel: UILabel!

	private static let cellInfo = [ "SingleValue" : PrototypeCellInfo("SingleValueCell") ]
	override class var validReuseIDDict: [ String: PrototypeCellInfo ] { return cellInfo }

	var title: String? {
		didSet { titleLabel.text = title }
	}
	var value: String? {
		didSet { valueLabel.text = value }
	}
}

