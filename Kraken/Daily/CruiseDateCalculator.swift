//
//  CruiseDateCalculator.swift
//  Kraken
//
//  Created by Chall Fry on 2/2/20.
//  Copyright © 2020 Chall Fry. All rights reserved.
//

import Foundation

// All other date calculation functions use this to get Date(). This way, different cruise dates may be unit tested
// by modifying the return value of this function.
func cruiseCurrentDate() -> Date {
	// Uncomment this to make the app think 'today' is some day relative to the cruise start date.
//	return cruiseStartDate()! + 86400 * 1 + 3600 * 12

	// Always return this when not specifically testing dates.
	return Date()
}

// For 2022, this date is 12:00 Midnight, Saturday March 5, EST
// For 2024, this date is 12:00 Midnight, Saturday March 9, EST
// For 2025, this date is 12:00 Midnight, Sunday March 2, EST
func cruiseStartDate() -> Date? {
	let startDayComponents = DateComponents(calendar: Calendar(identifier: .gregorian), timeZone: TimeZone(identifier: "America/New_York"), 
			year: 2025, month: 3, day: 2)
	let startDate = Calendar(identifier: .gregorian).date(from: startDayComponents)		
	return startDate
}

// How many days the cruise is. For a one week cruise, this value should be 8 (8 days, 7 nights).
func cruiseNumDays() -> Int {
	return 8
}

// A 1-based counter showing days before embark day, or nil if it's embark day or later.
func daysBeforeCruiseStart() -> Int? {
	if let startDate = cruiseStartDate(), cruiseCurrentDate() < startDate {
		let components = Calendar(identifier: .gregorian).dateComponents([.day], from: cruiseCurrentDate(), to: startDate)
		if let dayCount = components.day, dayCount >= 0 {
			return dayCount + 1
		}
	}
	return nil
}

// A 1-based counter; returns 1 on embark day, and 8 on disembark day (for a 1-week cruise). Nil on all other days.
func dayOfCruise() -> Int? {
	if let startDate = cruiseStartDate(), cruiseCurrentDate() > startDate {
		let components = Calendar(identifier: .gregorian).dateComponents([.day], from: startDate, to: cruiseCurrentDate())
		if let dayCount = components.day, dayCount >= 0, dayCount <= 7 {
			return dayCount + 1
		}
	}
	return nil
}

// A 1-based counter; returns 1 on disembark day. Nil if date is earlier.
func dayAfterCruise() -> Int? {
	if let startDate = cruiseStartDate(), cruiseCurrentDate() > startDate {
		let components = Calendar(identifier: .gregorian).dateComponents([.day], from: startDate, to: cruiseCurrentDate())
		if let dayCount = components.day, dayCount >= 8 {
			return dayCount - 7
		}
	}
	return nil
}

func cruiseStartRelativeDays() -> Int {
	if let startDate = cruiseStartDate() {
		let components = Calendar(identifier: .gregorian).dateComponents([.day], from: startDate, to: cruiseCurrentDate())
		guard let dayCount = components.day else { return 0 }
		if cruiseCurrentDate() < startDate {
			return dayCount - 1
		}
		return dayCount
	}
	return 0
}

// MARK: - Time Zones


// The TZ of the port the ship sails from
func portTimeZone() -> TimeZone {
	return TimeZone(identifier: "America/New_York") ?? TimeZone.current
}

// MARK: - Last Year's Cruise

func lastCruiseStartDate() -> Date {
	let startDayComponents = DateComponents(calendar: Calendar(identifier: .gregorian), timeZone: TimeZone(identifier: "America/New_York"), 
			year: 2024, month: 3, day: 9)
	let startDate = Calendar(identifier: .gregorian).date(from: startDayComponents)!	
	return startDate
}
	
	
// For 2023, this date is 12:00 Midnight, Saturday March 12, 2022 EDT
// For 2024, this date is 12:00 Midnight, Saturday March 12, 2023 EDT
// For 2025, this date is 12:00 Midnight, Saturday March 16, 2024 EDT
func lastCruiseEndDate() -> Date? {
	let endDayComponents = DateComponents(calendar: Calendar(identifier: .gregorian), timeZone: TimeZone(identifier: "America/New_York"), 
			year: 2024, month: 3, day: 16)
	let endDate = Calendar(identifier: .gregorian).date(from: endDayComponents)		
	return endDate
}

func lastCruiseEndRelativeDays() -> Int {
	if let endDate = lastCruiseEndDate() {
		let components = Calendar(identifier: .gregorian).dateComponents([.day], from: endDate, to: cruiseCurrentDate())
		guard let dayCount = components.day else { return 0 }
		return dayCount
	}
	return 0
}
