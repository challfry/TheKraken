//
//  Settings.swift
//  Kraken
//
//  Created by Chall Fry on 3/23/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import Foundation

@objc class Settings: NSObject, Codable {
	static let shared = Settings()
	
	@objc enum DisplayStyle: Int {
		case systemDefault = 0, normalMode, darkMode, deepSeaMode
	}
		
	// Need somewhere this can be referenced easily.
	static var v3Decoder: JSONDecoder {
		let v3 = JSONDecoder()
		v3.dateDecodingStrategy = .formatted(DateFormatter.iso8601Full)
		return v3
	}
	
	static var v3Encoder: JSONEncoder {
		let v3 = JSONEncoder()
		v3.dateEncodingStrategy = .formatted(DateFormatter.iso8601Full)
		return v3
	}
	
	// Settings that can't be changed once we initialize, but can be mutated for the next launch declared here.
	@objc dynamic public lazy var baseURL = settingsBaseURL
	@objc dynamic public lazy var apiVersion = 3
	
	// Each Settings property should get a copy of these 4 lines, modified appropriately
#if DEBUG
	@objc dynamic public var settingsBaseURL: URL {
	//	get { return getSetting(name: "baseURL", defaultValue: URL(string:"http://localhost:8081")!) }
	//	get { return getSetting(name: "baseURL", defaultValue: URL(string:"http://192.168.0.3:8081")!) }
		get { return getSetting(name: "baseURL", defaultValue: URL(string:"https://beta.twitarr.com")!) }
	//	get { return getSetting(name: "baseURL", defaultValue: URL(string:"https://twitarr.wookieefive.net")!) }
		set { setSetting(name: "baseURL", newValue: newValue) }
	}
#else
	@objc dynamic public var settingsBaseURL: URL {
		get { return getSetting(name: "baseURL", defaultValue: URL(string:"http://joco.hollandamerica.com")!) }
		set { setSetting(name: "baseURL", newValue: newValue) }
	}
#endif

	// Saves the last user to be 'active'. Unless they're logged in with multiple accounts, this will just 
	// be the user.
	public var activeUsername: String? {
		get { return getSetting(name: "activeUsername", defaultValue: nil) }
		set { setSetting(name: "activeUsername", newValue: newValue) }
	}
	
	// 
	@objc dynamic public var uiDisplayStyle: DisplayStyle {
		get { 
			if let newValue = Settings.DisplayStyle(rawValue: getSetting(name: "uiDisplayStyle", 
					defaultValue: Settings.DisplayStyle.normalMode.rawValue)) {
				return newValue	
			}
			return .normalMode
		}
		set { setSetting(name: "uiDisplayStyle", newValue: newValue.rawValue) }
	}

	// Chooses which viewfinder style to use
	@objc dynamic public var useFullscreenCameraViewfinder: Bool {
		get { return getSetting(name: "useFullscreenCameraViewfinder", defaultValue: true) }
		set { setSetting(name: "useFullscreenCameraViewfinder", newValue: newValue) }
	}
	
	// For interacting with the Calendar database via EKEventStore, we make a custom calendar named "JoCo Cruise 2022"
	// This saves the ID of that calendar.
	public var customCalendarForEvents: String? {
		get { return getSetting(name: "customCalendarForEvents", defaultValue: nil) }
		set { setSetting(name: "customCalendarForEvents", newValue: newValue) }
	}
	
	public var lastEventsUpdateTime: Date {
		get { return getSetting(name: "lastEventsUpdateTime", defaultValue: Date.distantPast) }
		set { setSetting(name: "lastEventsUpdateTime", newValue: newValue) }
	}
	
	public var seamailNotificationUUID: String {
		get { return getSetting(name: "seamailNotificationUUID", defaultValue: "") }
		set { setSetting(name: "seamailNotificationUUID", newValue: newValue) }
	}
	
	public var seamailNotificationBadgeCount: Int {
		get { return getSetting(name: "seamailNotificationBadgeCount", defaultValue: 0) }
		set { setSetting(name: "seamailNotificationBadgeCount", newValue: newValue) }
	}
	
	// The SSID of the onboard WIFI network. Received from the server.
	@objc dynamic public var onboardWifiNetowrkName: String {
		get { 
			let setting = getSetting(name: "onboardWifiNetowrkName", defaultValue: "")
			return setting
		}
		set { setSetting(name: "onboardWifiNetowrkName", newValue: newValue) }
	}
	
	// Whether to use direct connect or server-mediated VOIP.
	@objc dynamic public var useDirectVOIPConnnections: Bool {
		get { return getSetting(name: "useDirectVOIPConnnections", defaultValue: true) }
		set { setSetting(name: "useDirectVOIPConnnections", newValue: newValue) }
	}

// MARK: Debug Settings
	
	// Makes all network calls immediately fail. Sorta like airplane mode, except we'll still detect a newtork.
	@objc dynamic public var blockNetworkTraffic: Bool {
		get { return getSetting(name: "blockNetworkTraffic", defaultValue: false) }
		set { setSetting(name: "blockNetworkTraffic", newValue: newValue) }
	}

	// Makes PostOps sit in the queue--we don't try to send them to the server.
	@objc dynamic public var blockEmptyingPostOpsQueue: Bool {
		get { return getSetting(name: "blockEmptyingPostOpsQueue", defaultValue: false) }
		set { setSetting(name: "blockEmptyingPostOpsQueue", newValue: newValue) }
	}

	// Makes the schedule filters act as if the current time is mid-cruise 2019.
	@objc dynamic public var debugTimeWarpToCruiseWeek2019: Bool {
		get { return getSetting(name: "debugTimeWarpToCruiseWeek2019", defaultValue: false) }
		set { setSetting(name: "debugTimeWarpToCruiseWeek2019", newValue: newValue) }
	}
	
	// Makes local notifications for Schedule events fire 10 seconds after they're created, instead of 5 mins before
	// the event starts.
	@objc dynamic public var debugTestLocalNotificationsForEvents: Bool {
		get { return getSetting(name: "debugTestLocalNotificationsForEvents", defaultValue: false) }
		set { setSetting(name: "debugTestLocalNotificationsForEvents", newValue: newValue) }
	}


// MARK: Private stuff for Settings to do its work.
	private func getSetting<settingType>(name: String, defaultValue: settingType) -> settingType {
		if UserDefaults.standard.object(forKey: name) == nil {
			return defaultValue
		}
		switch settingType.self {
			// Bool auto-interprets missing values as "false", and converts things like String("yes") to true.
		case is Bool.Type: 
			return UserDefaults.standard.bool(forKey:name) as! settingType
			
			// Similarly, nonexistent defaults of type integer and float are interpreted as 0
		case is Int.Type: 
			return UserDefaults.standard.integer(forKey:name) as! settingType
		case is Float.Type: 
			return UserDefaults.standard.float(forKey:name) as! settingType
		case is Double.Type: 
			return UserDefaults.standard.double(forKey:name) as! settingType

		case is String.Type: 
			if let result = UserDefaults.standard.string(forKey:name) as! settingType? { return result }
		case is URL.Type: 
			if let result = UserDefaults.standard.url(forKey:name) as! settingType? { return result }
		case is Data.Type: 
			if let result = UserDefaults.standard.data(forKey:name) as! settingType? { return result }
		case is Array<String>.Type: 
			if let result = UserDefaults.standard.stringArray(forKey:name) as! settingType? { return result }
		case is Array<Any>.Type: 
			if let result = UserDefaults.standard.array(forKey:name) as! settingType? { return result }
		case is Dictionary<String, Any>.Type: 
			if let result = UserDefaults.standard.array(forKey:name) as! settingType? { return result }

		case is AnyObject.Type: 
			if let result = UserDefaults.standard.object(forKey:name) as! settingType? { return result }

		default: 
			if let result = UserDefaults.standard.object(forKey:name) as! settingType? { return result }
		}
		
		return defaultValue
	}	
	
	private func setSetting<settingType>(name: String, newValue: settingType) {
		switch settingType.self {
		case is Bool.Type: 
			UserDefaults.standard.set(newValue, forKey:name)
		case is Int.Type: 
			UserDefaults.standard.set(newValue, forKey:name)
		case is Float.Type: 
			UserDefaults.standard.set(newValue, forKey:name)
		case is Double.Type: 
			UserDefaults.standard.set(newValue, forKey:name)

		case is URL.Type: 
			let newURL = newValue as! URL
			UserDefaults.standard.set(newURL, forKey:name)
			
		case is AnyObject.Type: 
			UserDefaults.standard.set(newValue, forKey:name)

		default: 
			UserDefaults.standard.set(newValue, forKey:name)
		}
	}
	
	public func resetSetting(_ name: String) {
		UserDefaults.standard.removeObject(forKey: name)
	}

}

