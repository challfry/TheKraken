//
//  DayPlannerSectionHeader.swift
//  Kraken
//
//  Created by Chall Fry on 10/27/24.
//  Copyright © 2024 Chall Fry. All rights reserved.
//

import UIKit

class DayPlannerSectionHeader: BaseCollectionSupplementaryView {
	@IBOutlet var timeLabel: UILabel!
	@IBOutlet weak var previousDayButton: UIButton!
	@IBOutlet weak var nextDayButton: UIButton!
	
	override class var nib: UINib? {
		return UINib(nibName: "DayPlannerSectionHeader", bundle: nil)
	}
	
	override class var reuseID: String {
		return "DayPlannerSectionHeader"
	}

	override func awakeFromNib() {
		super.awakeFromNib()

		// Font styling
		timeLabel.styleFor(.body)
	}

	func setTime(to displayTime: Date) {
		let dateFormatter = DateFormatter()
		dateFormatter.locale = Locale(identifier: "en_US")
		
		// 
		if let serverTZ = ServerTime.shared.serverTimezone {
			dateFormatter.timeZone = serverTZ
		}

//		dateFormatter.setLocalizedDateFormatFromTemplate("eeee MMM d" )
		dateFormatter.dateFormat = "eeee MMM d"
		let timeString = dateFormatter.string(from: displayTime)
		timeLabel.text = timeString
	}
	
	func setTimeLabelText(to newString: String) {
		timeLabel.text = newString
	}

	override func setup(cellModel: BaseCellModel) {
		if let cellModel = cellModel as? DayPlannerCellModel {
			setTime(to: cellModel.displayStartTime)
			if let dayOfCruise = cellModel.dayOfCruise {
				previousDayButton.isEnabled = dayOfCruise != 0
				nextDayButton.isEnabled = dayOfCruise < (cruiseNumDays() - 1)
			}
		}

	}
	
	@IBAction func previousDayButtonHit(_ sender: Any) {
		if let cv = collectionView, var path = self.indexPath {
			path.section -= 1
			cv.scrollToItem(at: path, at: .centeredVertically, animated: true)
		}
	}
	
	@IBAction func nextDayButtonHit(_ sender: Any) {
		if let cv = collectionView, var path = self.indexPath {
			path.section += 1
			cv.scrollToItem(at: path, at: .centeredVertically, animated: true)
		}
	}
}
