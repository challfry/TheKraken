//
//  DailyActivityCell.swift
//  Kraken
//
//  Created by Chall Fry on 1/18/20.
//  Copyright © 2020 Chall Fry. All rights reserved.
//

import UIKit

@objc protocol DailyActivityCellProtocol {
}

class DailyActivityCellModel: BaseCellModel, DailyActivityCellProtocol {
	private static let validReuseIDs = [	"DailyActivityCell" : DailyActivityCell.self,
											"DailyActivityCell2" : DailyActivityCell.self,
											"DailyActivityCell3" : DailyActivityCell.self ]
	override class var validReuseIDDict: [String: BaseCollectionViewCell.Type ] { return validReuseIDs }

    init() {
        super.init(bindingWith: DailyActivityCellProtocol.self)
    }
    
    override func reuseID(traits: UITraitCollection) -> String {
    	if let _ = daysBeforeCruiseStart() {
	    	return "DailyActivityCell"
		}
		if let cruiseDay = dayOfCruise() {
			if cruiseDay == 1 {
				return "DailyActivityCell2"
			}
			return "DailyActivityCell"
		}
		
		return "DailyActivityCell3"
    }
        
    func currentDate() -> Date {
//		return cruiseStartDate()! + 86000 * 7 + 1000		
		return Date()
    }

	func cruiseStartDate() -> Date? {
		let startDayComponents = DateComponents(calendar: Calendar.current, timeZone: TimeZone(secondsFromGMT: 0 - 3600 * 5), 
				year: 2020, month: 3, day: 7)
		let startDate = Calendar.current.date(from: startDayComponents)		
		return startDate
	}
	
	// A 1-based counter showing days before March 7, or nil if it's March 7 or later.
	func daysBeforeCruiseStart() -> Int? {
		if let startDate = cruiseStartDate(), currentDate() < startDate {
			let components = Calendar.current.dateComponents([.day], from: currentDate(), to: startDate)
			if let dayCount = components.day, dayCount >= 0 {
				return dayCount + 1
			}
		}
		return nil
	}
	
	// A 1-based counter; returns 1 on March 7, and 8 on March 14. Nil on all other days.
	func dayOfCruise() -> Int? {
		if let startDate = cruiseStartDate(), currentDate() > startDate {
			let components = Calendar.current.dateComponents([.day], from: startDate, to: currentDate())
			if let dayCount = components.day, dayCount >= 0, dayCount <= 7 {
				return dayCount + 1
			}
		}
		return nil
	}
	
	// A 1-based counter; returns 1 on March 15. Nil if date is earlier.
	func dayAfterCruise() -> Int? {
		if let startDate = cruiseStartDate(), currentDate() > startDate {
			let components = Calendar.current.dateComponents([.day], from: startDate, to: currentDate())
			if let dayCount = components.day, dayCount >= 8 {
				return dayCount - 7
			}
		}
		return nil
	}
	
	func cruiseStartRelativeDays() -> Int {
		if let startDate = cruiseStartDate() {
			let components = Calendar.current.dateComponents([.day], from: startDate, to: currentDate())
			guard let dayCount = components.day else { return 0 }
			if currentDate() < startDate {
				return dayCount - 1
			}
			return dayCount
		}
		return 0
	}
	
	
}

class DailyActivityCell: BaseCollectionViewCell, DailyActivityCellProtocol {
	@IBOutlet var imageView: UIImageView!
	@IBOutlet var beforeBoatView: UIVisualEffectView?
	@IBOutlet var 	dayCountLabel: UILabel?
	@IBOutlet var 	daysLabel: UILabel?
	@IBOutlet var 	untilBoatLabel: UILabel?
	
	@IBOutlet var duringCruiseView: UIVisualEffectView?
	@IBOutlet var 	cruiseDayLabel: UILabel?
	
	@IBOutlet var postCruiseDayCount: UILabel?
	
	var configuredForDay: Int?
	
	private static let cellInfo = [ "DailyActivityCell" : PrototypeCellInfo("DailyActivityCell"),
									"DailyActivityCell2" : PrototypeCellInfo("DailyActivityCell2"),
									"DailyActivityCell3" : PrototypeCellInfo("DailyActivityCell3")]
	override class var validReuseIDDict: [ String: PrototypeCellInfo ] { return cellInfo }
	
	override func awakeFromNib() {
		NotificationCenter.default.addObserver(forName: RefreshTimers.MinuteUpdateNotification, object: nil,
				queue: nil) { [weak self] notification in
    		if let self = self {
    			self.setupForDay()
    		}
		}
	}
	
	override var cellModel: BaseCellModel? {
		didSet {
			setupForDay()
		}
	}

	func setupForDay() {
		if let model = cellModel as? DailyActivityCellModel {
		
			// If the cell's been configured for a particular day, and that day isn't today, reload.
			let dayOffset = model.cruiseStartRelativeDays()
			if let configuredDay = configuredForDay {
				if dayOffset != configuredDay {
					self.dataSource?.reloadCell(self)
					configuredForDay = nil					// Just in case; prevents repeated loads
				}
			}
			configuredForDay = dayOffset			
			
			if  let beforeCruise = model.daysBeforeCruiseStart() {
				beforeBoatView?.isHidden = false
				duringCruiseView?.isHidden = true
				dayCountLabel?.text = "\(beforeCruise)"
				daysLabel?.text = beforeCruise == 1 ? "Day" : "Days"
			}
			else if let duringCruise = model.dayOfCruise() {
				beforeBoatView?.isHidden = true
				duringCruiseView?.isHidden = false
				cruiseDayLabel?.text = "\(duringCruise)"
			}
			else if let afterCruise = model.dayAfterCruise() {
				if afterCruise == 1 {
					postCruiseDayCount?.text = "1 Day"
				}
				else {
					postCruiseDayCount?.text = "\(afterCruise) Days"
				}
			}
		}
	}
}
