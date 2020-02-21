//
//  ForumsLoadTimeCell.swift
//  Kraken
//
//  Created by Chall Fry on 12/3/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit

@objc protocol ForumsLoadTimeBindingProtocol {
	var lastLoadTime: Date? { get set }
	var enableRefreshButton: Bool { get set }
}

@objc class ForumsLoadTimeCellModel: BaseCellModel, ForumsLoadTimeBindingProtocol {
	override class var validReuseIDDict: [String: BaseCollectionViewCell.Type ] { 
		return [ "ForumsLoadTime" : ForumsLoadTimeCell.self ] 
	}

	@objc dynamic var lastLoadTime: Date?
	@objc dynamic var refreshButtonAction: (() -> Void)?
	@objc dynamic var enableRefreshButton: Bool = true
	
	init() {
		super.init(bindingWith: ForumsLoadTimeBindingProtocol.self)
	}
	
	func refreshButtonTapped() {
		refreshButtonAction?()
		enableRefreshButton = false
		Timer.scheduledTimer(withTimeInterval: 10.0, repeats: false) { timer in
			self.enableRefreshButton = true
		}
	}

}


class ForumsLoadTimeCell: BaseCollectionViewCell, ForumsLoadTimeBindingProtocol {
	private static let cellInfo = [ "ForumsLoadTime" : PrototypeCellInfo("ForumsLoadTimeCell") ]
	override class var validReuseIDDict: [ String: PrototypeCellInfo] { return ForumsLoadTimeCell.cellInfo }

	@IBOutlet weak var lastRefreshLabel: UILabel!
	@IBOutlet weak var refreshNowButton: UIButton!
	
	var lastLoadTime: Date? {
		didSet {
			if let lastLoad = lastLoadTime {
				let timeString = StringUtilities.relativeTimeString(forDate: lastLoad)
				lastRefreshLabel.text = "Last Refresh: \(timeString)"
				cellSizeChanged()
			}
		}
	}
	
	var enableRefreshButton: Bool = true {
		didSet {
			refreshNowButton.isEnabled = enableRefreshButton
		}
	}
	

	override func awakeFromNib() {
		// Font styling
		lastRefreshLabel.styleFor(.body)
		refreshNowButton.styleFor(.body)

		// Every 10 seconds, update the post time (the relative time since now that the post happened).
		NotificationCenter.default.addObserver(forName: RefreshTimers.TenSecUpdateNotification, object: nil,
				queue: nil) { [weak self] notification in
			if let self = self, let lastLoad = self.lastLoadTime {
				let timeString = StringUtilities.relativeTimeString(forDate: lastLoad)
				self.lastRefreshLabel.text = "Last Refresh: \(timeString)"
			}
		}
	}
	
	@IBAction func refreshNowButtonTapped(_ sender: Any) {
		if let m = cellModel as? ForumsLoadTimeCellModel {
			m.refreshButtonTapped()
		}
	}
	
	
}
