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
	dynamic var badgeValue: String? { get set }
}

@objc class SocialCellModel : BaseCellModel, SocialCellProtocol {
	private static let validReuseIDs = [ "SocialCell" : SocialCell.self ]
	override class var validReuseIDDict: [String: BaseCollectionViewCell.Type ] { return validReuseIDs }

	dynamic var labelText: String? 
	dynamic var iconName: String?
	dynamic var badgeValue: String?
	dynamic var contentDisabled: Bool = false
	var navPacket: GlobalNavPacket?
	
	

	init(_ titleLabel: String, imageNamed: String) {
		labelText = titleLabel
		iconName = imageNamed
		super.init(bindingWith: SocialCellProtocol.self)
	}
	
	override func cellTapped(dataSource: KrakenDataSource?, vc: UIViewController?) {
		if let appDel = UIApplication.shared.delegate as? AppDelegate, var packet = navPacket {
			if let vc = vc as? BaseCollectionViewController, let nav = vc.navigationController as? KrakenNavController {
				packet.column = nav.columnIndex
			}
			appDel.globalNavigateTo(packet: packet)
		}
	}
}

class SocialCell: BaseCollectionViewCell, SocialCellProtocol {
	@IBOutlet var label: UILabel!
	@IBOutlet var imageView: UIImageView!
	@IBOutlet var badgeLabel: UILabel!
	
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
	
	var badgeValue: String? {
		didSet {
			badgeLabel.text = badgeValue
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
			if let image = UIImage(named: name) {
				imageView.image = image
			}
			else
//			imageView.image = UIImage(named: name)?.withRenderingMode(.alwaysTemplate)
			if #available(iOS 15.0, *) {
//				let config = UIImage.SymbolConfiguration(hierarchicalColor: UIColor(named: "Kraken Icon Blue")!)
//						.applying(UIImage.SymbolConfiguration(pointSize: 22, weight: .regular, scale: .large))
				let config = UIImage.SymbolConfiguration(paletteColors: [UIColor(named: "Kraken Icon Secondary")!,  UIColor(named: "Kraken Icon Blue")!])
						.applying(UIImage.SymbolConfiguration(pointSize: 22, weight: .regular, scale: .large))
//				let config = UIImage.SymbolConfiguration(paletteColors: [UIColor(named: "Kraken Icon Blue")!,  UIColor(named: "Kraken Icon Secondary")!])
				imageView.image = UIImage(systemName: name)?.applyingSymbolConfiguration(config)
			}
			else {
				imageView.image = UIImage(named: name)?.withRenderingMode(.alwaysTemplate)
			}
		}
		else {
			imageView.image = nil
		}

	}
}
