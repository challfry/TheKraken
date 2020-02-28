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

	// This is for local notifications, which are basically timers.
	func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, 
			withCompletionHandler completionHandler: @escaping () -> Void) {
		
		// Nav to the Events view, show the event that's starting soon
		if let eventID = response.notification.request.content.userInfo["eventID"] {
			ContainerViewController.shared?.globalNavigateTo(packet: GlobalNavPacket(column: 0, tab: .events, 
					arguments: ["eventID" : eventID, "response" : response]))
			if let eventIDString = eventID as? String {
				EventsDataManager.shared.markNotificationCompleted(eventIDString)
			}
			completionHandler()
		}
		else if let seamailThreadID = response.notification.request.content.userInfo["Seamail"] {
			ContainerViewController.shared?.globalNavigateTo(packet: GlobalNavPacket(column: 0, tab: .seamail, 
					arguments: ["thread" : seamailThreadID, "response" : response]))
			let notificationUUID = response.notification.request.identifier
			SeamailDataManager.shared.markNotificationCompleted(notificationUUID)
			
			completionHandler()
		}
		else if let announcement = response.notification.request.content.userInfo["Announcement"] {
			ContainerViewController.shared?.globalNavigateTo(packet: GlobalNavPacket(column: 0, tab: .daily, 
					arguments: ["Announcement" : announcement]))
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
