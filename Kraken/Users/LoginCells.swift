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

@objc protocol LoginHeaderCellProtocol {
	dynamic var labelText: String? { get set }
}

@objc class LoginHeaderCellModel: BaseCellModel, LoginHeaderCellProtocol {
	private static let validReuseIDs = [ "loginHeader" : NibAndClass(LoginHeaderCell.self, "LoginHeaderCell")]
	override class var validReuseIDDict: [String: NibAndClass ] { return validReuseIDs }

	dynamic var labelText: String? {
		didSet { shouldBeVisible = labelText != nil }
	}

	init() {
		super.init(bindingWith: LoginHeaderCellProtocol.self)
	}
}

class LoginHeaderCell: BaseCollectionViewCell, LoginHeaderCellProtocol {

	@IBOutlet var label: UILabel!

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
	}
	
	func calcButtonEnable() {
		buttonEnabled = dataSource.usernameCellModel.editedText?.isEmpty == false && 
					dataSource.passwordCellModel.editedText?.isEmpty == false &&
					!CurrentUser.shared.isChangingLoginState
	}
}


@objc class LoginDataSource: FilteringDataSource {
	// The Login cells show up when we need to log in before seeing content. The idea is that the login cells show up
	// *on the same screen* the content will show up on, via the magic of data sources. This text is to tell the user
	// why it is we're making them log in.
	var headerCellText: String? {
		didSet { headerCellModel.labelText = headerCellText }
	}
	var headerCellModel: LoginHeaderCellModel
	@objc dynamic var usernameCellModel: TextFieldCellModel
	@objc dynamic var passwordCellModel: TextFieldCellModel
	
	override init() {
		headerCellModel = LoginHeaderCellModel()
		headerCellModel.labelText = headerCellText
		usernameCellModel = TextFieldCellModel("Username:")
		passwordCellModel = TextFieldCellModel("Password:")
		passwordCellModel.isPassword = true
		super.init()
	}
		
	func register(with cv:UICollectionView) {
		if allSections.count == 0 {

			var section = self.appendSection(named: "login")
			section.append(headerCellModel)
			section.append(usernameCellModel)
			section.append(passwordCellModel)
			section.append(LoginButtonCellModel(title: "Login", action: startLoggingIn, ds: self))
			section.append(LoginStatusCellModel(cv: cv))
			section.append(ButtonCellModel(title: "Create a new account", action: createNewAccountAction, alignment: .left))
			section.append(ButtonCellModel(title: "I've, uh, forgotten my password.", action: forgotPasswordAction, alignment: .left))
			section.append(ButtonCellModel(title: "Read Code of Conduct", action: readCodeOfConductAction,  alignment: .left))
			
			section = self.appendSection(named: "createUser")
			section.append(LabelCellModel(buildNewRegistrationHeaderString()))
			section.append(ButtonCellModel(title: "Read Code of Conduct", action: readCodeOfConductAction,  alignment: .left))
			section.append(TextFieldCellModel("Registration Code:"))
			section.append(usernameCellModel)
			section.append(TextFieldCellModel("Display Name:"))
			section.append(LabelCellModel(NSAttributedString(string:"meh")))
			section.append(passwordCellModel)
			section.append(TextFieldCellModel("Confirm Password:"))
			section.append(LoginButtonCellModel(title: "Login", action: startAccountCreation, ds: self))
			section.append(LoginStatusCellModel(cv: cv))
			section.forceSectionVisible = false
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
    	if let userName = usernameCellModel.editedText, let password = passwordCellModel.editedText {
	    	CurrentUser.shared.loginUser(name: userName, password: password)
		}
	}
	
	func createNewAccountAction() {
		self.section(named:"login")?.forceSectionVisible = false
		self.section(named:"createUser")?.forceSectionVisible = true
	}
	
	func forgotPasswordAction() {
		
	}

	func readCodeOfConductAction() {
		
	}
	
	func buildNewRegistrationHeaderString() -> NSAttributedString {
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

