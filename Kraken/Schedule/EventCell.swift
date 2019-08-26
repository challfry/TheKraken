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
}

class EventCellModel: FetchedResultsCellModel, EventCellBindingProtocol {
	override class var validReuseIDDict: [String: BaseCollectionViewCell.Type ] { return [ "EventCell" : EventCell.self ] }

	// If false, the cell doesn't show text links, the like/reply/delete/edit buttons, nor does tapping the 
	// user thumbnail open a user profile panel.
	@objc dynamic var isInteractive: Bool = true
	
	@objc dynamic var disclosureLevel: Int = 5
	
	init(withModel: NSFetchRequestResult?) {
		super.init(withModel: withModel, reuse: "EventCell", bindingWith: EventCellBindingProtocol.self)
	}


}

class EventCell: BaseCollectionViewCell, EventCellBindingProtocol {
	@IBOutlet var titleLabel: UILabel!
	@IBOutlet var eventTimeLabel: UILabel!
	@IBOutlet var locationLabel: UILabel!
	@IBOutlet var descriptionLabel: UILabel!
	
	private static let cellInfo = [ "EventCell" : PrototypeCellInfo("EventCell") ]
	override class var validReuseIDDict: [ String: PrototypeCellInfo] { return EventCell.cellInfo }

	// If false, the cell doesn't show text links, the like/reply/delete/edit buttons, nor does tapping the 
	// user thumbnail open a user profile panel.
	var isInteractive: Bool = true
	
	var disclosureLevel: Int = 5 {
		didSet {
			guard let event = model as? Event else { return }
			UIView.animate(withDuration: 0.3) {
				self.descriptionLabel.text = self.disclosureLevel <= 3 ? "" : event.eventDescription
				self.locationLabel.text = self.disclosureLevel <= 2 ? "" : event.location
				self.eventTimeLabel.text = self.disclosureLevel <= 1 ? "" : self.makeTimeString()
			}
			cellSizeChanged()
		}
	}

	var model: NSFetchRequestResult? {
		didSet {
			if let event = model as? Event {
				titleLabel.text = event.title
				locationLabel.text = event.location
				descriptionLabel.text = event.eventDescription
				eventTimeLabel.text = makeTimeString()
				
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

}

