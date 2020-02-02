//
//  DisclosureCell.swift
//  Kraken
//
//  Created by Chall Fry on 6/25/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit

@objc protocol DisclosureCellProtocol {
	dynamic var title: String? { get set }
	dynamic var errorString: String? { get set }
}

@objc class DisclosureCellModel: BaseCellModel, DisclosureCellProtocol {
	private static let validReuseIDs = [ "DisclosureCell" : DisclosureCell.self ]
	override class var validReuseIDDict: [String: BaseCollectionViewCell.Type ] { return validReuseIDs }

	dynamic var title: String?
	dynamic var errorString: String?
	var tapAction: ((DisclosureCellModel) -> Void)?
	
	init() {
		super.init(bindingWith: DisclosureCellProtocol.self)
	}

	override func cellTapped() {
		tapAction?(self)
	}
}

class DisclosureCell: BaseCollectionViewCell, DisclosureCellProtocol {
	@IBOutlet var titleLabel: UILabel!
	@IBOutlet var errorLabel: UILabel!
	private static let cellInfo = [ "DisclosureCell" : PrototypeCellInfo("DisclosureCell") ]
	override class var validReuseIDDict: [ String: PrototypeCellInfo ] { return cellInfo }

	var title: String? {
		didSet { titleLabel.text = title }
	}
	var errorString: String? {
		didSet { errorLabel.text = errorString }
	}
	
	var tapRecognizer: UILongPressGestureRecognizer?
	
	override var isHighlighted: Bool {
		didSet {
			standardHighlightHandler()
		}
	}
	
	override var isSelected: Bool {
		didSet {
			if isSelected {
				cellTapped()
			}
		}
	}
	
	override func awakeFromNib() {
		super.awakeFromNib()
	}
		
	// Either the cell or its model can override cellTapped to handle taps in the cell.
	func cellTapped() {
		if let model = cellModel as? DisclosureCellModel {
			model.cellTapped()
		}
	}
}
