//
//  RefreshTimers.swift
//  Kraken
//
//  Created by Chall Fry on 7/29/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit

class ServerUpdater : NSObject {

	static var updateActions: [ServerUpdater] = [
			ServerTimeUpdater.shared,
			ValidSectionUpdater.shared
	]
	
	func updateMethod() {}
	var minimumUpdateInterval: TimeInterval
	var lastUpdateTime: Date
	var refreshOnLogin: Bool
	var updateRunning: Bool
	
	init(_ interval: TimeInterval) {
		minimumUpdateInterval = interval
		refreshOnLogin = false
		lastUpdateTime = Date.distantPast
		updateRunning = false
	}
	
	func updateComplete(success: Bool) {
		updateRunning = false
		lastUpdateTime = Date()
	}
	
	// Checks each updater object, if we're over its minimum update interval, go refresh it.
	// TODO: Should put more stuff in here to handle update attempts that fail--generally try updating again soon,
	// but apply exponential backoff.
	class func runServerUpdates() {
		for updater in updateActions {
			if updater.lastUpdateTime < Date(timeIntervalSinceNow: 0 - updater.minimumUpdateInterval) {
				updater.updateRunning = true
				updater.updateMethod()
				
			}
		}
	}
	
}

class RefreshTimers: NSObject {
	static var timeDisplayRefresher: Timer?
	static let TenSecUpdateNotification = NSNotification.Name("Kraken10SecondUpdate")
	static let MinuteUpdateNotification = NSNotification.Name("KrakenMinuteUpdate")
	
	static var lastMinuteUpdate: Int = -1
	
	class func appForegrounded() {
		// 1. Post notification immediately on fg, to update all time fields before user sees them.
		NotificationCenter.default.post(Notification(name: RefreshTimers.TenSecUpdateNotification))

		// If the minute changed, send the minute notification as well
		let minute = Calendar.current.component(.minute, from: Date())
		if minute != lastMinuteUpdate {
			lastMinuteUpdate = minute
			NotificationCenter.default.post(Notification(name: RefreshTimers.MinuteUpdateNotification))
		}

		// 2. Start update timer, which refreshes all the time fields every 10 seconds.
		timeDisplayRefresher = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { timer in
			NotificationCenter.default.post(Notification(name: RefreshTimers.TenSecUpdateNotification))
			
			// If the minute changed, send the minute notification as well
			let minute = Calendar.current.component(.minute, from: Date())
			if minute != lastMinuteUpdate {
				lastMinuteUpdate = minute
				NotificationCenter.default.post(Notification(name: RefreshTimers.MinuteUpdateNotification))
				
				// One of the things I really hate about NSNotifications is that you can't inspect them to see who's signed
				// up to receive the notification. So, for 'global' clients that can be put here directly instead of 
				// registering for the notification, I'm putting them here. Because it's debuggable this way.
				ServerUpdater.runServerUpdates()
			}
		}
		
		// Run these things immediately on foreground.
		ServerUpdater.runServerUpdates()
	}
	
	class func appBackgrounded() {
		timeDisplayRefresher?.invalidate()
		timeDisplayRefresher = nil
	}
		
}

// Stuff to do on timers:
//		Get server time
//		Get announcements? 			/api/v2/announcements
//		Get alerts					/api/v2/alerts
//		Valid sections (/api/v2/admin/sections
// 		Refresh content on current tab? 
//			Okay. Each VC gets a 'refresh' thingy, called once a minute by baseVC?

