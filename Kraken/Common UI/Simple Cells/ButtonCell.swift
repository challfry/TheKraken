//
//  ButtonCell.swift
//  Kraken
//
//  Created by Chall Fry on 7/7/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit

// MARK: Button cell; right-alighed button
@objc protocol ButtonCellProtocol {
	dynamic var buttonAlignment: NSTextAlignment { get set }

	dynamic var button1Text: String? { get set }
	dynamic var button1Enabled: Bool { get set } 
	dynamic var button1Action: (() -> Void)? { get set } 
	dynamic var button2Text: String? { get set }
	dynamic var button2Enabled: Bool { get set } 
	dynamic var button2Action: (() -> Void)? { get set } 
	dynamic var infoText: NSAttributedString? { get set }
	dynamic var errorText: String? { get set }
}

@objc class ButtonCellModel: BaseCellModel, ButtonCellProtocol {
	private static let validReuseIDs = [ "ButtonCell" : ButtonCell.self ]
	override class var validReuseIDDict: [String: BaseCollectionViewCell.Type ] { return validReuseIDs }

	dynamic var buttonAlignment: NSTextAlignment

	dynamic var button1Text: String?
	dynamic var button1Enabled: Bool 
	dynamic var button1Action: (() -> Void)?
	dynamic var button2Text: String?
	dynamic var button2Enabled: Bool 
	dynamic var button2Action: (() -> Void)?
	dynamic var infoText: NSAttributedString?
	dynamic var errorText: String?
	
	init(alignment: NSTextAlignment = .right) {
		buttonAlignment = alignment
		button1Enabled = false
		button2Enabled = false
		errorText = nil
		super.init(bindingWith: ButtonCellProtocol.self)
	}
	
	init(title: String, alignment: NSTextAlignment = .right, action: (() -> Void)?) {
		buttonAlignment = alignment
		button1Enabled = true
		button1Text = title
		button1Action = action
		button2Enabled = false
		errorText = nil
		super.init(bindingWith: ButtonCellProtocol.self)
	}
	
	func setupButton(_ index: Int, title: String?, action: (() -> Void)?) {
		// I mean, I *could* use an array, but where's the fun in that? (I should be using an array of buttons)
		if index == 1 {
			button1Enabled = true
			button1Text = title
			button1Action = action
		}
		else if index == 2 {
			button2Enabled = true
			button2Text = title
			button2Action = action
		}
	}
}

class ButtonCell: BaseCollectionViewCell, ButtonCellProtocol {
	@IBOutlet weak var infoLabel: UILabel!
	@IBOutlet var button1: UIButton!
	@IBOutlet var button2: UIButton!
	@IBOutlet var leftConstraint: NSLayoutConstraint!
	@IBOutlet var centerXConstraint: NSLayoutConstraint!
	@IBOutlet var rightConstraint: NSLayoutConstraint!
	@IBOutlet weak var errorLabel: UILabel!
	
	private static let cellInfo = [ "ButtonCell" : PrototypeCellInfo("ButtonCell") ]
	override class var validReuseIDDict: [ String: PrototypeCellInfo ] { return cellInfo }

	dynamic var button1Action: (() -> Void)?
	dynamic var button2Action: (() -> Void)?

	var buttonAlignment: NSTextAlignment = .right {
		didSet {
			leftConstraint.isActive = buttonAlignment == .left
			centerXConstraint.isActive = buttonAlignment == .center
			rightConstraint.isActive = buttonAlignment == .right
			errorLabel.textAlignment = buttonAlignment
		}
	}

	var button1Text: String? {  
		didSet { 
			button1.setTitle(button1Text, for:.normal)
			button1.isHidden = button1Text?.isEmpty ?? true
		}
	}
	var button1Enabled: Bool = true { didSet { button1.isEnabled = button1Enabled } } 
	var button2Text: String? {  
		didSet {
			button2.setTitle(button2Text, for:.normal)
			button2.isHidden = button2Text?.isEmpty ?? true
		}
	}
	var button2Enabled: Bool = true { didSet { button2.isEnabled = button2Enabled } } 
		
	var infoText: NSAttributedString? {
		didSet {
			infoLabel.attributedText = infoText
		}
	}
	
	var errorText: String? {
		didSet {
			errorLabel.text = errorText
			cellSizeChanged()
		}
	}

	@IBAction func button1Tapped(_ sender: Any) {
		button1Action?()
	}
	
	@IBAction func button2Tapped(_ sender: Any) {
		button2Action?()
	}
	
	override func awakeFromNib() {
		super.awakeFromNib()
		
		button1.styleFor(.body)
		button2.styleFor(.body)
		infoLabel.styleFor(.body)
	}
}


