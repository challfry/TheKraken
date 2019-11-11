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

		PostOperationDataManager.shared.tell(self, when: "operationsWithErrorsCount") { observer, observed in
			if observed.operationsWithErrorsCount > 0 {
				observer.navigationController?.tabBarItem.badgeColor = UIColor.red
				observer.navigationController?.tabBarItem.badgeValue = "\(observed.operationsWithErrorsCount)"
			}
			else {
				observer.navigationController?.tabBarItem.badgeValue = nil
			}
        }?.execute()        

  		dataSource.register(with: collectionView, viewController: self)
  		dataSource.viewController = self
//		let settingsSection = dataSource.appendFilteringSegment(named: "settingsSection")
		
		// Network Info
		let networkInfoSection = dataSource.appendFilteringSegment(named: "networkInfo")
		let networkInfoCell = networkInfoSection.append(cell: SettingsInfoCellModel("Network"))
		NetworkGovernor.shared.tell(self, when: "connectionState") { observer, observed in
			networkInfoCell.labelText = observer.getCurrentWifiDescriptionString()
		}?.schedule()
		networkInfoSection.append(ServerAddressEditCellModel("Server URL"))
		let buttonCell = ButtonCellModel(alignment: .center)
		buttonCell.setupButton(1, title: "Reset Server URL to Default", action: resetServerButtonHit)
		networkInfoSection.append(buttonCell)
		
		// Login State, login/out
		let loginInfoSection = dataSource.appendFilteringSegment(named: "LoginInfo")
		CurrentUser.shared.tell(self, when: ["credentialedUsers", "loggedInUser"]) { observer, observed in 
			loginInfoSection.allCellModels.removeAllObjects()
			loginInfoSection.append(cell: LoginInfoCellModel())
			let userArray = CurrentUser.shared.credentialedUsers.sorted(by: { $0.username < $1.username } )
			for user in userArray {
				let cell = LoggedInUserCellModel(user: user, action: weakify(self, SettingsRootViewController.userButtonTapped))
				cell.showUserProfileAction = { [weak self] in
					self?.performSegue(withIdentifier: "showUserProfile", sender: user)
				}
				loginInfoSection.append(cell)
			}
			loginInfoSection.append(cell: SettingsLoginButtonCellModel(action: weakify(self, type(of: self).loginButtonTapped)))
//			settingsSection.append(cell: LoginAdminInfoCellModel())
		}?.execute()
		

		// POST actions waiting to be delivered to the server
		let postActionsSection = dataSource.appendFilteringSegment(named: "postActions")
		let delayedPostInfo = postActionsSection.append(cell: SettingsInfoCellModel("To Be Posted"))
		delayedPostInfo.labelText = NSAttributedString(string: "Changes you've made, waiting to be sent to the Twitarr server.")
		let delayedPostDisclosure = postActionsSection.append(cell: DelayedPostDisclosureCellModel())
		delayedPostDisclosure.viewController = self

		// Time Zone section
		let timezoneSection = dataSource.appendFilteringSegment(named: "Time Zone")
		timezoneSection.append(cell: TimeZoneHeaderCellModel())
		let timeZoneCell = TimeZoneInfoCellModel()
		timezoneSection.append(cell: timeZoneCell)
		let gmtTimeCell = GMTTimeInfoCellModel()
		timezoneSection.append(cell: gmtTimeCell)
		
		
		// Preferences
		let prefsSection = dataSource.appendFilteringSegment(named: "App Prefs")
		let prefsHeaderCell = prefsSection.append(cell: SettingsInfoCellModel("Preference Settings"))
		prefsHeaderCell.labelText = NSAttributedString(string: "App-wide settings")
		prefsSection.append(cell: BlockNetworkSwitchCellModel())
		prefsSection.append(cell: DelayPostsSwitchCellModel())
		prefsSection.append(cell: FullScreenCameraSwitchCellModel())
		prefsSection.append(cell: DisplayStyleCell())
		
		// Debug Settings
		let debugSettingsSection = dataSource.appendFilteringSegment(named: "Debug Prefs")
		let debugHeaderCell = debugSettingsSection.append(cell: SettingsInfoCellModel("Debug Settings"))
		debugHeaderCell.labelText = NSAttributedString(string: "Support for Debugging and Testing")
		debugSettingsSection.append(cell: DebugTimeWarpToCruiseWeek2019CellModel())
		debugSettingsSection.append(cell: DebugTestLocalNotificationsForEventsCellModel())
		
		let clearCacheCell = debugSettingsSection.append(cell: SettingsInfoCellModel("Clear Cache"))
		clearCacheCell.labelText = NSAttributedString(string: "Clear Cache")
		
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
		// Show login controller
		performSegue(withIdentifier: "ShowLogin", sender: self)
	}
	
	func userButtonTapped(_ cell: DisclosureCellModel) {
//		performSegue(withIdentifier: "showUserProfile", sender: loginCell.modelKrakenUser)
	}

    // MARK: Navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
    	switch segue.identifier {
//		case "PostOperations":
//			if let destVC = segue.destination as? SettingsTasksViewController, 
//					let controller = sender as? NSFetchedResultsController<PostOperation> {
//				destVC.controller = controller
//			}
		case "showUserProfile":
			if let destVC = segue.destination as? UserProfileViewController, 
					let user = sender as? LoggedInKrakenUser {
				destVC.modelUserName = user.username
			}
		default: break 
    	}
    }

	// This fn has to be here so that the login unwind stops here.
	@IBAction func dismissingLoginModal(_ segue: UIStoryboardSegue) {
	}	

	// This is the unwind segue handler for the profile edit VC
	@IBAction func dismissingProfileEditVC(segue: UIStoryboardSegue) {
	}

}

// MARK: -
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
		super.init("Logged In User(s)")
		
		CurrentUser.shared.tell(self, when: ["loggedInUser", "credentialedUsers"]) { observer, observed in
			if observed.credentialedUsers.count > 1 {
				var labelStr = "\(observed.credentialedUsers.count) users logged in."
				if let currentUser = observed.loggedInUser {
					labelStr.append(" Active User: \(currentUser.username).")
				}
				else {
					labelStr.append(" However, none of them are active, so the app is acting as if you're logged out.")
				}
				observer.labelText = NSAttributedString(string: labelStr)
			}
			else if let currentUser = observed.loggedInUser {
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
		
		CurrentUser.shared.tell(self, when:"loggedInUser.userRole") { observer, observed in
			var infoString: String
			var showCell = true
			switch observed.loggedInUser?.userRole {
				case .admin: infoString = "This is an admin account, although Kraken doesn't support many admin features."
				case .tho: infoString = "This is The Home Office special account"
				case .moderator: infoString = "This is a moderator account, although Kraken doesn't support many moderator features."
				case .user: infoString = ""; showCell = false
				case .muted: infoString = "This account has been temporarily muted"
				case .banned: infoString = "This account has been banned"
				case .loggedOut, .none: infoString = ""; showCell = false
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
			observer.button1Text = observed.loggedInUser == nil ? "Login" : "Login Additional User"
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
				case 0: observer.title = "No changes waiting."
				case 1: observer.title = "1 item to post"
				default: observer.title = "\(observed.pendingOperationCount) items to post"
			}
        }?.execute()        

		PostOperationDataManager.shared.tell(self, when: "operationsWithErrorsCount") { observer, observed in
			switch observed.operationsWithErrorsCount {
				case 0: observer.errorString = nil
				case 1: observer.errorString = "Server rejected 1 change"
				default: observer.errorString = "Server rejected \(observed.operationsWithErrorsCount) changes"
			}
        }?.execute()        
	}
	
	override func cellTapped() {
		if PostOperationDataManager.shared.pendingOperationCount > 0 {
			viewController?.performSegue(withIdentifier: "PostOperations", sender: self)
		}
	}
}

@objc class TimeZoneHeaderCellModel: SettingsInfoCellModel {
	init() {
		super.init("Time Zone Info")
		labelText = NSAttributedString(string: "Timeline is Synchronized.")
		
		ServerTimeUpdater.shared.tell(self, when: ["serverTimezone", "deviceTimezone", "timeZoneOffset",
				"deviceTimeOffset"]) { observer, observed in
			var timeHeaderString: NSAttributedString
			if observed.serverTimezone == nil {
				timeHeaderString = NSAttributedString(string: "Timeline state is: Unknown.")
			}
			else if observed.deviceTimezone == observed.serverTimezone && abs(observed.deviceTimeOffset) < 300 {
				timeHeaderString = NSAttributedString(string: "Timeline is Synchronized.")
			}
			else {
				timeHeaderString = NSAttributedString(string: "Timeline is out of Sync.", attributes: [ .foregroundColor : UIColor.red])
			}
			observer.labelText = timeHeaderString
		}?.execute()
	}
}

@objc class TimeZoneInfoCellModel: LabelCellModel {

	init() {
		super.init("")
		
		ServerTimeUpdater.shared.tell(self, when: ["serverTimezone", "deviceTimezone", "timeZoneOffset",
				"deviceTimeOffset"]) { observer, observed in
			if observed.serverTimezone == nil {
				observer.labelText = NSAttributedString(string: "We don't yet know what time the server thinks it is.")
			}
			else if observed.deviceTimezone == observed.serverTimezone {
				observer.labelText = NSAttributedString(string: "Device and Server are using the same time zone.")
			}
			else if observed.serverTimezoneOffset == observed.deviceTimezoneOffset {
				if let deviceTZ = TimeZone.current.abbreviation(), let serverTZ = observed.serverTimezone?.abbreviation() {
					self.labelText = NSAttributedString(string: 
							"""
							Time zones don't match, but they have the same offset from GMT. Local time is \(deviceTZ), server time is \(serverTZ).
							
							You should still set your device time zone to match the server time zone. 
							""")
				}
				else {
					self.labelText = NSAttributedString(string: 
							"""
							Time zones don't match, but they have the same offset from GMT.
							
							You should still set your device time zone to match the server time zone. 
							""")
				}
			}
			else {
				if let deviceTZ = TimeZone.current.abbreviation(), let serverTZ = observed.serverTimezone?.abbreviation() {
					observer.labelText = NSAttributedString(string: """
							Time zones don't match. Device is set to \(deviceTZ), server time zone is \(serverTZ).
							""")
				}
				else {
					observer.labelText = NSAttributedString(string: """
							Device and Server time zones don't match.
							""")
				}
			}
		}?.execute()
	}
	
}

@objc class GMTTimeInfoCellModel: LabelCellModel {

	init() {
		super.init("")
		
		ServerTimeUpdater.shared.tell(self, when: ["serverTimezone", "deviceTimezone", "timeZoneOffset",
				"deviceTimeOffset"]) { observer, observed in
			if observed.serverTimezone == nil {
				observer.shouldBeVisible = false
				return
			}
			observer.shouldBeVisible = true
			
			switch observed.deviceTimeOffset {
			case -10...10:	observer.labelText = NSAttributedString(string: "Device and Server are experiencing time synchronization.")
			case -60...60:	observer.labelText = NSAttributedString(string: "Device time is within a minute of Server time.")
			case -300...300: observer.labelText = NSAttributedString(string: "Device Time is close to Server Time--within a few minutes.")
			case 300...3300: observer.labelText = NSAttributedString(string: "Device Time is way ahead of Server Time--like \(observed.deviceTimeOffset / 60) minutes ahead.")
			case -3300...(-300): observer.labelText = NSAttributedString(string: "Device Time is way behind Server Time--like \(abs(observed.deviceTimeOffset) / 60) minutes behind.")
			case 3300...3900: 
				if abs(Int(observed.deviceTimeOffset) - observed.timeZoneOffset) < 300 {
					observer.labelText = NSAttributedString(string: """
							Your device may be showing the same time as wall clocks on the ship, but when it's in a different time zone it means all the events in the Calendar show the wrong time.
							
							You need to ensure your device is in the same time zone as the server--just setting the clock time to be the same doesn't entirely work.
							""")
				}
				else {
					observer.labelText = NSAttributedString(string: "UTC Device Time is an hour ahead of Server Time. You need to ensure your device is in the same time zone as the server--just setting the clock time to be the same doesn't entirely work.")
				}
			case -3900...(-3300): 
				if abs(Int(observed.deviceTimeOffset) - observed.timeZoneOffset) < 300 {
					observer.labelText = NSAttributedString(string: """
							Your device may be showing the same time as wall clocks on the ship, but when it's in a different time zone it means all the events in the Calendar show the wrong time.
							
							You need to ensure your device is in the same time zone as the server--just setting the clock time to be the same doesn't entirely work.
							""")
				}
				else {
					observer.labelText = NSAttributedString(string: "UTC Device Time is an hour behind Server Time. You need to ensure your device is in the same time zone as the server--just setting the clock time to be the same doesn't entirely work.")
				}
			case ...(-3900): observer.labelText = NSAttributedString(string: "Device Time (converted to UTC) is \(abs(observed.deviceTimeOffset) / 60) minutes behind UTC Server Time. You need to ensure your device is in the same timezone as the server--just setting the clock time to be the same doesn't entirely work.")
			case 3900...: observer.labelText = NSAttributedString(string: "Device Time (converted to UTC) is \(abs(observed.deviceTimeOffset) / 60) minutes ahead of UTC Server Time. You need to ensure your device is in the same timezone as the server--just setting the clock time to be the same doesn't entirely work.")
			default: observer.labelText = NSAttributedString(string: "")
			}
		}?.execute()
	}
	
}

// MARK: - Prefs Cells

@objc class DisplayStyleCell : SegmentCellModel {
	init() {
		super.init(titles: ["Normal", "Dark Mode", "Deep Sea Mode"])
		stateChanged = { 
			if let newStyle = Settings.DisplayStyle(rawValue: self.selectedSegment) {
				Settings.shared.uiDisplayStyle = newStyle
			}
		}
		selectedSegment = Settings.shared.uiDisplayStyle.rawValue
		cellTitle = "This sets the overall look of the app."
	}
}

@objc class FullScreenCameraSwitchCellModel : SwitchCellModel {
	init() {
		super.init(labelText: """
				This switch controls the camera viewfinder style.
				ON: uses the full screen to present the largest preview.
				OFF: Shows the cropping boundary of the final image.
				""")
		switchStateChanged = { 
			Settings.shared.useFullscreenCameraViewfinder = self.switchState
		}
		switchState = Settings.shared.useFullscreenCameraViewfinder
	}
}


// MARK: - Debug Cells
@objc class BlockNetworkSwitchCellModel: SwitchCellModel {
	init() {
		super.init(labelText: "Block all network traffic, for testing purposes. When on, all network calls will immediately fail.")
		switchStateChanged = { 
			Settings.shared.blockNetworkTraffic = self.switchState
		}
		switchState = Settings.shared.blockNetworkTraffic
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

@objc class DebugTimeWarpToCruiseWeek2019CellModel: SwitchCellModel {
	init() {
		super.init(labelText: "Makes Schedule filters act as if we're in the middle of cruise week 2019. Exact time follows time of week.")
		switchStateChanged = { 
			Settings.shared.debugTimeWarpToCruiseWeek2019 = self.switchState
		}
		switchState = Settings.shared.debugTimeWarpToCruiseWeek2019
	}
}

@objc class DebugTestLocalNotificationsForEventsCellModel: SwitchCellModel {
	init() {
		super.init(labelText: "Makes Local Notifications for Events fire 10 seconds after creation, instead of 5 mins before the event starts.")
		switchStateChanged = { 
			Settings.shared.debugTestLocalNotificationsForEvents = self.switchState
		}
		switchState = Settings.shared.debugTestLocalNotificationsForEvents
	}
}

