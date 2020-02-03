//
//  SocialCell.swift
//  Kraken
//
//  Created by Chall Fry on 1/19/20.
//  Copyright © 2020 Chall Fry. All rights reserved.
//

import UIKit

@objc protocol SocialCellProtocol {
	dynamic var labelText: String? { get set }
	dynamic var iconName: String? { get set }
	dynamic var contentDisabled: Bool { get set }
}

@objc class SocialCellModel : BaseCellModel, SocialCellProtocol {
	private static let validReuseIDs = [ "SocialCell" : SocialCell.self ]
	override class var validReuseIDDict: [String: BaseCollectionViewCell.Type ] { return validReuseIDs }

	dynamic var labelText: String? 
	dynamic var iconName: String?
	dynamic var contentDisabled: Bool = false
	var navPacket: GlobalNavPacket
	

	init(_ titleLabel: String, imageNamed: String, nav: GlobalNavPacket) {
		labelText = titleLabel
		iconName = imageNamed
		self.navPacket = nav
		super.init(bindingWith: SocialCellProtocol.self)
	}
	
	override func cellTapped(dataSource: KrakenDataSource?) {
		if let appDel = UIApplication.shared.delegate as? AppDelegate {
			appDel.globalNavigateTo(packet: navPacket)
		}
	}
}

class SocialCell: BaseCollectionViewCell, SocialCellProtocol {
	@IBOutlet var label: UILabel!
	@IBOutlet var imageView: UIImageView!
	
	private static let cellInfo = [ "SocialCell" : PrototypeCellInfo("SocialCell") ]
	override class var validReuseIDDict: [ String: PrototypeCellInfo ] { return cellInfo }
	
	var labelText: String? {
		didSet {
			setup() 
		}
	}
	
	var iconName: String? {
		didSet { 
			setup() 
		}
	}
	
	var contentDisabled: Bool = false {
		didSet {
			setup() 
		}
	}
	
	override var isHighlighted: Bool {
		didSet {
			standardHighlightHandler()
		}
	}
	
	override func awakeFromNib() {
		allowsSelection = true
		isAccessibilityElement = true
		
		// Font styling
		label.styleFor(.body)
	}	
	
	func setup() {
		if let labelText = labelText {
			label.text = "\(labelText) \(contentDisabled ? " (Disabled)" : "")"
			accessibilityLabel = label.text 
		}
		
		if contentDisabled {
			imageView.image = UIImage(named: "Disabled")?.withRenderingMode(.alwaysTemplate)
		} 
		else if let name = iconName {
			imageView.image = UIImage(named: name)?.withRenderingMode(.alwaysTemplate)
		}
		else {
			imageView.image = nil
		}

	}
}
