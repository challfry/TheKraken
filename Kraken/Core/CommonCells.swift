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
	private static let validReuseIDs = [ "LabelCell" : NibAndClass(LabelCell.self, "LabelCell")]
	override class var validReuseIDDict: [String: NibAndClass ] { return validReuseIDs }

	dynamic var labelText: NSAttributedString?
	
	init(_ titleLabel: NSAttributedString) {
		labelText = titleLabel
		super.init(bindingWith: LabelCellProtocol.self)
	}
}

class LabelCell: BaseCollectionViewCell, LabelCellProtocol {
	@IBOutlet var label: UILabel!
	
	var labelText: NSAttributedString? {
		didSet { label.attributedText = labelText }
	}
}


// MARK: Simple text entry cell with a label and a TextField.
@objc protocol TextFieldCellProtocol {
	dynamic var labelText: String? { get set }
	dynamic var isPassword: Bool { get set }
}

@objc class TextFieldCellModel: BaseCellModel, TextFieldCellProtocol {	
	private static let validReuseIDs = [ "TextFieldCell" : NibAndClass(TextFieldCell.self, "TextFieldCell")]
	override class var validReuseIDDict: [String: NibAndClass ] { return validReuseIDs }

	dynamic var labelText: String?
	dynamic var isPassword: Bool = false
	@objc dynamic var editedText: String?
	
	init(_ titleLabel: String) {
		labelText = titleLabel
		super.init(bindingWith: TextFieldCellProtocol.self)
	}
}

class TextFieldCell: BaseCollectionViewCell, TextFieldCellProtocol, UITextFieldDelegate {
	@IBOutlet var textField: UITextField!
	@IBOutlet var label: UILabel!
	
	var labelText: String? {
		didSet { label.text = labelText }
	}
	var isPassword: Bool = false {
		didSet {
			textField.clearsOnBeginEditing = isPassword
			textField.isSecureTextEntry = isPassword
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
}

// MARK: Button cell; right-alighed button
@objc protocol ButtonCellProtocol {
	dynamic var buttonText: String? { get set }
	dynamic var buttonEnabled: Bool { get set } 
	dynamic var buttonAction: (() -> Void)? { get set } 
	dynamic var buttonAlignment: NSTextAlignment { get set }
	
}

@objc class ButtonCellModel: BaseCellModel, ButtonCellProtocol {
	private static let validReuseIDs = [ "ButtonCell" :  NibAndClass(ButtonCell.self, "ButtonCell")]
	override class var validReuseIDDict: [String: NibAndClass ] { return validReuseIDs }

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
@objc protocol LoginStatusCellProtocol {
	dynamic var statusText: String { get set }
	dynamic var showSpinner: Bool { get set }
	dynamic var collection: UICollectionView? { get set }
}

@objc class LoginStatusCellModel: BaseCellModel, LoginStatusCellProtocol {	
	private static let validReuseIDs = [ "LoginStatusCell" : NibAndClass(LoginStatusCell.self, "LoginStatusCell")]
	override class var validReuseIDDict: [String: NibAndClass ] { return validReuseIDs }

	@objc dynamic var statusText: String = ""
	@objc dynamic var showSpinner: Bool = false
	@objc dynamic var collection: UICollectionView?

	init(cv: UICollectionView) {
		collection = cv
		super.init(bindingWith: LoginStatusCellProtocol.self)
		
		CurrentUser.shared.tell(self, when:[ "isChangingLoginState", "lastError" ]) { observer, observed in
		
			observer.shouldBeVisible = true
			observer.showSpinner = true
			observer.statusText = observed.isLoggedIn() ? "Logging out" : "Logging in"
			
//			if observed.isChangingLoginState || observed.lastError != nil {
//				observer.shouldBeVisible = true
//			}
//			observer.showSpinner = observed.isChangingLoginState
//			if observed.isChangingLoginState {
//				observer.statusText = observed.isLoggedIn() ? "Logging out" : "Logging in"
//			}
//			else {
//				if let error = observed.lastError as? CurrentUser.CurrentUserError {
//					observer.statusText = error.errorString
//	//				observer.statusText = "This is a very long error string, specifically to test out how the cell resizes itself in response to the text in the label changing."
//				}
//				else {
//					observer.statusText = ""
//				}
//			}
		}?.schedule()
	}
}

@objc class LoginStatusCell: BaseCollectionViewCell, LoginStatusCellProtocol {
	@IBOutlet var statusLabel: UILabel!
	@IBOutlet var spinner: UIActivityIndicatorView!
	@objc dynamic var collection: UICollectionView?

	var statusText: String = "" {
		didSet { 
			statusLabel.text = statusText; 
			self.layer.removeAllAnimations()
			collection?.performBatchUpdates({ }, completion: nil )
		}
	}
	var showSpinner: Bool = false { 
		didSet { spinner.isHidden = !showSpinner }
	}
}

