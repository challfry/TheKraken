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
	var krakenInAppPushProvider = WebsocketNotifier(isInApp: true)		// Runs when app is fg and extension isn't running
	private let logger = Logger()
	private var providerDownTimer: Timer?
	
	override init() {
		super.init()
		krakenInAppPushProvider.incomingPhonecallHandler = { userInfo in
			PhonecallDataManager.shared.receivedIncomingCallNotification(userInfo: userInfo)
		}
	}
		
	func appStarted() {
#if !targetEnvironment(simulator)
		NEAppPushManager.loadAllFromPreferences { managers, error in 
			if let error = error {
				AppLog.error("Couldn't load push manager prefs: \(error)")
			}
			let manager = managers?.first
			self.saveSettings(for: manager)
			manager?.delegate = self
		}
		
		Settings.shared.tell(self, when: "onboardWifiNetowrkName") { observer, observed in
			observer.saveSettings(for: observer.pushManager)
		}
		CurrentUser.shared.tell(self, when: "loggedInUser.authKey") { observer, observed in
			observer.saveSettings(for: observer.pushManager)
		}
		self.tell(self, when: "pushManager.isActive") { observer, observed in
			if let pm = observed.pushManager {
				observer.logger.info("Extension push provider is \(pm.isActive ? "active" : "inactive")")
			}
			else {
				observer.logger.info("Extension push provider is nil.")
			}
			if observed.pushManager?.isActive == true {
				observer.checkStopInAppSocket()
				observer.providerDownTimer?.invalidate()
				observer.providerDownTimer = nil
			}
			else {
				// Start a 30 second timer. If the provider extension is still offline, enable the 
				// in-app provider. This should prevent extra socket cycling for very short Wifi unavailability.
				observer.providerDownTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { timer in 
					observer.checkStartInAppSocket()
				}
			}
		}
		
		// If at app launch the extension isn't running, start using in-app provider.
		providerDownTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { timer in 
			self.checkStartInAppSocket()
		}
#endif
	}
	
	func saveSettings(for manager: NEAppPushManager?) {
#if !targetEnvironment(simulator)
		let onboardSSID = Settings.shared.onboardWifiNetowrkName
		if !onboardSSID.isEmpty {
			let mgr = manager ?? NEAppPushManager()
			var websocketURLComponents = URLComponents()
			websocketURLComponents.scheme = Settings.shared.baseURL.scheme == "https" ? "wss" : "ws"
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
			mgr.isEnabled = true
			mgr.delegate = self
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
	
// MARK: - In-app pushProvider

	// At app launch, app fg, or after 30 secs of the app extension being offline, try starting the in-app websocket for notifications. 
	// Try to ensure the app extension's socket and our in-app socket are not running at the same time.
	func checkStartInAppSocket() {
		if pushManager?.isActive != true, krakenInAppPushProvider.startState == false {
			var websocketURLComponents = URLComponents()
			websocketURLComponents.scheme = Settings.shared.baseURL.scheme == "https" ? "wss" : "ws"
			websocketURLComponents.host = Settings.shared.baseURL.host
			websocketURLComponents.port = Settings.shared.baseURL.port
			websocketURLComponents.path = "/api/v3/notification/socket"
			let token = CurrentUser.shared.loggedInUser?.authKey
			krakenInAppPushProvider.updateConfig(serverURL: websocketURLComponents.url, token: token)
			krakenInAppPushProvider.start()
		}
	}
	
	func checkStopInAppSocket() {
		if krakenInAppPushProvider.startState == true {
			krakenInAppPushProvider.stop(with: .superceded) {  }
		}
	}
}

extension LocalPush: NEAppPushDelegate {
    func appPushManager(_ manager: NEAppPushManager, didReceiveIncomingCallWithUserInfo userInfo: [AnyHashable: Any] = [:]) {
        logger.log("LocalPush received an incoming call")
        PhonecallDataManager.shared.receivedIncomingCallNotification(userInfo: userInfo)
	}
}
