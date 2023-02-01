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

	override func cellTapped(dataSource: KrakenDataSource?, vc: UIViewController?) {
		tapAction?(self)
	}
}

class DisclosureCell: BaseCollectionViewCell, DisclosureCellProtocol {
	@IBOutlet var titleLabel: UILabel!
	@IBOutlet var errorLabel: UILabel!
	private static let cellInfo = [ "DisclosureCell" : PrototypeCellInfo("DisclosureCell") ]
	override class var validReuseIDDict: [ String: PrototypeCellInfo ] { return cellInfo }

	var title: String? {
		didSet { 
			titleLabel.text = title
			cellSizeChanged()
		}
	}
	var errorString: String? {
		didSet { 
			errorLabel.text = errorString
			cellSizeChanged()
		}
	}
		
	override var isHighlighted: Bool {
		didSet {
			standardHighlightHandler()
		}
	}
		
	override func awakeFromNib() {
		super.awakeFromNib()
		
		titleLabel.styleFor(.body)
		errorLabel.styleFor(.body)
	}
}
