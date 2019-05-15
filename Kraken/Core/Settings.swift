//
//  Settings.swift
//  Kraken
//
//  Created by Chall Fry on 3/23/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import Foundation

class Settings: NSObject, Codable {
	static let shared = Settings()
	
	// Each Settings property should get a copy of these 4 lines, modified appropriately
	public var baseURL: URL {
		get { return getSetting(name: "baseURL", defaultValue: URL(string:"http://127.0.0.1:3000")!) }
		set { setSetting(name: "baseURL", newValue: newValue) }
	}

	public var lastSeamailCheckTime: Date {
		get { return getSetting(name: "lastSeamailCheckTime", defaultValue: Date(timeIntervalSince1970: 0)) }
		set { setSetting(name: "lastSeamailCheckTime", newValue: newValue) }
	}
	
	private func getSetting<settingType>(name: String, defaultValue:settingType) -> settingType {
		switch settingType.self {
			// Bool auto-interprets missing values as "false"
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

