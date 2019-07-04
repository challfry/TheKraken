//
//  CommonCells.swift
//  Kraken
//
//  Created by Chall Fry on 4/25/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import Foundation
import UIKit

// MARK: Label Cell

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
		didSet { label.attributedText = labelText }
	}
}


// MARK: Cell with two labels, a bold title and a normal value.
@objc protocol SingleValueCellProtocol {
	var title: String? { get set }
	var value: String? { get set }
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

// MARK: Simple text entry cell with a label and a TextField.
@objc protocol TextFieldCellProtocol {
	dynamic var labelText: String? { get set }
	dynamic var fieldText: String? { get set }
	dynamic var errorText: String? { get set }
	dynamic var isPassword: Bool { get set }
}

@objc class TextFieldCellModel: BaseCellModel, TextFieldCellProtocol {	
	private static let validReuseIDs = [ "TextFieldCell" : TextFieldCell.self ]
	override class var validReuseIDDict: [String: BaseCollectionViewCell.Type ] { return validReuseIDs }

	dynamic var labelText: String?
	@objc dynamic var fieldText: String?
	dynamic var errorText: String?
	dynamic var isPassword: Bool = false
	@objc dynamic var editedText: String?			// Cell fills this in
	
	init(_ titleLabel: String, isPassword: Bool = false) {
		labelText = titleLabel
		self.isPassword = isPassword
		super.init(bindingWith: TextFieldCellProtocol.self)
	}
	
	func hasText() -> Bool {
		if let text = editedText {
			return !text.isEmpty
		}
		else {
			return false
		}
	}
}

class TextFieldCell: BaseCollectionViewCell, TextFieldCellProtocol, UITextFieldDelegate {
	@IBOutlet var textField: UITextField!
	@IBOutlet var label: UILabel!
	@IBOutlet var errorLabel: UILabel!

	private static let cellInfo = [ "TextFieldCell" : PrototypeCellInfo("TextFieldCell") ]
	override class var validReuseIDDict: [ String: PrototypeCellInfo ] { return cellInfo }
	
	var labelText: String? {
		didSet { label.text = labelText }
	}
	var fieldText: String? {
		didSet { 
			if let model = cellModel as? TextFieldCellModel, let text = model.editedText {
				textField.text = text
			}
			else {
				textField.text = fieldText
			}
		}
	}
	var errorText: String? {
		didSet { errorLabel.text = errorText; cellSizeChanged() }
	}
	var isPassword: Bool = false {
		didSet {
			textField.clearsOnBeginEditing = isPassword
			textField.isSecureTextEntry = isPassword
		}
	}
	
	func textFieldDidBeginEditing(_ textField: UITextField) {
		if let vc = viewController as? BaseCollectionViewController {
			vc.activeTextEntry = textField
		}
	}
	
	func textFieldDidEndEditing(_ textField: UITextField, reason: UITextField.DidEndEditingReason) {
		if let vc = viewController as? BaseCollectionViewController {
			vc.activeTextEntry = nil
		}
	}
	
	func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
		if let model = cellModel as? TextFieldCellModel, var textFieldContents = textField.text {
			let swiftRange: Range<String.Index> = Range(range, in: textFieldContents)!
			textFieldContents.replaceSubrange(swiftRange, with: string)
			model.editedText = textFieldContents
		}
		return true
	}
	
	func textFieldShouldClear(_ textField: UITextField) -> Bool {
		if let model = cellModel as? TextFieldCellModel {
			model.editedText = ""
		}
		return true
	}
	
	func textFieldDidEndEditing(_ textField: UITextField) {
		if let model = cellModel as? TextFieldCellModel {
			model.editedText = textField.text
		}
	}

}

// MARK: Multi-Line Text Entry Cell
@objc protocol TextViewCellProtocol {
	dynamic var labelText: String? { get set }
	dynamic var editText: String? { get set }
	dynamic var errorText: String? { get set }
	dynamic var isEditable: Bool { get set }
}

@objc class TextViewCellModel: BaseCellModel, TextViewCellProtocol {	
	private static let validReuseIDs = [ "TextViewCell" : TextViewCell.self ]
	override class var validReuseIDDict: [String: BaseCollectionViewCell.Type ] { return validReuseIDs }

	dynamic var labelText: String?
	dynamic var editText: String?
	dynamic var errorText: String?
	@objc dynamic var editedText: String?			// Cell fills this in
	@objc dynamic var isEditable: Bool = true
	
	init(_ titleLabel: String) {
		labelText = titleLabel
		editText = ""
		super.init(bindingWith: TextViewCellProtocol.self)
	}
	
	func hasText() -> Bool {
		if let text = editedText {
			return !text.isEmpty
		}
		else {
			return false
		}
	}
}

class TextViewCell: BaseCollectionViewCell, TextViewCellProtocol, UITextViewDelegate {
	@IBOutlet var textView: UITextView!
	@IBOutlet var label: UILabel!
	@IBOutlet var errorLabel: UILabel!
	@IBOutlet var textViewHeightConstraint: NSLayoutConstraint!
	
	private static let cellInfo = [ "TextViewCell" : PrototypeCellInfo("TextViewCell") ]
	override class var validReuseIDDict: [ String: PrototypeCellInfo ] { return cellInfo }
	
	var labelText: String? {
		didSet { label.text = labelText }
	}
	var editText: String? {
		didSet {
			if isPrototypeCell, let model = cellModel as? TextViewCellModel, let editedText = model.editedText  {
				textView.text = editedText
				let newSize = textView.sizeThatFits(CGSize(width: textView.frame.size.width, height: 10000.0))
				textViewHeightConstraint.constant = newSize.height
			}
			else {
				textView.text = editText 
			}
		}
	}
	var errorText: String? {
		didSet {  //errorLabel.text = errorText
		}
	}
	
	var isEditable: Bool = true {
		didSet {
			textView.isEditable = isEditable
		}
	}
	
	func textViewDidBeginEditing(_ textView: UITextView) {
		if let vc = viewController as? BaseCollectionViewController {
			vc.activeTextEntry = textView
		}
	}
	
	func textViewDidEndEditing(_ textView: UITextView) {
		if let vc = viewController as? BaseCollectionViewController {
			vc.activeTextEntry = nil
		}
	}
	
	func textViewDidChange(_ textView: UITextView) {
		if let model = cellModel as? TextViewCellModel {
			model.editedText = textView.text
			let newSize = textView.sizeThatFits(CGSize(width: textView.frame.size.width, height: 10000.0))
			if newSize.height != textViewHeightConstraint.constant {
				let _ = UIViewPropertyAnimator(duration: 0.4, curve: .easeInOut) {
					self.textViewHeightConstraint.constant = newSize.height
				}
				cellSizeChanged()
			}
		}
	}
}


// MARK: Button cell; right-alighed button
@objc protocol ButtonCellProtocol {
	dynamic var buttonAlignment: NSTextAlignment { get set }

	dynamic var button1Text: String? { get set }
	dynamic var button1Enabled: Bool { get set } 
	dynamic var button1Action: (() -> Void)? { get set } 
	dynamic var button2Text: String? { get set }
	dynamic var button2Enabled: Bool { get set } 
	dynamic var button2Action: (() -> Void)? { get set } 
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

	init(alignment: NSTextAlignment = .right) {
		buttonAlignment = alignment
		button1Enabled = false
		button2Enabled = false
		super.init(bindingWith: ButtonCellProtocol.self)
	}
	
	init(title: String, action: (() -> Void)?, alignment: NSTextAlignment = .right) {
		buttonAlignment = alignment
		button1Enabled = true
		button1Text = title
		button1Action = action
		button2Enabled = false
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
	@IBOutlet var button1: UIButton!
	@IBOutlet var button2: UIButton!
	@IBOutlet var leftConstraint: NSLayoutConstraint!
	@IBOutlet var centerXConstraint: NSLayoutConstraint!
	@IBOutlet var rightConstraint: NSLayoutConstraint!

	private static let cellInfo = [ "ButtonCell" : PrototypeCellInfo("ButtonCell") ]
	override class var validReuseIDDict: [ String: PrototypeCellInfo ] { return cellInfo }

	var buttonAlignment: NSTextAlignment = .right {
		didSet {
			leftConstraint.isActive = buttonAlignment == .left
			centerXConstraint.isActive = buttonAlignment == .center
			rightConstraint.isActive = buttonAlignment == .right
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
		

	dynamic var button1Action: (() -> Void)?
	@IBAction func button1Tapped(_ sender: Any) {
		button1Action?()
	}
	dynamic var button2Action: (() -> Void)?
	@IBAction func button2Tapped(_ sender: Any) {
		button2Action?()
	}
	
}




// MARK: Status cell; activity name + spinner, or error status on failure
@objc protocol OperationStatusCellProtocol {
	dynamic var statusText: String { get set }
	dynamic var errorText: String? { get set }
	dynamic var showSpinner: Bool { get set }
}

@objc class OperationStatusCellModel: BaseCellModel, OperationStatusCellProtocol {
	private static let validReuseIDs = [ "OperationStatusCell" : OperationStatusCell.self ]
	override class var validReuseIDDict: [String: BaseCollectionViewCell.Type ] { return validReuseIDs }

	@objc dynamic var errorText: String?
	@objc dynamic var statusText: String = ""
	@objc dynamic var showSpinner: Bool = false

	init() {
		super.init(bindingWith: OperationStatusCellProtocol.self)
	}
}

@objc class LoginStatusCellModel: BaseCellModel, OperationStatusCellProtocol {	
	private static let validReuseIDs = [ "OperationStatusCell" : OperationStatusCell.self ]
	override class var validReuseIDDict: [String: BaseCollectionViewCell.Type ] { return validReuseIDs }

	@objc dynamic var statusText: String = ""
	@objc dynamic var errorText: String?
	@objc dynamic var showSpinner: Bool = false

	init() {
		super.init(bindingWith: OperationStatusCellProtocol.self)
		
		CurrentUser.shared.tell(self, when:[ "isChangingLoginState", "lastError" ]) { observer, observed in
					
			observer.shouldBeVisible = observed.isChangingLoginState || observed.lastError != nil 
			observer.showSpinner = observed.isChangingLoginState
			if observed.isChangingLoginState {
				observer.statusText = observed.isLoggedIn() ? "Logging out" : "Logging in"
			}
			else {
				if let error = observed.lastError {
					observer.errorText = error.getErrorString()
	//				observer.statusText = "This is a very long error string, specifically to test out how the cell resizes itself in response to the text in the label changing."
				}
				else {
					observer.errorText = nil
				}
			}
		}?.schedule()
	}
}

@objc class OperationStatusCell: BaseCollectionViewCell, OperationStatusCellProtocol {
	@IBOutlet var statusLabel: UILabel!
	@IBOutlet var spinner: UIActivityIndicatorView!
	@objc dynamic var collection: UICollectionView?

	private static let cellInfo = [ "OperationStatusCell" : PrototypeCellInfo("OperationStatusCell") ]
	override class var validReuseIDDict: [ String: PrototypeCellInfo ] { return cellInfo }

	var statusText: String = "" {
		didSet { 
			statusLabel.text = statusText
			self.layer.removeAllAnimations()
		}
	}
	var errorText: String? {
		didSet {
			let newText = errorText ?? statusText
			statusLabel.text = newText
			self.layer.removeAllAnimations()
		}
	}
	
	var showSpinner: Bool = false { 
		didSet { spinner.isHidden = !showSpinner }
	}
}

