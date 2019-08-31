//
//  EventCell.swift
//  Kraken
//
//  Created by Chall Fry on 8/13/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit

@objc protocol EventCellBindingProtocol: FetchedResultsBindingProtocol {
	var isInteractive: Bool { get set }
	var disclosureLevel: Int { get set }
	var specialHighlight: Bool { get set }
}

class EventCellModel: FetchedResultsCellModel, EventCellBindingProtocol {
	override class var validReuseIDDict: [String: BaseCollectionViewCell.Type ] { return [ "EventCell" : EventCell.self ] }

	// If false, the cell doesn't show text links, the like/reply/delete/edit buttons, nor does tapping the 
	// user thumbnail open a user profile panel.
	@objc dynamic var isInteractive: Bool = true
	@objc dynamic var disclosureLevel: Int = 5
	@objc dynamic var specialHighlight: Bool = false
	
	init(withModel: NSFetchRequestResult?) {
		super.init(withModel: withModel, reuse: "EventCell", bindingWith: EventCellBindingProtocol.self)
	}


}

class EventCell: BaseCollectionViewCell, EventCellBindingProtocol {
	@IBOutlet var titleLabel: UILabel!
	@IBOutlet var eventTimeLabel: UILabel!
	@IBOutlet var locationLabel: UILabel!
	@IBOutlet var descriptionLabel: UILabel!
	@IBOutlet var ribbonView: UIView!
	@IBOutlet var ribbonViewLabel: UILabel!
	
	private static let cellInfo = [ "EventCell" : PrototypeCellInfo("EventCell") ]
	override class var validReuseIDDict: [ String: PrototypeCellInfo] { return EventCell.cellInfo }
	
	override func awakeFromNib() {
		super.awakeFromNib()
		ribbonViewLabel.layer.anchorPoint = CGPoint(x: 0.0, y: 0.0)
		ribbonViewLabel.transform = CGAffineTransform(rotationAngle: .pi / 2)
		
		// Every 10 seconds, update the ribbon
		NotificationCenter.default.addObserver(forName: RefreshTimers.TenSecUpdateNotification, object: nil,
				queue: nil) { [weak self] notification in
			self?.setRibbonStates()
		}
	}

	// If false, the cell doesn't show text links, the like/reply/delete/edit buttons, nor does tapping the 
	// user thumbnail open a user profile panel.
	var isInteractive: Bool = true
	
	var disclosureLevel: Int = 5 {
		didSet {
			guard let event = model as? Event else { return }
			let actionBlock = {
				self.descriptionLabel.text = self.disclosureLevel > 3 ?  event.eventDescription : ""
				self.locationLabel.text = self.disclosureLevel > 2 ? event.location : ""
				self.eventTimeLabel.text = self.disclosureLevel > 1 ? self.makeTimeString() : ""
			}
			isPrototypeCell ? actionBlock() : UIView.animate(withDuration: 0.3, animations: actionBlock)
			cellSizeChanged()
		}
	}

	var specialHighlight: Bool = false

	var model: NSFetchRequestResult? {
		didSet {
			if let event = model as? Event {
				titleLabel.text = event.title
				descriptionLabel.text = disclosureLevel > 3 ?  event.eventDescription : ""
				locationLabel.text = disclosureLevel > 2 ? event.location : ""
				eventTimeLabel.text = disclosureLevel > 1 ? makeTimeString() : ""
				setRibbonStates()

				cellSizeChanged()
				
			}
		}
	}
	
	func makeTimeString() -> String {
		if let event = model as? Event, let startTime = event.startTime {
			let dateFormatter = DateFormatter()
			dateFormatter.dateStyle = .short
			dateFormatter.timeStyle = .short
			dateFormatter.locale = Locale(identifier: "en_US")
			var timeString = dateFormatter.string(from: startTime)
			if let endTime = event.endTime {
				dateFormatter.dateStyle = .none
				timeString.append(" - \(dateFormatter.string(from: endTime))")
			}
			return timeString
		}
		return ""
	}
	
	func setRibbonStates() {
		if let event = model as? Event {
			if event.isHappeningNow() {
				ribbonView.isHidden = false
				ribbonView.backgroundColor = UIColor(red: 167.0 / 255.0, green: 0.0, blue: 180.0 / 255.0, alpha: 1.0)
				ribbonViewLabel.text = "Now"
				ribbonViewLabel.textColor = UIColor.white
			}
			else if event.isHappeningSoon() {
				ribbonView.isHidden = false
				ribbonView.backgroundColor = UIColor(red: 250.0 / 255.0, green: 250.0 / 255.0, blue: 50.0 / 255.0, alpha: 1.0)
				ribbonViewLabel.text = "Soon"
				ribbonViewLabel.textColor = UIColor.black
			}
			else {
				ribbonView.isHidden = true
			}
		}
		else {
			ribbonView.isHidden = true
		}
	}
	
	// I believe this cell can override calculateSize() to optimize layout speed, and can probably override
	// makePrototypeCell() to calculate cell heights for all disclosure levels.

}

