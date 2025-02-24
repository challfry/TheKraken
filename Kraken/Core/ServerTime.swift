//
//  ServerTime.swift
//  Kraken
//
//  Created by Chall Fry on 9/12/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit

@objc(TimeZoneChange) public class TimeZoneChange: KrakenManagedObject {
	/// When the new time zone becomes active.
	@NSManaged public var activeDate: Date
	/// The 3 letter abbreviation for the timezone that becomes active at `activeDate`
	@NSManaged public var timeZoneAbbrev: String
	/// The Foundation ID for the timezone that becomes active at `activeDate`. Prefer using this to make TimeZone objects over the abbreviation.
	/// There is a list of all Foundation TimeZone names at `seeds/TimeZoneNames.txt`
	@NSManaged public var timeZoneID: String
	
	override public func awakeFromInsert() {
		super.awakeFromInsert()
		activeDate = Date()
	}

	func buildFromV3(context: NSManagedObjectContext, v3Object: TwitarrV3TimeZoneChangeData.Record) {
		TestAndUpdate(\.activeDate, v3Object.activeDate)
		TestAndUpdate(\.timeZoneAbbrev, v3Object.timeZoneAbbrev)
		TestAndUpdate(\.timeZoneID, v3Object.timeZoneID)
	}
}

@objc class ServerTime : ServerUpdater {
	static let shared = ServerTime()

	var lastError: ServerError?
	
	// All known time zone changes that occur on the boat
	var changePoints: [TwitarrV3TimeZoneChangeData.Record] = []

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
		super.init(3600)
		loadTimezoneTableFromDB()		
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
	
	private func calculateTimes() {
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
	
	override func updateMethod() {
		callTimezonesEndpoint()
	}
	
	// Called by ServerUpdater to update the table of time zone changes
	private func callTimezonesEndpoint() {
		let request = NetworkGovernor.buildTwittarRequest(withPath:"/api/v3/admin/timezonechanges")
		NetworkGovernor.shared.queue(request) { (package: NetworkResponse) in
			if let error = package.serverError {
				self.lastError = error
				self.updateComplete(success: false)
			}
			else if let data = package.data {
				do {
					self.lastError = nil
					let response = try Settings.v3Decoder.decode(TwitarrV3TimeZoneChangeData.self, from: data)
					self.saveTimezoneTableToDB(newRecords: response.records)
					self.updateComplete(success: true)
				}
				catch {
					NetworkLog.error("Failure parsing TimeZones response.", ["Error" : error, "url" : request.url as Any])
					self.updateComplete(success: false)
				}
			}
			else {
				// Network error
				self.updateComplete(success: false)
			}
		}
	}
	
	private func saveTimezoneTableToDB(newRecords: [TwitarrV3TimeZoneChangeData.Record]) {
		LocalCoreData.shared.performNetworkParsing { context in
			context.pushOpErrorExplanation("Failure saving TimeZone table to Core Data.")
			
			let fetchRequest = NSFetchRequest<TimeZoneChange>(entityName: "TimeZoneChange")
			fetchRequest.sortDescriptors = [NSSortDescriptor(key: "activeDate", ascending: true)]
			let dbChangePoints = try context.fetch(fetchRequest)
			var tablesAreEquivalent = dbChangePoints.count == newRecords.count
			if tablesAreEquivalent {
				for index in 0..<newRecords.count {
					if newRecords[index].activeDate != dbChangePoints[index].activeDate || 
							newRecords[index].timeZoneID != dbChangePoints[index].timeZoneID || 
							newRecords[index].timeZoneAbbrev != dbChangePoints[index].timeZoneAbbrev {
						tablesAreEquivalent = false
					}
				}
			}
			if !tablesAreEquivalent {
				dbChangePoints.forEach { context.delete($0) }
				newRecords.forEach { 
					let newChangePoint = TimeZoneChange(context: context)
					newChangePoint.activeDate = $0.activeDate
					newChangePoint.timeZoneID = $0.timeZoneID
					newChangePoint.timeZoneAbbrev = $0.timeZoneAbbrev
				}
				LocalCoreData.shared.setAfterSaveBlock(for: context) { success in
					self.loadTimezoneTableFromDB()
				}
			}
		}
	}
	
	@discardableResult private func loadTimezoneTableFromDB() -> [TwitarrV3TimeZoneChangeData.Record] {
		let fetchRequest = NSFetchRequest<TimeZoneChange>(entityName: "TimeZoneChange")
		fetchRequest.sortDescriptors = [NSSortDescriptor(key: "activeDate", ascending: true)]
		if let dbChangePoints = try? LocalCoreData.shared.mainThreadContext.fetch(fetchRequest) {
			self.changePoints = dbChangePoints.map { TwitarrV3TimeZoneChangeData.Record(from: $0) }
		}
		return changePoints
	}
	
	private func getTimezoneTable() -> [TwitarrV3TimeZoneChangeData.Record] {
		if changePoints.isEmpty {
			return loadTimezoneTableFromDB()
		}
		return changePoints
	}
	
// MARK: - Client API
	
	/// Returns the TimeZone the ship will be in at the given Date, or the current time if no Date specified. If you're using this with a 'floating' date (e.g. "2:00 PM in whatever
	/// timezone the boat is in that day") be sure to call `portTimeToDisplayTime()` first, and call this fn with the returned Date.
	func tzAtTime(_ time: Date? = nil) -> TimeZone {
		let actualTime = time ?? Date()
		if let currentTZ = getTimezoneTable().last(where: { $0.activeDate <= actualTime }),
				let result = TimeZone(identifier: currentTZ.timeZoneID) ?? TimeZone(abbreviation: currentTZ.timeZoneAbbrev) {
			return result
		}
		return portTimeZone()
	}
	
	/// Returns the 3 letter abbreviation for the time zone the ship will be in at the given Date, or the current time if no Date specified. If you're using this with 
	/// a 'floating' date (e.g. "2:00 PM in whatever timezone the boat is in that day") be sure to call `portTimeToDisplayTime()` first, and call this fn with the returned Date.
	/// Also, do not use these abbreviations to later make TimeZone objects (with `TimeZone(abbreviation:)`). Use `tzAtTime()` instead.
	func abbrevAtTime(_ time: Date? = nil) -> String {
		let actualTime = time ?? Date()
		if let currentRecord = getTimezoneTable().last(where: { $0.activeDate <= actualTime }),
				let tz = TimeZone(identifier: currentRecord.timeZoneID) ?? TimeZone(abbreviation: currentRecord.timeZoneAbbrev) {
			return tz.abbreviation(for: actualTime) ?? currentRecord.timeZoneAbbrev
		}
		return portTimeZone().abbreviation(for: actualTime) ?? "EST"
	}

	// Twitarr often has to deal with Date objects that actually attempt to specify a 'floating local time', e.g. `March 10, 2:00 PM`
	// in whatever the local timezone is on March 10th. However, we store dates as Date() objects, which are just Doubles and don't
	// support a floating local time concept. And no, we're not going to switch to storing "20220310T1400" strings, that's a recipe
	// for about a million sort bugs. 
	// 
	// Instead, we declare floating Dates stored in the db to be in 'port time', usually EST for sailings departing Fort Lauderdale.
	// The advantage over storing GMT is that the dates are +/- one hour from the 'correct' time, reducing the severity of mistakes
	// with filters that grab "all events happening on Tuesday". When the API delivers Date objects to clients we convert the date
	// into the current timezone the boat is in. 
	//
	// This means that if for some reason the boat isn't where it's expected to be or the captain declares an unexpected TZ change,
	// all 'floating' dates will still be correct once the TimeZoneChange table is updated.
	//
	// Finally: call this fn to convert timezones. Make another fn like this one if you need to do another kind of tz conversion.
	// Do not calculate the offset between timezones and add/subtract that value from a Date object.
//	func portTimeToDisplayTime(_ time: Date? = nil) -> Date {
//		let actualTime = time ?? Date()
//		if let currentRecord = getTimezoneTable().last(where: { $0.startTime <= actualTime }), 
//				let currentTZ = TimeZone(identifier: currentRecord.timeZoneID) {
//			let cal = Settings.shared.getPortCalendar()
//			var dateComponents = cal.dateComponents(in: Settings.shared.portTimeZone, from: actualTime)
//			dateComponents.timeZone = currentTZ
//			return cal.date(from: dateComponents) ?? actualTime
//		}
//		return actualTime
//	}
//	
//	// Adjusts the given Date so that it's the same 'clock time' but in the boat's Port timezone. Useful for building queries
//	// against Date objects in the db that are really 'floating' dates meant to be interpreted as 'clock time' in the local tz.
//	func displayTimeToPortTime(_ time: Date? = nil) -> Date {
//		let actualTime = time ?? Date()
//		if let currentRecord = getTimezoneTable().last(where: { $0.startTime <= actualTime }), 
//				let currentTZ = TimeZone(identifier: currentRecord.timeZoneID) {
//			let cal = Settings.shared.getPortCalendar()
//			var dateComponents = cal.dateComponents(in: currentTZ, from: actualTime)
//			dateComponents.timeZone = Settings.shared.portTimeZone
//			return cal.date(from: dateComponents) ?? actualTime
//		}
//		return actualTime
//	}
}


// MARK: - Twitarr V3 API 

/// Used to return information about the time zone changes scheduled to occur during the cruise.
///
/// Returned by: `GET /api/v3/admin/timezonechanges`
public struct TwitarrV3TimeZoneChangeData: Content {
	public struct Record: Content {
		/// When the new time zone becomes active.
		var activeDate: Date
		/// The 3 letter abbreviation for the timezone that becomes active at `activeDate`
		var timeZoneAbbrev: String
		/// The Foundation ID for the timezone that becomes active at `activeDate`. Prefer using this to make TimeZone objects over the abbreviation.
		/// There is a list of all Foundation TimeZone names at `seeds/TimeZoneNames.txt`
		var timeZoneID: String
	}

	/// All the timezone changes that will occur during the cruise, sorted by activeDate.
	var records: [Record]
	/// The 3 letter abbreviation for the timezone the ship is currently observing.
	var currentTimeZoneAbbrev: String
	/// The Foundation ID of the current time zone.
	var currentTimeZoneID: String
	/// The number of seconds between the current timezone and GMT. Generally a negative number in the western hemisphere.
	var currentOffsetSeconds: Int
}

extension TwitarrV3TimeZoneChangeData.Record {
	init(from: TimeZoneChange) {
		activeDate = from.activeDate
		timeZoneAbbrev = from.timeZoneAbbrev
		timeZoneID = from.timeZoneID
	}
}
