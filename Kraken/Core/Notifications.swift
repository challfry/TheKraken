//
//  Notifications.swift
//  Kraken
//
//  Created by Chall Fry on 9/4/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit
import UserNotifications

class Notifications: NSObject, UNUserNotificationCenterDelegate {
	static let shared = Notifications()
	
	func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, 
			withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
		completionHandler([.sound, .alert])
	}

	func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, 
			withCompletionHandler completionHandler: @escaping () -> Void) {
		if let eventID = response.notification.request.content.userInfo["eventID"] {
			RootTabBarViewController.shared?.globalNavigateTo(packet: GlobalNavPacket(tab: .events, arguments: ["eventID" : eventID]))
		}
	}

	class func appForegrounded() {
		let center = UNUserNotificationCenter.current()
		center.getDeliveredNotifications { notifications in
			// Remove older notifications; keep ones that are within 10 minutes of delivery (during this time,
			// people may still be getting to the event the notification is reminding them of).
			let oldNotifications = notifications.compactMap { notification in 
				notification.date < Date() - 60 * 10 ? notification.request.identifier : nil
			}

			center.removeDeliveredNotifications(withIdentifiers: oldNotifications)
		}
	}
}
