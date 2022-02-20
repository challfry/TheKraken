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
		
		// Every 10 seconds, update the post time (the relative time since now that the post happened).
		NotificationCenter.default.addObserver(forName: RefreshTimers.MinuteUpdateNotification, object: nil,
				queue: nil) { [weak self] notification in
			if let self = self, let announcementModel = self.model as? Announcement {
				self.shouldBeVisible = announcementModel.displayUntil > Date() && announcementModel.isActive
			}
		}
	}
}

@objc protocol LocalAnnouncementCellBindingProtocol {
	var headerText: String { get set }
	var authorName: String { get set } 
	var relativeTimeString: String { get set }
	var text: String { get set }
}


@objc class LocalAnnouncementCellModel: BaseCellModel, LocalAnnouncementCellBindingProtocol {
	override class var validReuseIDDict: [String: BaseCollectionViewCell.Type ] { 
		return [ "AnnouncementCell" : AnnouncementCell.self ] 
	}
	
	dynamic var headerText: String = ""
	dynamic var authorName: String = ""
	dynamic	var relativeTimeString: String = ""
	dynamic var text: String = ""
		
	init() {
		super.init(bindingWith: LocalAnnouncementCellBindingProtocol.self)
	}
}

class AnnouncementCell: BaseCollectionViewCell, AnnouncementCellBindingProtocol, LocalAnnouncementCellBindingProtocol {
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
				announcementHeaderLabel.text = "Announcement"
			
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
				
				addObservation(announcementModel.tell(self, when: "updatedAt") { observer, observed in
					observer.relativeTimeLabel.text = StringUtilities.relativeTimeString(forDate: announcementModel.updatedAt)
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
	
	var headerText: String = "" {
		didSet {
			announcementHeaderLabel.text = headerText
		}
	}
	
	var authorName: String = "" {
		didSet {
			authorLabel.text = authorName
		}
	}
	
	var relativeTimeString: String = "" {
		didSet {
			relativeTimeLabel.text = relativeTimeString
		}
	}
	
	var text: String = "" {
		didSet {
			announcementTextLabel.text = text
		}
	}
	
	override func awakeFromNib() {
		// Font styling
		announcementHeaderLabel.styleFor(.body)
		authorLabel.styleFor(.body)
		relativeTimeLabel.styleFor(.body)
		announcementTextLabel.styleFor(.body)

		// Every 10 seconds, update the post time.
		NotificationCenter.default.addObserver(forName: RefreshTimers.TenSecUpdateNotification, object: nil,
				queue: nil) { [weak self] notification in
    		if let self = self, let announcementModel = self.model as? Announcement, announcementModel.isActive {
				self.relativeTimeLabel.text = StringUtilities.relativeTimeString(forDate: announcementModel.updatedAt)
			}
		}
	}
}



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


// Reversed
let preSailAnnouncements : [String] = [
	"Tomorrow we Sail",
	
	".. but have you packed enough Ukeleles?",
	"I'm hungry for seafood, but what food is the sea hungry for?",
	""
]

let duringCruiseAnnouncements : [String] = [
	"Day 1: Leaving Fort Lauderdale",
	"Day 2: Half Moon Cay",
	"Day 3: At Sea",
	"Day 4: Santo Domingo",
	"Day 5: At Sea",
	"Day 6: Grand Turk",
	"Day 7: At Sea",
	"Day 8: Fort Lauderdale"
]


//let announcementAlertColors: [String] = [
//	"Fuschia Alert",
//	"Chartreuse Alert",
//	"Violet Alert",
//	"Marmalade Alert"
//	"Scarlet Alert"
//	"Magenta Alert"
//	"Mauve Alert"]

