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
//	return cruiseStartDate()! + 86400 * 0 + 3600 * 10		

	// Always return this when not specifically testing dates.
	return Date()
}

// For 2020, this date is 12:00 Midnight, Saturday March 7, EST
func cruiseStartDate() -> Date? {
	let startDayComponents = DateComponents(calendar: Calendar.current, timeZone: TimeZone(secondsFromGMT: 0 - 3600 * 5), 
			year: 2020, month: 3, day: 7)
	let startDate = Calendar.current.date(from: startDayComponents)		
	return startDate
}

// A 1-based counter showing days before March 7, or nil if it's March 7 or later.
func daysBeforeCruiseStart() -> Int? {
	if let startDate = cruiseStartDate(), cruiseCurrentDate() < startDate {
		let components = Calendar.current.dateComponents([.day], from: cruiseCurrentDate(), to: startDate)
		if let dayCount = components.day, dayCount >= 0 {
			return dayCount + 1
		}
	}
	return nil
}

// A 1-based counter; returns 1 on March 7, and 8 on March 14. Nil on all other days.
func dayOfCruise() -> Int? {
	if let startDate = cruiseStartDate(), cruiseCurrentDate() > startDate {
		let components = Calendar.current.dateComponents([.day], from: startDate, to: cruiseCurrentDate())
		if let dayCount = components.day, dayCount >= 0, dayCount <= 7 {
			return dayCount + 1
		}
	}
	return nil
}

// A 1-based counter; returns 1 on March 15. Nil if date is earlier.
func dayAfterCruise() -> Int? {
	if let startDate = cruiseStartDate(), cruiseCurrentDate() > startDate {
		let components = Calendar.current.dateComponents([.day], from: startDate, to: cruiseCurrentDate())
		if let dayCount = components.day, dayCount >= 8 {
			return dayCount - 7
		}
	}
	return nil
}

func cruiseStartRelativeDays() -> Int {
	if let startDate = cruiseStartDate() {
		let components = Calendar.current.dateComponents([.day], from: startDate, to: cruiseCurrentDate())
		guard let dayCount = components.day else { return 0 }
		if cruiseCurrentDate() < startDate {
			return dayCount - 1
		}
		return dayCount
	}
	return 0
}
	
	
// For 2019, this date is 12:00 Midnight, Saturday March 16, EDT
func lastCruiseEndDate() -> Date? {
	let endDayComponents = DateComponents(calendar: Calendar.current, timeZone: TimeZone(secondsFromGMT: 0 - 3600 * 4), 
			year: 2019, month: 3, day: 16)
	let endDate = Calendar.current.date(from: endDayComponents)		
	return endDate
}

func lastCruiseEndRelativeDays() -> Int {
	if let endDate = lastCruiseEndDate() {
		let components = Calendar.current.dateComponents([.day], from: endDate, to: cruiseCurrentDate())
		guard let dayCount = components.day else { return 0 }
		return dayCount
	}
	return 0
}
