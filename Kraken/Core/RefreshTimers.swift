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

	class func appForegrounded() {
		// 1. Post notification immediately on fg, to update all time fields before user sees them.
		// 2. Start update timer, which refreshes all the time fields every 10 seconds.
		NotificationCenter.default.post(Notification(name: RefreshTimers.TenSecUpdateNotification))
		timeDisplayRefresher = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { timer in
			NotificationCenter.default.post(Notification(name: RefreshTimers.TenSecUpdateNotification))
		}

	}
	
	class func appBackgrounded() {
		timeDisplayRefresher?.invalidate()
		timeDisplayRefresher = nil
	}
}
