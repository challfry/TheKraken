//
//  TableIndexView.swift
//  Kraken
//
//  Created by Chall Fry on 2/2/20.
//  Copyright © 2020 Chall Fry. All rights reserved.
//

import UIKit

protocol TableIndexDelegate: NSObject {
	func itemNameAt(percentage: CGFloat) -> String
	func scrollToPercentage(_ percentage: CGFloat)
}

class TableIndexView: UIView, UIGestureRecognizerDelegate {
//	static let fullIndexChars = "1234567890ABCDEFGHIJKLMNOPQRSTUVWXYZ"
	static let fullIndexChars = "1ABCDEFGHIJKLMNOPQRSTUVWXYZ"
	static let halfIndexChars = "1BDFHJLNPRTVXZ"

	weak var delegate: TableIndexDelegate?
	var floatingLabel: UILabel?
	var floatingLabelTextAttrs:  [NSAttributedString.Key : Any] = [:]
		
	func setup(_ del: TableIndexDelegate) {
		delegate = del
		let label = UILabel()
		label.backgroundColor = UIColor(named: "Overlay Label Background")
		label.textAlignment	= .right
		label.isHidden = true
		self.addSubview(label)
		floatingLabel = label

		let baseFont =  UIFont.systemFont(ofSize: 17)
		let authorFont = UIFontMetrics(forTextStyle: .body).scaledFont(for: baseFont, maximumPointSize: 36.0)
		floatingLabelTextAttrs = [ .foregroundColor : UIColor(named: "Kraken Label Text") as Any,
				.font : authorFont as Any ]
	}
	
	func filterUpdated() {
		
	}
	
	override func draw(_ rect: CGRect) {
		// Background first
		if let color = UIColor(named: "VC Background")?.cgColor {
			UIGraphicsGetCurrentContext()?.setFillColor(color)
			UIGraphicsGetCurrentContext()?.fill(rect)
		}
		
		// 
		var indexString = TableIndexView.fullIndexChars
		if bounds.size.height < 360 {
			indexString = TableIndexView.halfIndexChars
		}
		let stepSize = bounds.size.height / CGFloat(indexString.count)
		let textAttrs: [NSAttributedString.Key : Any] = [ .foregroundColor : UIColor(named: "Kraken Label Text") as Any ]
		for index in 0..<indexString.count {
		
			let str = NSAttributedString(string: String(Array(indexString)[index]), attributes: textAttrs)
			let strSize = str.size()
			let position = CGPoint(x: 8 - (strSize.width / 2), y: CGFloat(index) * stepSize)
			str.draw(at: position)
		}
	}
	
	func positionLabel(yPos: CGFloat) {
		let percentage = yPos / (bounds.size.height - 10)
		if let stringToShow = delegate?.itemNameAt(percentage: percentage), let label = floatingLabel {
			let labelString = NSAttributedString(string: stringToShow, attributes: floatingLabelTextAttrs)
			label.attributedText = labelString
			label.sizeToFit()

			label.frame = CGRect(x: 0 - label.bounds.size.width - 35, y: yPos - 10,
					width: label.bounds.size.width, height: label.bounds.size.height)
		}
	}

// UIResponder Methods	
	override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
		if let touch = touches.first {
			floatingLabel?.isHidden = false
			positionLabel(yPos: touch.location(in: self).y) 
		}
	}

	override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
		if let touch = touches.first {
			positionLabel(yPos: touch.location(in: self).y) 
			
			// If the user moves far enough off the the left of our view, stop interacting with this event.
			if touch.location(in:self).x < -200 {
				floatingLabel?.isHidden = true
			}
		}
	}
	
	override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
		floatingLabel?.isHidden = true
		if let touch = touches.first {
			let percentage = touch.location(in: self).y / (bounds.size.height - 10)
			delegate?.scrollToPercentage(percentage)
		}
	}

	override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
		floatingLabel?.isHidden = true
	}

}
