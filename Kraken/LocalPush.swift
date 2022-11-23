//
//  LocalPush.swift
//  Kraken
//
//  Created by Chall Fry on 2/9/22.
//  Copyright © 2022 Chall Fry. All rights reserved.
//

import Foundation
import NetworkExtension
import os

@objc class LocalPush: NSObject {
	static let shared = LocalPush()
	
	@objc dynamic var pushManager: NEAppPushManager?
	private let logger = Logger()
		
	func appStarted() {
#if !targetEnvironment(simulator)
		NEAppPushManager.loadAllFromPreferences { managers, error in 
			if let error = error {
				AppLog.error("Couldn't load push manager prefs: \(error)")
			}
			let manager = managers?.first
			self.saveSettings(for: manager)
		}
		
		Settings.shared.tell(self, when: "onboardWifiNetowrkName") { observer, observed in
			observer.saveSettings(for: observer.pushManager)
		}
		CurrentUser.shared.tell(self, when: "loggedInUser.authKey") { observer, observed in
			observer.saveSettings(for: observer.pushManager)
		}
#endif
	}
	
	func saveSettings(for manager: NEAppPushManager?) {
#if !targetEnvironment(simulator)
		let onboardSSID = Settings.shared.onboardWifiNetowrkName
		if !onboardSSID.isEmpty {
			let mgr = manager ?? NEAppPushManager()
			var websocketURLComponents = URLComponents()
			websocketURLComponents.scheme = "ws"
			websocketURLComponents.host = Settings.shared.baseURL.host
			websocketURLComponents.port = Settings.shared.baseURL.port
			websocketURLComponents.path = "/api/v3/notification/socket"
			let websocketURLString = websocketURLComponents.string ?? ""
			
			let token = CurrentUser.shared.loggedInUser?.authKey ?? ""
			
			if websocketURLString != mgr.providerConfiguration["twitarrURL"] as? String ||
					token != mgr.providerConfiguration["token"] as? String ||
					mgr.matchSSIDs != [onboardSSID] || mgr.isEnabled == false {
				mgr.localizedDescription = "App Extension for Background Server Communication"
				mgr.providerBundleIdentifier = "com.challfry-FQD.Kraken.KrakenLocalPushExtension"
//				mgr.delegate = self
				mgr.isEnabled = true
				mgr.providerConfiguration = [
					"twitarrURL": websocketURLString,
					"token": token
				]
				mgr.matchSSIDs = [onboardSSID]
			
				mgr.saveToPreferences { error in
					if let error = error {
						AppLog.error("Couldn't save push manager prefs: \(error)")
					}
					mgr.loadFromPreferences { error in 
						if let error = error {
							AppLog.error("Couldn't load push manager prefs: \(error)")
						}
					}
				}
			}
			pushManager = mgr
		}
		else if let mgr = manager {
			mgr.removeFromPreferences { error in
				if let error = error {
					AppLog.error("Couldn't save push manager prefs: \(error)")
				}
			}
			pushManager = nil
		}
#endif
	}
}

//extension LocalPush: NEAppPushDelegate {
//    func appPushManager(_ manager: NEAppPushManager, didReceiveIncomingCallWithUserInfo userInfo: [AnyHashable: Any] = [:]) {
//        logger.log("LocalPush received an incoming call?? This should not happen.")
//	}
//}
