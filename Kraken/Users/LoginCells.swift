//
//  LoginCells.swift
//  Kraken
//
//  Created by Chall Fry on 3/29/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit

/* Cells show up when logged out and:
	- user taps compose new tweet
	- user taps compose new forum post
	- user goes to seamail tab
	- user goes to login in settings
*/

// MARK: Login

@objc protocol LoginHeaderCellProtocol {
	dynamic var labelText: String? { get set }
	dynamic var subLabelText: String? { get set }
}

@objc class LoginHeaderCellModel: BaseCellModel, LoginHeaderCellProtocol {
	private static let validReuseIDs = [ "loginHeader" : LoginHeaderCell.self ]
	override class var validReuseIDDict: [String: BaseCollectionViewCell.Type ] { return validReuseIDs }

	dynamic var labelText: String? {
		didSet { shouldBeVisible = labelText != nil }
	}
	dynamic var subLabelText: String? 

	init() {
		super.init(bindingWith: LoginHeaderCellProtocol.self)
	}
}

class LoginHeaderCell: BaseCollectionViewCell, LoginHeaderCellProtocol {
	@IBOutlet var topLabel: UILabel!
	@IBOutlet var subLabel: UILabel!
	private static let cellInfo = [ "loginHeader" : PrototypeCellInfo("LoginHeaderCell") ]
	override class var validReuseIDDict: [ String: PrototypeCellInfo] { return cellInfo }

	var labelText: String? { 
		didSet { topLabel.text = labelText }
	}
	var subLabelText: String? { 
		didSet { 
			UIViewPropertyAnimator(duration: 0.6, curve: .easeInOut) {
				self.subLabel.text = self.subLabelText
				self.subLabel.alpha = self.subLabel.text == nil ? 0.0 : 1.0
			}.startAnimation()
			cellSizeChanged()
		}
	}
}

class LoginButtonCellModel: ButtonCellModel {
	weak var segment: LoginDataSourceSegment?

	init(title: String?, action: (() -> Void)?, dss: LoginDataSourceSegment) {
		segment = dss
		super.init(alignment: .right)
		setupButton(1, title: title, action: action)

		CurrentUser.shared.tell(self, when:"isChangingLoginState") { observer, observed in 
			observer.calcButtonEnable()
		}
		segment?.tell(self, when: ["usernameCellModel.editedText", "passwordCellModel.editedText"]) { observer, observed in 
			observer.calcButtonEnable()
		}?.execute()
		
		segment?.tell(self, when: "mode") { observer, observed in 
				observer.shouldBeVisible = observed.mode == .login 
		}?.execute()
	}
	
	func calcButtonEnable() {
		button1Enabled = segment?.usernameCellModel.editedText?.isEmpty == false && 
					segment?.passwordCellModel.editedText?.isEmpty == false &&
					!CurrentUser.shared.isChangingLoginState
	}
}

// MARK: Create Account

class CreateAccountHeaderLabelModel: LabelCellModel {
	init(dataSource: LoginDataSourceSegment) {
		super.init(CreateAccountHeaderLabelModel.buildNewRegistrationHeaderString())
		
		dataSource.tell(self, when: "mode") { observer, observed in 
				observer.shouldBeVisible = observed.mode == .createAccount 
		}?.execute()
	}
	
	class func buildNewRegistrationHeaderString() -> NSAttributedString {
		let bodyText = """
				
				
				By signing up for and using Twit-arr, you agree to abide by the JoCo Cruise 2020 Code of Conduct / harassment \
				policy that all JoCo Cruise attendees must sign. (The short version: everyone play nice!)

				In the event that you encounter someone on Twit-arr not behaving in accordance with the Code of Conduct, \
				please seek a Helper Monkey for assistance, who will in turn work with the Twit-arr tech team to effect \
				any necessary changes within the Twit-arr platform.

				Your Twit-arr registration code was sent to you via e-mail. If you did not receive your registration code \
				or do not have access to your e-mail, go to the JoCo Cruise Info Desk for assistance. Please enter your \
				code below. Your registration code can only be used once, so do not share it with others. You will be \
				held accountable for the actions of ANYONE using your code. If you need an additional code to create an \
				additional account, please request one at the JoCo Cruise Info Desk.
				"""


		let titleStr = NSMutableAttributedString(string: "Preliminary niceties...", attributes: 
				[ .font: UIFont.preferredFont(forTextStyle:.headline) ])
		let bodyStr = NSMutableAttributedString(string: bodyText, attributes: 
				[ .font: UIFont.preferredFont(forTextStyle:.body) ])
		titleStr.append(bodyStr)
		
		return titleStr 

	}
}

class EditDisplayNameCellModel : TextFieldCellModel {
	init(segment: LoginDataSourceSegment) {
		super.init("Display Name:")
		
		segment.tell(self, when: "mode") { observer, observed in 
				observer.shouldBeVisible = observed.mode == .createAccount 
		}?.execute()

		CurrentUser.shared.tell(self, when: "lastError.fieldErrors.display_name") { observer, observed in 
			if let errors = (observed.lastError as? ServerError)?.fieldErrors?["display_name"] {
				observer.errorText = errors[0]
			}
			else {
				observer.errorText = ""
			}
		}?.execute()
	}
}

class RegistrationCodeCellModel: TextFieldCellModel {
	init(segment: LoginDataSourceSegment) {
		super.init("Registration Code:")
		
		segment.tell(self, when: "mode") { observer, observed in 
				observer.shouldBeVisible = observed.mode == .createAccount || observed.mode == .forgotPassword
		}?.execute()
		
		CurrentUser.shared.tell(self, when: "lastError.fieldErrors.registration_code") { observer, observed in 
			if let errors = (observed.lastError as? ServerError)?.fieldErrors?["registration_code"] {
				observer.errorText = errors[0]
			}
		}
	}
}

class ConfirmPasswordCellModel: TextFieldCellModel {
	init(segment: LoginDataSourceSegment) {
		super.init("Confirm Password:", purpose: .password)
		
		segment.tell(self, when: "mode") { observer, observed in 
				observer.shouldBeVisible = observed.mode == .createAccount || observed.mode == .forgotPassword
		}?.execute()
	}
}

class CreateAccountButtonCellModel: ButtonCellModel {
	weak var segment: LoginDataSourceSegment?

	init(title: String?, action: (() -> Void)?, dss: LoginDataSourceSegment) {
		segment = dss
		super.init(alignment: .right)
		setupButton(1, title: title, action: action)

//		CurrentUser.shared.tell(self, when:"isChangingLoginState") { observer, observed in 
//			observer.calcButtonEnable()
//		}
		segment?.tell(self, when: ["usernameCellModel.editedText", "passwordCellModel.editedText"]) { observer, observed in 
			observer.calcButtonEnable()
		}?.execute()

		segment?.tell(self, when: "mode") { observer, observed in 
			observer.shouldBeVisible = observed.mode == .createAccount
		}?.execute()
	}
	
	func calcButtonEnable() {
		button1Enabled = segment?.usernameCellModel.editedText?.isEmpty == false && 
					segment?.passwordCellModel.editedText?.isEmpty == false &&
					!CurrentUser.shared.isChangingLoginState
	}
}

// MARK: Forgot Password

class ForgotPasswordButtonCellModel: ButtonCellModel {
	weak var segment: LoginDataSourceSegment?

	init(title: String?, action: (() -> Void)?, dss: LoginDataSourceSegment) {
		segment = dss
		super.init(alignment: .right)
		setupButton(1, title: title, action: action)

		CurrentUser.shared.tell(self, when:"isChangingLoginState") { observer, observed in 
			observer.calcButtonEnable()
		}
		segment?.tell(self, when: ["usernameCellModel.editedText", "passwordCellModel.editedText",
				"confirmPasswordCellModel.editedText", "registrationCodeCellModel.editedText"]) { observer, observed in 
			observer.calcButtonEnable()
		}?.execute()

		segment?.tell(self, when: "mode") { observer, observed in 
			observer.shouldBeVisible = observed.mode == .forgotPassword
		}?.execute()
	}
	
	func calcButtonEnable() {
		button1Enabled = segment?.usernameCellModel.editedText?.isEmpty == false && 
					segment?.passwordCellModel.editedText?.isEmpty == false &&
					segment?.confirmPasswordCellModel.editedText?.isEmpty == false &&
					segment?.registrationCodeCellModel.editedText?.isEmpty == false &&
					!CurrentUser.shared.isChangingLoginState
	}
}


// MARK: Common to all Modes

class EditUsernameCellModel: TextFieldCellModel {
	init(_ titleLabel: String) {
		super.init(titleLabel, purpose: .username)
		
		CurrentUser.shared.tell(self, when: ["lastError.fieldErrors.username", 
				"lastError.fieldErrors.new_username"]) { observer, observed in 
			if let errors = (observed.lastError as? ServerError)?.fieldErrors?["username"] {
				observer.errorText = errors[0]
			}
			else if let errors = (observed.lastError as? ServerError)?.fieldErrors?["new_username"] {
				observer.errorText = errors[0]
			}
			else {
				observer.errorText = ""
			}
		}
	}
}

class EditPasswordCellModel: TextFieldCellModel {
	init() {
		super.init("Password:", purpose: .password)
		
		CurrentUser.shared.tell(self, when: ["lastError.fieldErrors.new_password", 
				"lastError.fieldErrors.current_password", "lastError.fieldErrors.password"]) { observer, observed in 
			if let errors = (observed.lastError as? ServerError)?.fieldErrors?["new_password"] {
				observer.errorText = errors[0]
			}
			else if let errors = (observed.lastError as? ServerError)?.fieldErrors?["current_password"] {
				observer.errorText = errors[0]
			}
			else if let errors = (observed.lastError as? ServerError)?.fieldErrors?["password"] {
				observer.errorText = errors[0]
			}
			else {
				observer.errorText = ""
			}
		}
	}
}

class ModeSwitchButtonCellModel: ButtonCellModel {
	var targetMode: LoginDataSourceSegment.Mode = .login

	init(title: String, forMode: LoginDataSourceSegment.Mode, segment: LoginDataSourceSegment) {
		targetMode = forMode
		super.init(alignment: .left)
		setupButton(1, title: title, action: { [weak segment] in segment?.mode = forMode })
		
		segment.tell(self, when: "mode") { observer, observed in 
			observer.shouldBeVisible = observed.mode != observer.targetMode
		}?.execute()
	}
}


@objc class LoginDataSourceSegment: FilteringDataSourceSegment {

	@objc enum Mode: Int {
		case login, createAccount, forgotPassword
	}
	@objc dynamic var mode: Mode = .login {
		didSet { 
			CurrentUser.shared.clearErrors() 
			
			switch mode {
				case .login: headerCellModel.subLabelText = nil
				case .createAccount: headerCellModel.subLabelText = "…and to log in you may need to create an account."
				case .forgotPassword: headerCellModel.subLabelText = "…and to log in you may need to recover your password.\n\nYou can use the registration code you received in the mail to set a new password for your account."
			}
		}
	}

	// The Login cells show up when we need to log in before seeing content. The idea is that the login cells show up
	// *on the same screen* the content will show up on, via the magic of data sources. This text is to tell the user
	// why it is we're making them log in.
	var headerCellText: String? {
		didSet { headerCellModel.labelText = headerCellText }
	}
	var headerCellModel = LoginHeaderCellModel()
	@objc dynamic lazy var usernameCellModel = EditUsernameCellModel("Username:")
	@objc dynamic lazy var displayNameCellModel = EditDisplayNameCellModel(segment: self)
	@objc dynamic lazy var passwordCellModel = EditPasswordCellModel()
	@objc dynamic lazy var confirmPasswordCellModel = ConfirmPasswordCellModel(segment: self)
	@objc dynamic lazy var registrationCodeCellModel = RegistrationCodeCellModel(segment: self)
			
	override init() {
		super.init()
		segmentName = "User Login"
	
		append(headerCellModel)
		append(CreateAccountHeaderLabelModel(dataSource: self))
		append(usernameCellModel)
		append(registrationCodeCellModel)
		append(displayNameCellModel)
		append(passwordCellModel)
		append(confirmPasswordCellModel)
		append(LoginButtonCellModel(title: "Login", action: weakify(self, LoginDataSourceSegment.startLoggingIn), dss: self))
		append(CreateAccountButtonCellModel(title: "Create Account", 
				action: weakify(self, LoginDataSourceSegment.startAccountCreation), dss: self))
		append(ForgotPasswordButtonCellModel(title: "Reset Password", 
				action: weakify(self, LoginDataSourceSegment.startResetPassword), dss: self))
		append(LoginStatusCellModel())
		append(ModeSwitchButtonCellModel(title: "Actually, just let me log in.", forMode: .login, segment: self))
		append(ModeSwitchButtonCellModel(title: "Create a new account", forMode: .createAccount, segment: self))
		append(ModeSwitchButtonCellModel(title: "I've, uh, forgotten my password.", forMode: .forgotPassword, segment: self))
		append(ButtonCellModel(title: "Read Code of Conduct", action: weakify(self, type(of:self).readCodeOfConductAction), 
				alignment: .left))
	}
	
	func startLoggingIn() {
    	if let userName = usernameCellModel.editedText, let password = passwordCellModel.editedText {
			CurrentUser.shared.clearErrors() 
	    	CurrentUser.shared.loginUser(name: userName, password: password)
			clearAllSensitiveFields()
		}
	}
	
	func startAccountCreation() {
		guard usernameCellModel.hasText() && passwordCellModel.hasText() && registrationCodeCellModel.hasText() else {
			// TODO: show error state
			return		
		}
//		guard passwordCellModel.editedText == confirmPasswordCellModel.editedText else {
//			// TODO: show error state
//			return		
//		}
	
		CurrentUser.shared.clearErrors() 
    	if let userName = usernameCellModel.editedText, let password = passwordCellModel.editedText,
    			let regCode = registrationCodeCellModel.editedText {
	    	let displayName = displayNameCellModel.editedText
	    	CurrentUser.shared.createNewAccount(name: userName, password: password, displayName: displayName, regCode: regCode)
			clearAllSensitiveFields()
		}
	}
	
	func startResetPassword() {
    	guard let userName = usernameCellModel.editedText, let newPassword = passwordCellModel.editedText,
    			let regCode = registrationCodeCellModel.editedText else { return }
		CurrentUser.shared.clearErrors() 
		CurrentUser.shared.resetPassword(name: userName, regCode: regCode, newPassword: newPassword) {}
		clearAllSensitiveFields()
	}
	
	func readCodeOfConductAction() {
		let storyboard = UIStoryboard(name: "Main", bundle: nil)
		if let textFileVC = storyboard.instantiateViewController(withIdentifier: "ServerTextFileDisplay") as? ServerTextFileViewController {
			textFileVC.fileToLoad = "codeofconduct"
			textFileVC.titleText = "Code Of Conduct"
			dataSource?.viewController?.present(textFileVC, animated: true, completion: nil)
		}
	}
	
	func clearAllSensitiveFields() {
		dataSource?.collectionView?.endEditing(true)
		passwordCellModel.clearText()
		confirmPasswordCellModel.clearText()
		registrationCodeCellModel.clearText()
	}
		
}

