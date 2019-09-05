//
//  RefreshTimers.swift
//  Kraken
//
//  Created by Chall Fry on 7/29/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit

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
			}
		}

	}
	
	class func appBackgrounded() {
		timeDisplayRefresher?.invalidate()
		timeDisplayRefresher = nil
	}
}
