//
//  ServerTime.swift
//  Kraken
//
//  Created by Chall Fry on 9/12/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit

@objc class ServerTime : NSObject {
	static let shared = ServerTime()

	// Server Time
	@objc dynamic var serverTimezone: TimeZone?		// This is the Timezone the server claims to be using
	var serverTimezoneOffset: Int?					// Seconds from UTC.
	
	// Device Time
	@objc dynamic var deviceTimezone: TimeZone
	var deviceTimezoneOffset: Int
		
	// This is the time offset, in seconds, between the device timezone and the server timezone. 0 if both are the same TZ.
	// Can be 0 even if they are not the same TZ. In the example above, value would be -3600 (CST is an hour behind EST).
	@objc dynamic var timeZoneOffset: Int = 0
	
	// This is the (approximate) GMT-based offset between between server time and device time. Note that this isn't displayed time.
	// If the server says it's 5:00 EST and the device says it's 5:00 CST, this will list the offset at 3600 seconds.
	@objc dynamic var deviceTimeOffset: TimeInterval = 0			// Positive times mean device is ahead of server.
	
	// There's basically 2 things we care about for server time:
	//		1. Does device time match server time, in absolute terms (GMT, or seconds-since-epoch)? If not, notifications 
	//			may be wrong, events may show the wrong time, tweets will be listed as an hour old as soon as they post, etc.
	//		2. Does the device TZ match the server TZ? If not, the user will have to be sure to do time computations whenever
	//			they look at a wall clock.

	override init() {
		// Not using the autoupdating timezone, as we're manually updating it and watching the notification.
		deviceTimezone = TimeZone.current
		deviceTimezoneOffset = deviceTimezone.secondsFromGMT()
		super.init()
		NotificationCenter.default.addObserver(self, selector: #selector(deviceTimeZoneChanged), name: Notification.Name.NSSystemTimeZoneDidChange, object: nil)
	}
	
	// Called by the Alert Updater.
	func updateServerTime(_ response: TwitarrV3UserNotificationData)
	{
		self.serverTimezoneOffset = response.serverTimeOffset
		if let tz = TimeZone(identifier: response.serverTimeZoneID) {
			self.serverTimezone = tz
		}
		else {
			self.serverTimezone	= TimeZone(abbreviation: response.serverTimeZone)
		}
		let serverTime = StringUtilities.isoDateWithFraction.date(from: response.serverTime) ??
				StringUtilities.isoDateNoFraction.date(from: response.serverTime) ?? Date()
		self.deviceTimeOffset = Date().timeIntervalSince(serverTime)
		self.calculateTimes()
	}
	
	@objc func deviceTimeZoneChanged(_ notification: Notification) {
		calculateTimes()
	}
	
	func calculateTimes() {
		deviceTimezone = TimeZone.current
		deviceTimezoneOffset = deviceTimezone.secondsFromGMT()
		if let serverTimezoneOffset = serverTimezoneOffset {
			timeZoneOffset = TimeZone.current.secondsFromGMT() - serverTimezoneOffset
		}
		
	}

	override var debugDescription: String {
		if let serverTz = serverTimezone, let serverTZOffset = serverTimezoneOffset {
			return """
					Server TZ is \(serverTz), with an offset of \(serverTZOffset).
					    Displayed time on device is \(deviceTimeOffset) seconds later than server time, and the TZ offset is \(timeZoneOffset)
					"""
		}
		return ""
	}
}
