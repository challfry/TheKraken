//
//  RefreshTimers.swift
//  Kraken
//
//  Created by Chall Fry on 7/29/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit
import BackgroundTasks

@objc class ServerUpdater : NSObject {

	static var updateActions: [ServerUpdater] = [
			ServerTimeUpdater.shared,
			ValidSectionUpdater.shared,
			AlertsUpdater.shared,
			DailyThemeUpdater.shared,
	]
	static var numActiveUpdaters: Int = 0
	static var allUpdatesComplete: (() -> Void)?
	
	func updateMethod() {}
	var minimumUpdateInterval: TimeInterval
	@objc dynamic var lastUpdateTime: Date
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
		ServerUpdater.numActiveUpdaters -= 1
//		RefreshLog.debug("Completed an update task. \(ServerUpdater.numActiveUpdaters) active.")
		
		// A bit of a hack. Although all the network processing will be complete when updateComplete() is called,
		// not all of the updaters carry through to their Core Data async processing. So, once everyone claims to be
		// done, give it a few seconds before calling allUpdatesComplete, as that call will make us stop being scheduled.
		if ServerUpdater.numActiveUpdaters == 0 {
			DispatchQueue.main.asyncAfter(deadline: .now() + DispatchTimeInterval.seconds(2)) {
				ServerUpdater.allUpdatesComplete?()
				ServerUpdater.allUpdatesComplete = nil
			}
		}
	}
	
	// Checks each updater object, if we're over its minimum update interval, go refresh it.
	// TODO: Should put more stuff in here to handle update attempts that fail--generally try updating again soon,
	// but apply exponential backoff.
	class func runServerUpdates() {
//		RefreshLog.debug("Starting runServerUpdates().")
		for updater in updateActions {
			// The boundary time is 5 secs minus the update interval so a refresher on a minute timer will run every minute,
			// instead of running every 2 mins perhaps half the time.
			if updater.lastUpdateTime < Date(timeIntervalSinceNow: 5.0 - updater.minimumUpdateInterval) {
				if !updater.updateRunning {
					updater.updateRunning = true
					ServerUpdater.numActiveUpdaters += 1
					updater.updateMethod()
				}
			}
		}
			
		// If we didn't run anything, most likely because no tasks are over their min interval, we're done.
		if ServerUpdater.numActiveUpdaters == 0 {
//			RefreshLog.debug("Bailing. Nothing to run.")
			ServerUpdater.allUpdatesComplete?()
			ServerUpdater.allUpdatesComplete = nil
		}
	}
	
}

class RefreshTimers: NSObject {
	static var timeDisplayRefresher: Timer?
	static let TenSecUpdateNotification = NSNotification.Name("Kraken10SecondUpdate")
	static let MinuteUpdateNotification = NSNotification.Name("KrakenMinuteUpdate")
	
	static var lastMinuteUpdate: Int = -1
	
	class func appLaunched() {
		if #available(iOS 13.0, *) {
			BGTaskScheduler.shared.register(forTaskWithIdentifier: "com.challfry-FQD.Kraken.refresh", using: nil) { task in
				// Schedule the next refresh; these chain
				RefreshTimers.scheduleAppRefresh()
				
				task.expirationHandler = { 
					RefreshLog.debug("EXPIRATION HANDLER FIRED.")
					NetworkGovernor.shared.cancelAllTasks()
					task.setTaskCompleted(success: false)
				}
				ServerUpdater.allUpdatesComplete = {
					task.setTaskCompleted(success: true)
					RefreshLog.debug("All updates complete. App Refresh task done.")
				}
				ServerUpdater.runServerUpdates()
			}
		}
		
		appForegrounded(isLaunch: true)
	}
		
	class func appForegrounded(isLaunch: Bool) {
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
//			print("10 second timer.")
			
			// If the minute changed, send the minute notification as well
			let minute = Calendar.current.component(.minute, from: Date())
			if minute != lastMinuteUpdate {
				lastMinuteUpdate = minute
				NotificationCenter.default.post(Notification(name: RefreshTimers.MinuteUpdateNotification))
//				print("minute timer.")
				
				// One of the things I really hate about NSNotifications is that you can't inspect them to see who's signed
				// up to receive the notification. So, for 'global' clients that can be put here directly instead of 
				// registering for the notification, I'm putting them here. Because it's debuggable this way.
				ServerUpdater.runServerUpdates()
			}
		}
		
		// Run these things immediately on foreground.
		if !isLaunch {
			ServerUpdater.runServerUpdates()
		}
	}
	
	class func appBackgrounded() {
		timeDisplayRefresher?.invalidate()
		timeDisplayRefresher = nil
		
		RefreshTimers.scheduleAppRefresh()
	}
	
	class func scheduleAppRefresh() {
		if #available(iOS 13.0, *) {
			let request = BGAppRefreshTaskRequest(identifier: "com.challfry-FQD.Kraken.refresh")
			request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60) 
        
			do {
				try BGTaskScheduler.shared.submit(request)
				RefreshLog.debug("Scheduled BG Refresh.")
				
				// e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"com.challfry-FQD.Kraken.refresh"]
//				RefreshLog.debug("Eval debugger line here.")
			} catch {
				RefreshLog.error("Could not schedule app refresh: \(error)")
			}
		}
    }
    
}

// Stuff to do on timers:
//	x	Get server time
//	x	Get announcements? 			/api/v2/announcements
//		Get alerts					/api/v2/alerts
//		Valid sections (/api/v2/admin/sections
// 		Refresh content on current tab? 
//			Okay. Each VC gets a 'refresh' thingy, called once a minute by baseVC?
//		GET /api/v2/event/mine/:epoch -- gets favorited events on a particular day, to sync with other devices.
