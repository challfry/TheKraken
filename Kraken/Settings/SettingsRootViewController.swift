//
//  SettingsRootViewController.swift
//  Kraken
//
//  Created by Chall Fry on 5/23/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit
import SystemConfiguration
import SystemConfiguration.CaptiveNetwork
import CoreData

class SettingsRootViewController: BaseCollectionViewController {
	let dataSource = KrakenDataSource()

    override func viewDidLoad() {
        super.viewDidLoad()
		title = "Settings"

  		dataSource.register(with: collectionView, viewController: self)
  		dataSource.viewController = self
		let settingsSection = dataSource.appendFilteringSegment(named: "settingsSection")
		
		// Network Info
		let networkInfoCell = settingsSection.append(cell: SettingsInfoCellModel("Network"))
		NetworkGovernor.shared.tell(self, when: "connectionState") { observer, observed in
			networkInfoCell.labelText = observer.getCurrentWifiDescriptionString()
		}?.schedule()
		settingsSection.append(ServerAddressEditCellModel("Server URL"))
		let buttonCell = ButtonCellModel(alignment: .center)
		buttonCell.setupButton(1, title: "Reset Server URL to Default", action: resetServerButtonHit)
		settingsSection.append(buttonCell)
		
		// Login State, login/out
		settingsSection.append(cell: LoginInfoCellModel())
		settingsSection.append(cell: LoginAdminInfoCellModel())
		settingsSection.append(cell: SettingsLoginButtonCellModel(action: loginButtonTapped))

		// POST actions waiting to be delivered to the server
		let delayedPostInfo = settingsSection.append(cell: SettingsInfoCellModel("To Be Posted"))
		delayedPostInfo.labelText = NSAttributedString(string: "Changes you've made, waiting to be sent to the Twitarr server.")
		let delayedPostDisclosure = settingsSection.append(cell: DelayedPostDisclosureCellModel())
		delayedPostDisclosure.viewController = self


		var x = settingsSection.append(cell: SettingsInfoCellModel("Time Zone Info"))
		x.labelText = NSAttributedString(string: "Clocks Synchronized")
		
		// Preferences
		let prefsHeaderCell = settingsSection.append(cell: SettingsInfoCellModel("Preference Settings"))
		prefsHeaderCell.labelText = NSAttributedString(string: "App-wide settings")
		settingsSection.append(cell: DelayPostsSwitchCellModel())
		
		x = settingsSection.append(cell: SettingsInfoCellModel("Clear Cache"))
		x.labelText = NSAttributedString(string: "Button")
		
		dataSource.enableAnimations	= true
    }
    
	func getCurrentWifiName() -> String? {
		#if targetEnvironment(simulator)
			return "Simulator-- No Wifi APIs"
		#else
			if let ifs = CFBridgingRetain( CNCopySupportedInterfaces()) as? [String],
				let ifName = ifs.first as CFString?,
				let info = CFBridgingRetain( CNCopyCurrentNetworkInfo((ifName))) as? [AnyHashable: Any] {
				return info["SSID"] as? String 
			}
			return nil
		#endif
	}
	
	func getCurrentWifiDescriptionString() -> NSMutableAttributedString {
		let resultString: NSMutableAttributedString
		if let wifiName = getCurrentWifiName() {
			resultString = NSMutableAttributedString(string:"Connected to wifi network:", attributes: nil)
			resultString.append(NSMutableAttributedString(string:wifiName, attributes: nil))
		}
		else {
			resultString = NSMutableAttributedString(string:"Not connected to wifi", attributes: nil)
		}
		
		if NetworkGovernor.shared.connectionState == .canConnect {
			resultString.append(NSMutableAttributedString(string: "\n\nServer Connection looks good", attributes: nil))
		}
		else {
			resultString.append(NSMutableAttributedString(string: "\n\nCan't talk to the server right now.", attributes: nil))
		}
		
		return resultString
	}
	
	func resetServerButtonHit() {
		Settings.shared.resetSetting("baseURL")
		let defaultValue = Settings.shared.settingsBaseURL
		Settings.shared.settingsBaseURL = URL(string:"http://cnn.com")!
		Settings.shared.settingsBaseURL = defaultValue
	}
	
	func loginButtonTapped() {
		if CurrentUser.shared.isLoggedIn() {
			// TODO: Should warn user if they logout while offline, they can't log in until
			// they return to the ship. If they have pending posts, that dialog should also
			// mention posts won't be sent until they're logged back in.
		
			CurrentUser.shared.logoutUser()
		}
		else {
			// Show login controller
			performSegue(withIdentifier: "ShowLogin", sender: self)
		}
	}
	
    // MARK: - Navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
    	switch segue.identifier {
//		case "PostOperations":
//			if let destVC = segue.destination as? SettingsTasksViewController, 
//					let controller = sender as? NSFetchedResultsController<PostOperation> {
//				destVC.controller = controller
//			}
		default: break 
    	}
    }

	// This fn has to be here so that the login unwind stops here.
	@IBAction func dismissingLoginModal(_ segue: UIStoryboardSegue) {
	
	}	
}

@objc class ServerAddressEditCellModel: TextFieldCellModel {
	override var editedText: String? {
		didSet {
			if editedText != Settings.shared.baseURL.absoluteString {
				errorText = "You will have to restart the app to connect to the new server. Will continue to use \(Settings.shared.baseURL.absoluteString) until restart."
			}
			else {
				errorText = ""
			}
			if let textString = editedText, let validURL = URL(string:textString) {
				Settings.shared.settingsBaseURL = validURL
			}
		}
	}

	init(_ titleLabel: String) {
		super.init(titleLabel)
		
		Settings.shared.tell(self, when: "settingsBaseURL") { observer, observed in
			observer.fieldText = observed.settingsBaseURL.absoluteString
			observer.editedText = observer.fieldText
		}?.schedule()
	}
}

@objc protocol SettingsInfoCellProtocol {
	dynamic var taskIndex: Int { get set }
	dynamic var titleText: String? { get set }
	dynamic var labelText: NSAttributedString? { get set }
	dynamic var showActivitySpinner: Bool { get set }
	dynamic var activityText: String? { get set }
}

@objc class SettingsInfoCellModel: BaseCellModel, SettingsInfoCellProtocol {	
	private static let validReuseIDs = [ "SettingsInfoCell" : SettingsInfoCell.self ]
	override class var validReuseIDDict: [String: BaseCollectionViewCell.Type ] { return validReuseIDs }

	@objc dynamic var taskIndex: Int = 0
	@objc dynamic var titleText: String?
	@objc dynamic var labelText: NSAttributedString?
	@objc dynamic var showActivitySpinner: Bool = false
	@objc dynamic var activityText: String?

	init(_ titleLabel: String, taskIndex: Int = 0) {
		titleText = titleLabel
		self.taskIndex = taskIndex
		super.init(bindingWith: SettingsInfoCellProtocol.self)
	}
}

class SettingsInfoCell: BaseCollectionViewCell, SettingsInfoCellProtocol {
	@IBOutlet var titleLabel: UILabel!
	@IBOutlet var infoLabel: UILabel!
	@IBOutlet var activityView: UIView!
	@IBOutlet var activityLabel: UILabel!
	
	private static let cellInfo = [ "SettingsInfoCell" : PrototypeCellInfo("SettingsInfoCell") ]
	override class var validReuseIDDict: [ String: PrototypeCellInfo ] { return cellInfo }

	var taskIndex: Int = 0 {
		didSet { buildTitle() }
	}

	var titleText: String? {
		didSet { buildTitle() }
	}
	
	func buildTitle() {
		titleLabel.text = (taskIndex > 0 ? "\(taskIndex): " : "") + (titleText ?? "")
	}
	
	var labelText: NSAttributedString? {
		didSet { infoLabel.attributedText = labelText }
	}
	
	var showActivitySpinner: Bool = false {
		didSet { activityView.isHidden = !showActivitySpinner }
	}
	
	var activityText: String? {
		didSet { activityLabel.text = activityText }
	}
}



@objc class LoginInfoCellModel: SettingsInfoCellModel {
	init() {
		super.init("Logged In User")
		
		CurrentUser.shared.tell(self, when:"loggedInUser") { observer, observed in
			if let currentUser = observed.loggedInUser {
				observer.labelText = NSAttributedString(string: "Logged in as: \(currentUser.username)")
			}
			else {
				observer.labelText = NSAttributedString(string: "Not logged in.")
			}
		}?.schedule()
	}
}

@objc class LoginAdminInfoCellModel: LabelCellModel {
	init() {
		super.init("")
		
		CurrentUser.shared.tell(self, when:"userRole") { observer, observed in
			var infoString: String
			var showCell = true
			switch observed.userRole {
				case .admin: infoString = "This is an admin account, although Kraken doesn't support many admin features."
				case .tho: infoString = "This is The Home Office special account"
				case .moderator: infoString = "This is a moderator account, although Kraken doesn't support many moderator features."
				case .user: infoString = ""; showCell = false
				case .muted: infoString = "This account has been temporarily muted"
				case .banned: infoString = "This account has been banned"
				case .loggedOut: infoString = ""; showCell = false
			}

			// For Testing
	//		infoString = "This is a moderator account, although Kraken doesn't support many moderator features."
	//		observer.shouldBeVisible = true

			let centerStyle = NSMutableParagraphStyle()
			centerStyle.alignment = .center
			let warningAttrs: [NSAttributedString.Key : Any] = [ .font : UIFont.preferredFont(forTextStyle:.headline).withSize(17) as Any, 
					.foregroundColor : UIColor.red, .paragraphStyle : centerStyle ]
			observer.labelText = NSAttributedString(string: infoString, attributes:  warningAttrs)
			observer.shouldBeVisible = showCell
		}?.schedule()
	}
}


@objc class SettingsLoginButtonCellModel : ButtonCellModel {
	init(action: (() -> Void)?) {
		super.init(alignment: .center)
		setupButton(1, title: "Login", action: action)
		
		CurrentUser.shared.tell(self, when:"loggedInUser") { observer, observed in
//			observer.shouldBeVisible = observed.loggedInUser == nil
			observer.button1Text = observed.loggedInUser == nil ? "Login" : "Log Out"
		}?.schedule()
		
		CurrentUser.shared.tell(self, when:"isChangingLoginState") { observer, observed in
			observer.button1Enabled = !observed.isChangingLoginState
		}?.schedule()
	}
	
}

@objc class DelayedPostDisclosureCellModel : DisclosureCellModel, NSFetchedResultsControllerDelegate {
	var viewController: SettingsRootViewController?
	
	override init() {
		super.init()
		
		PostOperationDataManager.shared.tell(self, when: "pendingOperationCount") { observer, observed in
			switch observed.pendingOperationCount {
				case 0: observer.title = "No changes waiting to be sent to the server."
				case 1: observer.title = "1 item to post"
				default: observer.title = "\(observed.pendingOperationCount) items to post"
			}
        }?.execute()        
	}
	
	override func cellTapped() {
		if PostOperationDataManager.shared.pendingOperationCount > 0 {
			viewController?.performSegue(withIdentifier: "PostOperations", sender: self)
		}
	}
}

@objc class DelayPostsSwitchCellModel: SwitchCellModel {
	init() {
		super.init(labelText: "Don't send content changes to server. Content changes will be queued but not sent while this is on.")
		switchStateChanged = { 
			Settings.shared.blockEmptyingPostOpsQueue = self.switchState
		}
		switchState = Settings.shared.blockEmptyingPostOpsQueue
	}
	
}

