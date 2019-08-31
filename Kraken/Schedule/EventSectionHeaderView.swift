//
//  EventSectionHeaderView.swift
//  Kraken
//
//  Created by Chall Fry on 8/30/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit

class EventSectionHeaderView: UICollectionReusableView {
	@IBOutlet var timeLabel: UILabel!
	
	func setTime(to displayTime: Date) {
		let dateFormatter = DateFormatter()
		dateFormatter.locale = Locale(identifier: "en_US")

		dateFormatter.setLocalizedDateFormatFromTemplate("H:mm a, eeee MMM d" )
		dateFormatter.dateFormat = "h:mm a - eeee MMM d"
		let timeString = dateFormatter.string(from: displayTime)
		timeLabel.text = timeString
	}

}
