//
//  ServerTimeUpdater.swift
//  Kraken
//
//  Created by Chall Fry on 9/12/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit

@objc class ServerTimeUpdater: ServerUpdater {
	static let shared = ServerTimeUpdater()

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

	init() {
		// Not using the autoupdating timezone, as we're manually updating it and watching the notification.
		deviceTimezone = TimeZone.current
		deviceTimezoneOffset = deviceTimezone.secondsFromGMT()
		super.init(15 * 60)
		NotificationCenter.default.addObserver(self, selector: #selector(deviceTimeZoneChanged), name: Notification.Name.NSSystemTimeZoneDidChange, object: nil)
	}

	override func updateMethod() {
		let request = NetworkGovernor.buildTwittarRequest(withPath:"/api/v2/time", query: nil)
		NetworkGovernor.shared.queue(request) { (package: NetworkResponse) in
			if let error = NetworkGovernor.shared.parseServerError(package) {
				// Should only be called on app foreground and every 15 mins thereafter. If the call fails,
				// nothing to do.
				NetworkLog.error(error.localizedDescription)
			}
			else if let data = package.data {
//				print (String(decoding:data!, as: UTF8.self))
				let decoder = JSONDecoder()
				do {
					let timeResponse = try decoder.decode(TwitarrV2ServerTimeResponse.self, from: data)
					
					// Time Zones
					self.serverTimezoneOffset = timeResponse.offset
					if let tzName = timeResponse.time.split(separator: " ").last {
						self.serverTimezone	= TimeZone(abbreviation: String(tzName))
					}
					
					self.deviceTimeOffset = Date().timeIntervalSince(Date(timeIntervalSince1970: Double(timeResponse.epoch) / 1000.0 ))
					self.calculateTimes()
				} catch 
				{
					NetworkLog.error("Failure parsing server time response.", ["Error" : error, "URL" : request.url as Any])
				} 
			}
			self.updateComplete(success: true)
		}
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

// MARK: - V2 API Decoding

// GET /api/v2/time
struct TwitarrV2ServerTimeResponse: Codable {
	let status: String
	let epoch: Int64
	let time: String
	let offset: Int
}

