//
//  TextCells.swift
//  Kraken
//
//  Created by Chall Fry on 7/7/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit

// MARK: Simple text entry cell with a label and a TextField

@objc protocol TextFieldCellProtocol {
	dynamic var labelText: String? { get set }
	dynamic var fieldText: String? { get set }
	dynamic var errorText: String? { get set }
	dynamic var purpose: TextFieldCellModel.Purpose { get set }
	dynamic var showClearTextButton: Bool { get set }
	dynamic var returnButtonHit: ((String) -> Void)? { get set } 
}

@objc class TextFieldCellModel: BaseCellModel, TextFieldCellProtocol {	
	private static let validReuseIDs = [ "TextFieldCell" : TextFieldCell.self ]
	override class var validReuseIDDict: [String: BaseCollectionViewCell.Type ] { return validReuseIDs }

	dynamic var labelText: String?
	@objc dynamic var fieldText: String?
	dynamic var errorText: String?
	dynamic var purpose: Purpose = .normal
	dynamic var showClearTextButton: Bool = false
	dynamic var returnButtonHit: ((String) -> Void)?
	@objc dynamic var editedText: String?			// Cell fills this in
	
	@objc enum Purpose: Int {
		case normal
		case email
		case roomNumber
		case username
		case password
		case url
	}
	
	init(_ titleLabel: String, purpose: Purpose = .normal) {
		labelText = titleLabel
		self.purpose = purpose
		super.init(bindingWith: TextFieldCellProtocol.self)
	}
	
	func hasText() -> Bool {
		if let text = getText() {
			return !text.isEmpty
		}
		else {
			return false
		}
	}

	func getText() -> String? {
		return editedText ?? fieldText
	}
	
	// It's easiest to just force an update to fieldText.
	func clearText() {
		fieldText = "."
		fieldText = ""
		editedText = ""
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
	
	var purpose: TextFieldCellModel.Purpose = .normal {
		didSet {
			textField.clearsOnBeginEditing = false
			textField.isSecureTextEntry = false
			textField.textContentType = nil
			
			switch purpose {
			case .normal:
				textField.keyboardType = .default
			case .email:
				textField.keyboardType = .emailAddress
				textField.textContentType = .emailAddress
			case .roomNumber:
				textField.keyboardType = .numberPad
			case .username:
				textField.keyboardType = .default
				textField.textContentType = .username
			case .password:
				textField.keyboardType = .default
				textField.clearsOnBeginEditing = true
				textField.isSecureTextEntry = true
				textField.textContentType = .password
			case .url:
				textField.keyboardType = .URL
				textField.textContentType = .URL
			}
		}
	}
	
	var showClearTextButton: Bool = false {
		didSet {
			textField.clearButtonMode = showClearTextButton ? .always : .never
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
	var returnButtonHit: ((String) -> Void)?
	
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
	
	func textFieldShouldReturn(_ textField: UITextField) -> Bool {
		returnButtonHit?(textField.text ?? "")
		textField.text = ""
		if let model = cellModel as? TextFieldCellModel {
			model.editedText = textField.text
		}
		return false
	}

	override func prepareForReuse() {
		textField.text = ""
		super.prepareForReuse()
	}
}

// MARK: - Multi-Line Text Entry Cell

@objc protocol TextViewCellProtocol {
	dynamic var labelText: String? { get set }
	dynamic var editText: String? { get set }
	dynamic var errorText: String? { get set }
	dynamic var isEditable: Bool { get set }
	dynamic var purpose: TextViewCellModel.Purpose { get set }
}

@objc class TextViewCellModel: BaseCellModel, TextViewCellProtocol {	
	private static let validReuseIDs = [ "TextViewCell" : TextViewCell.self ]
	override class var validReuseIDDict: [String: BaseCollectionViewCell.Type ] { return validReuseIDs }

	dynamic var labelText: String?
	dynamic var editText: String?
	dynamic var errorText: String?
	@objc dynamic var editedText: String?			// Cell fills this in
	@objc dynamic var isEditable: Bool = true
	dynamic var purpose: Purpose = .normal
	
	@objc enum Purpose: Int {
		case normal
		case twitarr
	}

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
	
	func getText() -> String? {
		return editedText ?? editText
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
		didSet {  
			errorLabel.text = errorText
			errorLabel.isHidden = errorText == nil
		}
	}
	
	var isEditable: Bool = true {
		didSet {
			textView.isEditable = isEditable
		}
	}
	
	var purpose: TextViewCellModel.Purpose = .normal {
		didSet {
			textView.keyboardType = .default
			
			switch purpose {
			case .normal:
				textView.keyboardType = .default
			case .twitarr:
				textView.keyboardType = .twitter
			}
		}
	}
	override func awakeFromNib() {
		errorLabel.isHidden = true
		
		// Font styling
		label.styleFor(.body)
		errorLabel.styleFor(.body)
	}
	
	func textViewDidBeginEditing(_ textView: UITextView) {
		if let vc = viewController as? BaseCollectionViewController {
			vc.textViewBecameActive(textView, inCell: self)
		}
		fitTextViewToText(animated: false)
	}
	
	func textViewDidEndEditing(_ textView: UITextView) {
		if let vc = viewController as? BaseCollectionViewController {
			vc.textViewResignedActive(textView, inCell: self)
		}
	}
	
	func textViewDidChange(_ textView: UITextView) {
		fitTextViewToText(animated: true)
	}
	
	func fitTextViewToText(animated: Bool = true) {
		if let model = cellModel as? TextViewCellModel {
			model.editedText = textView.text
			let newSize = textView.sizeThatFits(CGSize(width: textView.frame.size.width, height: 10000.0))
			if newSize.height != textViewHeightConstraint.constant {
				if animated {
					let _ = UIViewPropertyAnimator(duration: 0.4, curve: .easeInOut) {
						self.textViewHeightConstraint.constant = newSize.height
					}
				}
				else {
					self.textViewHeightConstraint.constant = newSize.height
				}
				cellSizeChanged()
			}
		}
	}
}


