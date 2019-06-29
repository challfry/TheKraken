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
	dynamic var buttonText: String? { get set }
	dynamic var buttonEnabled: Bool { get set } 
	dynamic var buttonAction: (() -> Void)? { get set } 
	dynamic var buttonAlignment: NSTextAlignment { get set }
	
}

@objc class ButtonCellModel: BaseCellModel, ButtonCellProtocol {
	private static let validReuseIDs = [ "ButtonCell" : ButtonCell.self ]
	override class var validReuseIDDict: [String: BaseCollectionViewCell.Type ] { return validReuseIDs }

	dynamic var buttonText: String? {
		didSet { shouldBeVisible = buttonText != nil }
	}
	dynamic var buttonEnabled: Bool 
	dynamic var buttonAction: (() -> Void)?
	dynamic var buttonAlignment: NSTextAlignment

	init(title: String?, action: (() -> Void)?, alignment: NSTextAlignment = .right) {
		buttonText = title
		buttonAction = action
		buttonEnabled = true
		buttonAlignment = alignment
		super.init(bindingWith: ButtonCellProtocol.self)
	}
}

class ButtonCell: BaseCollectionViewCell, ButtonCellProtocol {
	@IBOutlet var button: UIButton!
	@IBOutlet var leftConstraint: NSLayoutConstraint!
	@IBOutlet var centerXConstraint: NSLayoutConstraint!
	@IBOutlet var rightConstraint: NSLayoutConstraint!

	private static let cellInfo = [ "ButtonCell" : PrototypeCellInfo("ButtonCell") ]
	override class var validReuseIDDict: [ String: PrototypeCellInfo ] { return cellInfo }

	var buttonText: String? {  didSet { button.setTitle(buttonText, for:.normal) } }
	var buttonEnabled: Bool = true { didSet { button.isEnabled = buttonEnabled } } 
		
	var buttonAlignment: NSTextAlignment = .right {
		didSet {
			leftConstraint.isActive = buttonAlignment == .left
			centerXConstraint.isActive = buttonAlignment == .center
			rightConstraint.isActive = buttonAlignment == .right
		}
	}

	dynamic var buttonAction: (() -> Void)?
	@IBAction func buttonTapped(_ sender: Any) {
		buttonAction?()
	}
	
}




// MARK: Status cell; activity name + spinner, or error status on failure
@objc protocol OperationStatusCellProtocol {
	dynamic var statusText: String { get set }
	dynamic var showSpinner: Bool { get set }
}

@objc class OperationStatusCellModel: BaseCellModel, OperationStatusCellProtocol {
	private static let validReuseIDs = [ "OperationStatusCell" : OperationStatusCell.self ]
	override class var validReuseIDDict: [String: BaseCollectionViewCell.Type ] { return validReuseIDs }

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
					observer.statusText = error.getErrorString()
	//				observer.statusText = "This is a very long error string, specifically to test out how the cell resizes itself in response to the text in the label changing."
				}
				else {
					observer.statusText = ""
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
			statusLabel.text = statusText; 
			self.layer.removeAllAnimations()
		}
	}
	var showSpinner: Bool = false { 
		didSet { spinner.isHidden = !showSpinner }
	}
}

