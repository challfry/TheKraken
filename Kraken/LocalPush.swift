//
//  LocalPush.swift
//  Kraken
//
//  Created by Chall Fry on 2/9/22.
//  Copyright © 2022 Chall Fry. All rights reserved.
//

import Foundation
import NetworkExtension

class LocalPush: NSObject {
	static let shared = LocalPush()
	
	private var pushManager: NEAppPushManager?
	
	override init() {
		
	}
	
	func appStarted() {
		NEAppPushManager.loadAllFromPreferences { managers, error in 
			if let error = error {
				AppLog.error("Couldn't load push manager prefs: \(error)")
			}
			let manager = managers?.first ?? NEAppPushManager()
			self.saveSettings(for: manager)
		}
	}
	
	func saveSettings(for mgr: NEAppPushManager) {
		mgr.localizedDescription = "App Extension for Background Server Communication"
        mgr.providerBundleIdentifier = "com.challfry-FQD.Kraken.KrakenLocalPushExtension"
        mgr.isEnabled = true
        mgr.providerConfiguration = [
            "host": "ws://192.168.0.19:8081/api/v3/notification/socket"
        ]
		mgr.matchSSIDs = ["4045Stanton"]
	
		mgr.saveToPreferences { error in
			if let error = error {
				AppLog.error("Couldn't save push manager prefs: \(error)")
			}
		}
		pushManager = mgr
	}
}
