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
		if !isPrototypeCell {
			NotificationCenter.default.addObserver(forName: RefreshTimers.MinuteUpdateNotification, object: nil,
					queue: nil) { [weak self] notification in
    			if let self = self {
    					self.setupForDay()
   	 			}
			}
		}
	}
	
	override var cellModel: BaseCellModel? {
		didSet {
			setupForDay()
		}
	}

	func setupForDay() {
		isAccessibilityElement = true
	
		// If the cell's been configured for a particular day, and that day isn't today, reload.
		let dayOffset = cruiseStartRelativeDays()
		if let configuredDay = configuredForDay {
			if dayOffset != configuredDay {
				self.dataSource?.reloadCell(self)
				configuredForDay = nil					// Just in case; prevents repeated loads
			}
		}
		configuredForDay = dayOffset			
		
		if  let beforeCruise = daysBeforeCruiseStart() {
			beforeBoatView?.isHidden = false
			duringCruiseView?.isHidden = true
			dayCountLabel?.text = "\(beforeCruise)"
			daysLabel?.text = beforeCruise == 1 ? "Day" : "Days"
			accessibilityLabel = "\(beforeCruise) days until boat"
		}
		else if let duringCruise = dayOfCruise() {
			beforeBoatView?.isHidden = true
			duringCruiseView?.isHidden = false
			cruiseDayLabel?.text = "\(duringCruise)"
		}
		else if let afterCruise = dayAfterCruise() {
			if afterCruise == 1 {
				postCruiseDayCount?.text = "1 Day"
				accessibilityLabel = "1 day post cruise"
			}
			else {
				postCruiseDayCount?.text = "\(afterCruise) Days"
				accessibilityLabel = "\(afterCruise) days post cruise"
			}
		}
	}
}
