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
}

@objc class SocialCellModel : BaseCellModel, SocialCellProtocol {
	private static let validReuseIDs = [ "SocialCell" : SocialCell.self ]
	override class var validReuseIDDict: [String: BaseCollectionViewCell.Type ] { return validReuseIDs }

	dynamic var labelText: String? 
	dynamic var iconName: String?
	var navPacket: GlobalNavPacket
	

	init(_ titleLabel: String, imageNamed: String, nav: GlobalNavPacket) {
		labelText = titleLabel
		iconName = imageNamed
		self.navPacket = nav
		super.init(bindingWith: SocialCellProtocol.self)
	}
	
	override var privateSelected: Bool {
		didSet {
			if privateSelected, let appDel = UIApplication.shared.delegate as? AppDelegate {
				appDel.globalNavigateTo(packet: navPacket)
			}
		}
	}
}

class SocialCell: BaseCollectionViewCell, SocialCellProtocol {
	@IBOutlet var label: UILabel!
	@IBOutlet var imageView: UIImageView!
	
	private static let cellInfo = [ "SocialCell" : PrototypeCellInfo("SocialCell") ]
	override class var validReuseIDDict: [ String: PrototypeCellInfo ] { return cellInfo }
	
	override func awakeFromNib() {
		allowsSelection = true
		
		// Font styling
		label.styleFor(.body)
	}	
	
	var labelText: String? {
		didSet { label.text = labelText }
	}
	var iconName: String? {
		didSet { 
			if let name = iconName {
				imageView.image = UIImage(named: name)?.withRenderingMode(.alwaysTemplate)
			}
			else {
				imageView.image = nil
			}
		}
	}
	
	var highlightAnimation: UIViewPropertyAnimator?
	override var isHighlighted: Bool {
		didSet {
			if let oldAnim = highlightAnimation {
				oldAnim.stopAnimation(true)
			}
			let anim = UIViewPropertyAnimator(duration: 0.2, curve: .easeInOut) {
				self.contentView.backgroundColor = self.isHighlighted || self.privateSelected ? 
						UIColor(named: "Cell Background Selected") : UIColor(named: "Cell Background")
			}
			anim.isUserInteractionEnabled = true
			anim.isInterruptible = true
			anim.startAnimation()
			highlightAnimation = anim
		}
	}
}
