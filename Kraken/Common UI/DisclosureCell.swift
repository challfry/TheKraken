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
	
	init() {
		super.init(bindingWith: DisclosureCellProtocol.self)
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
	
	var highlightAnimation: UIViewPropertyAnimator?
	override var isHighlighted: Bool {
		didSet {
			if let oldAnim = highlightAnimation {
				oldAnim.stopAnimation(true)
			}
			let anim = UIViewPropertyAnimator(duration: 0.2, curve: .easeInOut) {
				self.contentView.backgroundColor = self.isHighlighted || self.privateSelected ? UIColor(white:0.95, alpha: 1.0) : UIColor.white
			}
			anim.isUserInteractionEnabled = true
			anim.isInterruptible = true
			anim.startAnimation()
			highlightAnimation = anim
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
		setupGestureRecognizer()
	}
	
	// Either the cell or its model can override cellTapped to handle taps in the cell.
	func cellTapped() {
		if let model = cellModel as? DisclosureCellModel {
			model.cellTapped()
		}
	}
}

//extension DisclosureCell: UIGestureRecognizerDelegate {
//
//	func setupGestureRecognizer() {	
//		let tapper = UILongPressGestureRecognizer(target: self, action: #selector(DisclosureCell.cellTapGesture))
//		tapper.minimumPressDuration = 0.1
//		tapper.numberOfTouchesRequired = 1
//		tapper.numberOfTapsRequired = 0
//		tapper.allowableMovement = 10.0
//		tapper.delegate = self
//		tapper.name = "DisclosureCell Tap Detector"
//		self.addGestureRecognizer(tapper)
//		tapRecognizer = tapper
//	}
//
//	override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
//		// need to call super if it's not our recognizer
//		if gestureRecognizer != tapRecognizer {
//			return false
//		}
//		
//		return true
//	}
//
//	@objc func cellTapGesture(_ sender: UILongPressGestureRecognizer) {
//		if sender.state == .began {
//			isHighlighted = true
//		}
//		
//		let currentPoint = sender.location(in: self)
//		var isInside = false
//		if point(inside: currentPoint, with: nil) {
//			isInside = true
//		}
//
//		if sender.state == .changed {
//			isHighlighted = isInside
//		}
//		else if sender.state == .ended {
//			if isInside {
//				cellTapped()
//			}
//		} 
//		
//		if sender.state == .ended || sender.state == .cancelled || sender.state == .failed {
//			isHighlighted = false
//		}
//	}
//	
//}
