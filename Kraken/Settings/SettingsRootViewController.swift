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

class SettingsRootViewController: BaseCollectionViewController {
	let dataSource = FilteringDataSource()

    override func viewDidLoad() {
        super.viewDidLoad()
		title = "Settings"

  		dataSource.register(with: collectionView)
		let settingsSection = dataSource.appendSection(named: "settingsSection")
		let networkInfoCell = settingsSection.append(cell: SettingsInfoCellModel("Network"))
		NetworkGovernor.shared.tell(self, when: "connectionState") { observer, observed in
			networkInfoCell.labelText = observer.getCurrentWifiDescriptionString()
		}?.schedule()
		settingsSection.append(ServerAddressEditCellModel("Server URL"))
		settingsSection.append(ButtonCellModel(title: "Reset Server URL to Default", action: resetServerButtonHit, alignment: .center))
		
		var x = settingsSection.append(cell: SettingsInfoCellModel("Logged In User"))
		x.labelText = NSAttributedString(string: "None")
		x = settingsSection.append(cell: SettingsInfoCellModel("To Be Posted"))
		x.labelText = NSAttributedString(string: "Nothing to post")
		x = settingsSection.append(cell: SettingsInfoCellModel("Time Zone Info"))
		x.labelText = NSAttributedString(string: "Clocks Synchronized")
		x = settingsSection.append(cell: SettingsInfoCellModel("Preference Settings"))
		x.labelText = NSAttributedString(string: "lolwut?")
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
	
	

    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destination.
        // Pass the selected object to the new view controller.
    }
    */

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
	dynamic var titleText: String? { get set }
	dynamic var labelText: NSAttributedString? { get set }
}

@objc class SettingsInfoCellModel: BaseCellModel, SettingsInfoCellProtocol {	
	private static let validReuseIDs = [ "SettingsInfoCell" : SettingsInfoCell.self ]
	override class var validReuseIDDict: [String: BaseCollectionViewCell.Type ] { return validReuseIDs }

	dynamic var titleText: String?
	@objc dynamic var labelText: NSAttributedString?
	
	init(_ titleLabel: String) {
		titleText = titleLabel
		super.init(bindingWith: SettingsInfoCellProtocol.self)
	}
}

class SettingsInfoCell: BaseCollectionViewCell, SettingsInfoCellProtocol {
	@IBOutlet var titleLabel: UILabel!
	@IBOutlet var infoLabel: UILabel!
	
	private static let cellInfo = [ "SettingsInfoCell" : PrototypeCellInfo("SettingsInfoCell") ]
	override class var validReuseIDDict: [ String: PrototypeCellInfo ] { return cellInfo }

	var titleText: String? {
		didSet { titleLabel.text = titleText }
	}

	
	var labelText: NSAttributedString? {
		didSet { infoLabel.attributedText = labelText }
	}
}

