//
//  AnnouncementCell.swift
//  Kraken
//
//  Created by Chall Fry on 1/19/20.
//  Copyright © 2020 Chall Fry. All rights reserved.
//

import UIKit

@objc protocol AnnouncementCellBindingProtocol: FetchedResultsBindingProtocol {

}

@objc class AnnouncementCellModel: BaseCellModel, AnnouncementCellBindingProtocol {
	override class var validReuseIDDict: [String: BaseCollectionViewCell.Type ] { 
		return [ "AnnouncementCell" : AnnouncementCell.self ] 
	}
	
	dynamic var model: NSFetchRequestResult?
	
	init() {
		super.init(bindingWith: AnnouncementCellBindingProtocol.self)
	}
}

class AnnouncementCell: BaseCollectionViewCell, AnnouncementCellBindingProtocol {
	private static let cellInfo = [ "AnnouncementCell" : PrototypeCellInfo("AnnouncementCell") ]
	override class var validReuseIDDict: [ String: PrototypeCellInfo] { return AnnouncementCell.cellInfo }

	@IBOutlet var announcementHeaderLabel: UILabel!
	@IBOutlet var authorLabel: UILabel!
	@IBOutlet var relativeTimeLabel: UILabel!
	@IBOutlet var announcementTextLabel: UILabel!
	@IBOutlet var roundedRectView: AnnouncementRoundedRectView!
	
	var model: NSFetchRequestResult? {
		didSet {
			clearObservations()
			if let announcementModel = model as? Announcement {
				addObservation(announcementModel.tell(self, when: "text") { observer, observed in
					if let text = observed.text {
						observer.announcementTextLabel.attributedText = StringUtilities.cleanupText(text)
					}
					else {
						observer.announcementTextLabel.text = ""
					}
				}?.execute())
				
				addObservation(announcementModel.tell(self, when: "author.displayName") { observer, observed in
					observer.authorLabel.text = "From: \(observed.author?.displayName ?? observed.author?.username ?? "unknown")"
				}?.execute())
				
				addObservation(announcementModel.tell(self, when: "timestamp") { observer, observed in
					observer.relativeTimeLabel.text = StringUtilities.relativeTimeString(forDate: announcementModel.creationDate())
				}?.execute())
			}
			else {
				announcementTextLabel.text = ""
				authorLabel.text = ""
			}
			cellSizeChanged()
			roundedRectView.setNeedsDisplay()
		}
	}
	
	override func awakeFromNib() {
		// Font styling
		announcementHeaderLabel.styleFor(.body)
		authorLabel.styleFor(.body)
		announcementTextLabel.styleFor(.body)

		// Every 10 seconds, update the post time.
		NotificationCenter.default.addObserver(forName: RefreshTimers.TenSecUpdateNotification, object: nil,
				queue: nil) { [weak self] notification in
    		if let self = self, let announcementModel = self.model as? Announcement, announcementModel.isActive {
				self.relativeTimeLabel.text = StringUtilities.relativeTimeString(forDate: announcementModel.creationDate())
			}
		}
	}
}


let preSailAnnouncements : [String] = [
	".. but have you packed enough Ukeleles?",
	"I'm hungry for seafood, but what food is the sea hungry for?",
	""
]

//let announcementAlertColors: [String] = [
//	"Fuschia Alert",
//	"Chartreuse Alert",
//	"Violet Alert",
//	"Marmalade Alert"
//	"Scarlet Alert"
//	"Magenta Alert"
//	"Mauve Alert"]


@objc class AnnouncementRoundedRectView: UIView {
	override func draw(_ rect: CGRect) {
		let pathBounds = bounds.insetBy(dx: 10, dy: 5)

		let rectShape = CAShapeLayer()
		rectShape.bounds = pathBounds
		rectShape.position = self.center
		let rectPath = UIBezierPath(roundedRect: pathBounds, cornerRadius: 12)
		rectShape.path = rectPath.cgPath
		layer.mask = rectShape
		layer.masksToBounds = true
		
		let context = UIGraphicsGetCurrentContext()
		if let color = UIColor(named: "Announcement Header Color") {
			context?.setStrokeColor(color.cgColor)
			rectPath.stroke()
		}

	}
}
