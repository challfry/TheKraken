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
	
	// This gets called when a notification is *delivered* while the app is running in the foreground.
	// The completion handler argument lets us choose how to show the notification to the user. 
	// If it's shown to the user (over our app's UI--we're in the FG) and the user taps it, the didReceive response: call
	// will get called.
	func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, 
			withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
		processNotifications([notification])
		completionHandler([.sound, .banner])
	}

	// Called when the user taps a notification, whether the notification is displayed while the app running or not.
	func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, 
			withCompletionHandler completionHandler: @escaping () -> Void) {
		
		// Nav to the Events view, show the event that's starting soon
		if let eventID = response.notification.request.content.userInfo["eventID"] {
			ContainerViewController.shared?.globalNavigateTo(packet: GlobalNavPacket(column: 0, tab: .events, 
					arguments: ["eventID" : eventID, "response" : response]))
			if let eventIDString = eventID as? String {
				EventsDataManager.shared.markNotificationCompleted(eventIDString)
			}
		}
		else if let seamailThreadID = response.notification.request.content.userInfo["Seamail"] {
			ContainerViewController.shared?.globalNavigateTo(packet: GlobalNavPacket(column: 0, tab: .seamail, 
					arguments: ["thread" : seamailThreadID, "response" : response]))
			let notificationUUID = response.notification.request.identifier
			SeamailDataManager.shared.markNotificationCompleted(notificationUUID)
		}
		else if let announcement = response.notification.request.content.userInfo["Announcement"] {
			ContainerViewController.shared?.globalNavigateTo(packet: GlobalNavPacket(column: 0, tab: .daily, 
					arguments: ["Announcement" : announcement]))
		}
		completionHandler()
	}

	class func appForegrounded() {
		let center = UNUserNotificationCenter.current()
		center.getDeliveredNotifications { notifications in
			Notifications.shared.processNotifications(notifications)
			// Remove older notifications; keep ones that are within 10 minutes of delivery (during this time,
			// people may still be getting to the event the notification is reminding them of).
			let oldNotifications = notifications.compactMap { notification in 
				notification.date < Date() - 60 * 10 ? notification.request.identifier : nil
			}

			center.removeDeliveredNotifications(withIdentifiers: oldNotifications)
		}
	}
	
	func processNotifications(_ notifications: [UNNotification]) {
		notifications.forEach { notification in
			// Load a thread if there's a new message.
			if let seamailIDStr = notification.request.content.userInfo["Seamail"] as? String, let seamailID = UUID(uuidString: seamailIDStr) {
				SeamailDataManager.shared.updateSeamailWithID(threadID: seamailID)
			}
			else if let _ = notification.request.content.userInfo["Announcement"] {
				AnnouncementDataManager.shared.updateAnnouncements()
			}
		}
		
	}
}
