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
}

@objc class LoginHeaderCellModel: BaseCellModel, LoginHeaderCellProtocol {
	private static let validReuseIDs = [ "loginHeader" : LoginHeaderCell.self ]
	override class var validReuseIDDict: [String: BaseCollectionViewCell.Type ] { return validReuseIDs }

	dynamic var labelText: String? {
		didSet { shouldBeVisible = labelText != nil }
	}

	init() {
		super.init(bindingWith: LoginHeaderCellProtocol.self)
	}
}

class LoginHeaderCell: BaseCollectionViewCell, LoginHeaderCellProtocol {
	@IBOutlet var label: UILabel!
	private static let cellInfo = [ "loginHeader" : PrototypeCellInfo("LoginHeaderCell") ]
	override class var validReuseIDDict: [ String: PrototypeCellInfo] { return cellInfo }

	var labelText: String? { 
		didSet { label.text = labelText }
	}
}

class LoginButtonCellModel: ButtonCellModel {
	var dataSource: LoginDataSource

	init(title: String?, action: (() -> Void)?, ds: LoginDataSource) {
		dataSource = ds
		super.init(title: title, action: action)
		buttonAlignment	= .right

		CurrentUser.shared.tell(self, when:"isChangingLoginState") { observer, observed in 
			observer.calcButtonEnable()
		}
		dataSource.tell(self, when: ["usernameCellModel.editedText", "passwordCellModel.editedText"]) { observer, observed in 
			observer.calcButtonEnable()
		}?.execute()
		
		dataSource.tell(self, when: "mode") { observer, observed in 
				observer.shouldBeVisible = observed.mode == .login 
		}?.execute()
	}
	
	func calcButtonEnable() {
		buttonEnabled = dataSource.usernameCellModel.editedText?.isEmpty == false && 
					dataSource.passwordCellModel.editedText?.isEmpty == false &&
					!CurrentUser.shared.isChangingLoginState
	}
}

// MARK: Create Account

class CreateAccountHeaderLabelModel: LabelCellModel {
	init(dataSource: LoginDataSource) {
		super.init(CreateAccountHeaderLabelModel.buildNewRegistrationHeaderString())
		
		dataSource.tell(self, when: "mode") { observer, observed in 
				observer.shouldBeVisible = observed.mode == .createAccount 
		}?.execute()
	}
	
	class func buildNewRegistrationHeaderString() -> NSAttributedString {
		let bodyText = """
				
				
				By signing up for and using Twit-arr, you agree to abide by the JoCo Cruise 2019 Code of Conduct / harassment \
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
	init(dataSource: LoginDataSource) {
		super.init("Display Name:")
		
		dataSource.tell(self, when: "mode") { observer, observed in 
				observer.shouldBeVisible = observed.mode == .createAccount 
		}?.execute()

		CurrentUser.shared.tell(self, when: "lastError.fieldErrors.display_name") { observer, observed in 
			if let errors = observed.lastError?.fieldErrors?["display_name"] {
				observer.errorText = errors[0]
			}
			else {
				observer.errorText = ""
			}
			observer.cellHeight = observer.cellHeight + 1
		}?.execute()
	}
}

class RegistrationCodeCellModel: TextFieldCellModel {
	init(dataSource: LoginDataSource) {
		super.init("Registration Code:")
		
		dataSource.tell(self, when: "mode") { observer, observed in 
				observer.shouldBeVisible = observed.mode == .createAccount || observed.mode == .forgotPassword
		}?.execute()
		
		CurrentUser.shared.tell(self, when: "lastError.fieldErrors.registration_code") { observer, observed in 
			if let errors = observed.lastError?.fieldErrors?["registration_code"] {
				observer.errorText = errors[0]
			}
		}
	}
}

class ConfirmPasswordCellModel: TextFieldCellModel {
	init(dataSource: LoginDataSource) {
		super.init("Confirm Password:", isPassword: true)
		
		dataSource.tell(self, when: "mode") { observer, observed in 
				observer.shouldBeVisible = observed.mode == .createAccount || observed.mode == .forgotPassword
		}?.execute()
	}
}

class CreateAccountButtonCellModel: ButtonCellModel {
	var dataSource: LoginDataSource

	init(title: String?, action: (() -> Void)?, ds: LoginDataSource) {
		dataSource = ds
		super.init(title: title, action: action)
		buttonAlignment	= .right

//		CurrentUser.shared.tell(self, when:"isChangingLoginState") { observer, observed in 
//			observer.calcButtonEnable()
//		}
		dataSource.tell(self, when: ["usernameCellModel.editedText", "passwordCellModel.editedText"]) { observer, observed in 
			observer.calcButtonEnable()
		}?.execute()

		dataSource.tell(self, when: "mode") { observer, observed in 
			observer.shouldBeVisible = observed.mode == .createAccount
		}?.execute()
	}
	
	func calcButtonEnable() {
		buttonEnabled = dataSource.usernameCellModel.editedText?.isEmpty == false && 
					dataSource.passwordCellModel.editedText?.isEmpty == false &&
					!CurrentUser.shared.isChangingLoginState
	}
}

// MARK: Forgot Password

class ForgotPasswordButtonCellModel: ButtonCellModel {
	var dataSource: LoginDataSource

	init(title: String?, action: (() -> Void)?, ds: LoginDataSource) {
		dataSource = ds
		super.init(title: title, action: action)
		buttonAlignment	= .right

		CurrentUser.shared.tell(self, when:"isChangingLoginState") { observer, observed in 
			observer.calcButtonEnable()
		}
		dataSource.tell(self, when: ["usernameCellModel.editedText", "passwordCellModel.editedText",
				"confirmPasswordCellModel.editedText", "registrationCodeCellModel.editedText"]) { observer, observed in 
			observer.calcButtonEnable()
		}?.execute()

		dataSource.tell(self, when: "mode") { observer, observed in 
			observer.shouldBeVisible = observed.mode == .forgotPassword
		}?.execute()
	}
	
	func calcButtonEnable() {
		buttonEnabled = dataSource.usernameCellModel.editedText?.isEmpty == false && 
					dataSource.passwordCellModel.editedText?.isEmpty == false &&
					dataSource.confirmPasswordCellModel.editedText?.isEmpty == false &&
					dataSource.registrationCodeCellModel.editedText?.isEmpty == false &&
					!CurrentUser.shared.isChangingLoginState
	}
}


// MARK: Common to all Modes

class EditUsernameCellModel: TextFieldCellModel {
	override init(_ titleLabel: String, isPassword: Bool = false) {
		super.init(titleLabel, isPassword: isPassword)
		
		CurrentUser.shared.tell(self, when: ["lastError.fieldErrors.username", 
				"lastError.fieldErrors.new_username"]) { observer, observed in 
			if let errors = observed.lastError?.fieldErrors?["username"] {
				observer.errorText = errors[0]
			}
			else if let errors = observed.lastError?.fieldErrors?["new_username"] {
				observer.errorText = errors[0]
			}
			else {
				observer.errorText = ""
			}
			observer.cellHeight = observer.cellHeight + 1
		}
	}
}

class EditPasswordCellModel: TextFieldCellModel {
	init() {
		super.init("Password:", isPassword: true)
		
		CurrentUser.shared.tell(self, when: ["lastError.fieldErrors.new_password", 
				"lastError.fieldErrors.current_password"]) { observer, observed in 
			if let errors = observed.lastError?.fieldErrors?["new_password"] {
				observer.errorText = errors[0]
			}
			else if let errors = observed.lastError?.fieldErrors?["current_password"] {
				observer.errorText = errors[0]
			}
			else {
				observer.errorText = ""
			}
			observer.cellHeight = observer.cellHeight + 1
		}
	}
}

class ModeSwitchButtonCellModel: ButtonCellModel {
	var targetMode: LoginDataSource.Mode = .login
	var dataSource: LoginDataSource

	init(title: String, forMode: LoginDataSource.Mode, dataSource: LoginDataSource) {
		targetMode = forMode
		self.dataSource = dataSource
		super.init(title: title, action: { dataSource.mode = forMode }, alignment: .left)
		
		dataSource.tell(self, when: "mode") { observer, observed in 
			observer.shouldBeVisible = observed.mode != observer.targetMode
		}?.execute()
	}
}


@objc class LoginDataSource: FilteringDataSource {

	@objc enum Mode: Int {
		case login, createAccount, forgotPassword
	}
	@objc dynamic var mode: Mode = .login {
		didSet { CurrentUser.shared.clearErrors() }
	}

	// The Login cells show up when we need to log in before seeing content. The idea is that the login cells show up
	// *on the same screen* the content will show up on, via the magic of data sources. This text is to tell the user
	// why it is we're making them log in.
	var headerCellText: String? {
		didSet { headerCellModel.labelText = headerCellText }
	}
	var headerCellModel = LoginHeaderCellModel()
	@objc dynamic lazy var usernameCellModel = EditUsernameCellModel("Username:")
	@objc dynamic lazy var displayNameCellModel = EditDisplayNameCellModel(dataSource: self)
	@objc dynamic lazy var passwordCellModel = EditPasswordCellModel()
	@objc dynamic lazy var confirmPasswordCellModel = ConfirmPasswordCellModel(dataSource: self)
	@objc dynamic lazy var registrationCodeCellModel = RegistrationCodeCellModel(dataSource: self)
	
	override init() {
		super.init()
		
		headerCellModel.labelText = headerCellText
	}
		
	func register(with cv:UICollectionView) {
		if allSections.count == 0 {

			let section = self.appendSection(named: "login")
			section.append(headerCellModel)
			section.append(CreateAccountHeaderLabelModel(dataSource: self))
			section.append(usernameCellModel)
			section.append(registrationCodeCellModel)
			section.append(displayNameCellModel)
			section.append(passwordCellModel)
			section.append(confirmPasswordCellModel)
			section.append(LoginButtonCellModel(title: "Login", action: startLoggingIn, ds: self))
			section.append(CreateAccountButtonCellModel(title: "Create Account", action: startAccountCreation, ds: self))
			section.append(ForgotPasswordButtonCellModel(title: "Reset Password", action: startResetPassword, ds: self))
			section.append(LoginStatusCellModel(cv: cv))
			section.append(ModeSwitchButtonCellModel(title: "Actually, just let me log in.", forMode: .login, dataSource: self))
			section.append(ModeSwitchButtonCellModel(title: "Create a new account", forMode: .createAccount, dataSource: self))
			section.append(ModeSwitchButtonCellModel(title: "I've, uh, forgotten my password.", forMode: .forgotPassword, dataSource: self))
			section.append(ButtonCellModel(title: "Read Code of Conduct", action: readCodeOfConductAction,  alignment: .left))
		}

		collectionView = cv
		collectionView?.dataSource = self
		collectionView?.delegate = self
	}
	
	func startLoggingIn() {
    	if let userName = usernameCellModel.editedText, let password = passwordCellModel.editedText {
	    	CurrentUser.shared.loginUser(name: userName, password: password)
		}
	}
	
	func startAccountCreation() {
		guard usernameCellModel.hasText() && passwordCellModel.hasText() && registrationCodeCellModel.hasText() else {
			// TODO: show error state
			return		
		}
		guard passwordCellModel.editedText == confirmPasswordCellModel.editedText else {
			// TODO: show error state
			return		
		}
	
    	if let userName = usernameCellModel.editedText, let password = passwordCellModel.editedText,
    			let regCode = registrationCodeCellModel.editedText {
	    	let displayName = displayNameCellModel.editedText
	    	CurrentUser.shared.createNewAccount(name: userName, password: password, displayName: displayName, regCode: regCode)
		}
	}
	
	func startResetPassword() {
    	guard let userName = usernameCellModel.editedText, let newPassword = passwordCellModel.editedText,
    			let regCode = registrationCodeCellModel.editedText else { return }
		CurrentUser.shared.resetPassword(name: userName, regCode: regCode, newPassword: newPassword) {}
	}
	
	func readCodeOfConductAction() {
		let storyboard = UIStoryboard(name: "Main", bundle: nil)
		if let textFileVC = storyboard.instantiateViewController(withIdentifier: "ServerTextFileDisplay") as? ServerTextFileViewController {
			textFileVC.fileToLoad = "codeofconduct"
			viewController?.present(textFileVC, animated: true, completion: nil)
		}
	}
		
}

