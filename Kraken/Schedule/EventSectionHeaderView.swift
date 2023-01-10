//
//  EventSectionHeaderView.swift
//  Kraken
//
//  Created by Chall Fry on 8/30/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit

class EventSectionHeaderView: BaseCollectionSupplementaryView {
	@IBOutlet var timeLabel: UILabel!
	
	override class var nib: UINib? {
		return  UINib(nibName: "EventSectionHeaderView", bundle: nil)
	}
	
	override class var reuseID: String {
		return "EventSectionHeaderView"
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

		dateFormatter.setLocalizedDateFormatFromTemplate("H:mm a, eeee MMM d" )
		dateFormatter.dateFormat = "h:mm a - eeee MMM d"
		let timeString = dateFormatter.string(from: displayTime)
		timeLabel.text = timeString
	}
	
	func setTimeLabelText(to newString: String) {
		timeLabel.text = newString
	}

	override func setup(cellModel: BaseCellModel) {
		if let eventCellModel = cellModel as? EventCellModel, let event = eventCellModel.model as? Event {
			setTime(to: event.startTime)
		}
	}
}
