//
//  LoggedInUserCell.swift
//  Kraken
//
//  Created by Chall Fry on 9/30/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit

@objc protocol LoggedInUserCellProtocol {
	dynamic var title: String? { get set }
	dynamic var isActive: Bool { get set }
	dynamic var role: LoggedInKrakenUser.UserRole { get set }
	dynamic var modelKrakenUser: LoggedInKrakenUser? { get set }
}


@objc class LoggedInUserCellModel: BaseCellModel, LoggedInUserCellProtocol {
	private static let validReuseIDs = [ "LoggedInUserCell" : LoggedInUserCell.self ]
	override class var validReuseIDDict: [String: BaseCollectionViewCell.Type ] { return validReuseIDs }

	dynamic var title: String?
	dynamic var isActive: Bool = false
	dynamic var role: LoggedInKrakenUser.UserRole = .user
	var showUserProfileAction: (() -> Void)?

	var modelKrakenUser: LoggedInKrakenUser? {
		didSet {
			if let user = modelKrakenUser {
				title = user.username
				isActive = user.username == CurrentUser.shared.loggedInUser?.username
				role = user.userRole
			}
			else {
				role = .user
				isActive = false
				title = ""
			}
		}
	}

	init(user: LoggedInKrakenUser, action: @escaping (DisclosureCellModel) -> Void) {
		modelKrakenUser = user
		super.init(bindingWith: LoggedInUserCellProtocol.self)
		title = user.username
		isActive = user.username == CurrentUser.shared.loggedInUser?.username
		role = user.userRole
	}
}


class LoggedInUserCell: BaseCollectionViewCell, LoggedInUserCellProtocol {
	@IBOutlet weak var usernameLabel: UILabel!
	@IBOutlet weak var adminModLabel: UILabel!
	@IBOutlet weak var currentlyActiveLabel: UILabel!
	@IBOutlet weak var logoutButton: UIButton!
	@IBOutlet weak var viewProfileButton: UIButton!
	@IBOutlet weak var activeInactiveButton: UIButton!
	
	private static let cellInfo = [ "LoggedInUserCell" : PrototypeCellInfo("LoggedInUserCell") ]
	override class var validReuseIDDict: [ String: PrototypeCellInfo ] { return cellInfo }
	
	var title: String? {
		didSet {
			usernameLabel.text = title
		}
	}
	
	var isActive: Bool = false {
		didSet {
			currentlyActiveLabel.text = isActive ? "Currently Active" : "Inactive"
			activeInactiveButton.setTitle(isActive ? "Deactivate" : "Activate", for: .normal)
			activeInactiveButton.isHidden = isActive
		}
	}
	
	var role: LoggedInKrakenUser.UserRole = .user {
		didSet {
			switch role {
				case .admin: adminModLabel.text = "Admin"
				case .tho: adminModLabel.text = "THO Acct"
				case .moderator: adminModLabel.text = "Mod"
				case .user: adminModLabel.text = ""
				case .muted: adminModLabel.text = "Muted"
				case .banned: adminModLabel.text = "Banned"
				case .loggedOut: adminModLabel.text = ""
			}
		}
	}
	
	var modelKrakenUser: LoggedInKrakenUser?
	
	@IBAction func logoutButtonTapped(_ sender: Any) {
		CurrentUser.shared.logoutUser(modelKrakenUser)
	}
	
	@IBAction func viewProfileButtonTapped(_ sender: Any) {
		if let model = cellModel as? LoggedInUserCellModel {
			model.showUserProfileAction?()
		}	
	}
	
	@IBAction func makeActiveUserTapped(_ sender: Any) {
		if let user = modelKrakenUser {
			CurrentUser.shared.setActiveUser(to: user)
		}	
	}
}
