//
//  AnnouncementCell.swift
//  Kraken
//
//  Created by Chall Fry on 1/19/20.
//  Copyright © 2020 Chall Fry. All rights reserved.
//

import UIKit
import CoreData

@objc protocol AnnouncementCellBindingProtocol  {
	var headerText: String { get set }
	var authorName: String { get set } 
	var announcementTime: Date { get set }
	var text: NSAttributedString { get set }
}

@objc class AnnouncementCellModel: BaseCellModel, AnnouncementCellBindingProtocol, FetchedResultsBindingProtocol {
	override class var validReuseIDDict: [String: BaseCollectionViewCell.Type ] { 
		return [ "AnnouncementCell" : AnnouncementCell.self ] 
	}
	
	dynamic var headerText: String = ""
	dynamic var authorName: String = ""
	dynamic	var announcementTime: Date = Date()
	dynamic var text: NSAttributedString = NSAttributedString()

	var model: NSFetchRequestResult? {
		didSet {
			clearObservations()
			if let announcementModel = model as? Announcement {
				headerText = "Announcement"
			
				addObservation(announcementModel.tell(self, when: "text") { observer, observed in
					if let text = observed.text {
						observer.text = StringUtilities.cleanupText(text)
					}
					else {
						observer.text =  NSAttributedString()
					}
				}?.execute())
				
				addObservation(announcementModel.tell(self, when: ["author.displayName", "author.username"]) { observer, observed in
					observer.authorName = "From: \(observed.author?.displayName ?? observed.author?.username ?? "unknown")"
				}?.execute())
				
				addObservation(announcementModel.tell(self, when: "updatedAt") { observer, observed in
					observer.announcementTime = observed.updatedAt
				}?.execute())
			}
			else {
				headerText = ""
				text = NSAttributedString()
				authorName = ""
				announcementTime = Date()
			}
		}
	}
	
	init() {
		super.init(bindingWith: AnnouncementCellBindingProtocol.self)
		
		// Every 10 seconds, call updateIsActive, so the model can mark itself inactive which causes it to be removed from the FRC.
		NotificationCenter.default.addObserver(forName: RefreshTimers.MinuteUpdateNotification, object: nil,
				queue: nil) { [weak self] notification in
			if let self = self, let announcementModel = self.model as? Announcement {
				announcementModel.updateIsActive()
			}
		}
	}
}

@objc class LocalAnnouncementCellModel: BaseCellModel, AnnouncementCellBindingProtocol {
	override class var validReuseIDDict: [String: BaseCollectionViewCell.Type ] { 
		return [ "AnnouncementCell" : AnnouncementCell.self ] 
	}
	
	dynamic var headerText: String = ""
	dynamic var authorName: String = ""
	dynamic	var announcementTime: Date = Date()
	dynamic var text: NSAttributedString = NSAttributedString()
		
	init() {
		super.init(bindingWith: AnnouncementCellBindingProtocol.self)
	}
}

class AnnouncementCell: BaseCollectionViewCell, AnnouncementCellBindingProtocol, UITextViewDelegate {
	private static let cellInfo = [ "AnnouncementCell" : PrototypeCellInfo("AnnouncementCell") ]
	override class var validReuseIDDict: [ String: PrototypeCellInfo] { return AnnouncementCell.cellInfo }

	@IBOutlet var announcementHeaderLabel: UILabel!
	@IBOutlet var authorLabel: UILabel!
	@IBOutlet var relativeTimeLabel: UILabel!
	@IBOutlet var announcementTextView: UITextView!
	@IBOutlet var roundedRectView: AnnouncementRoundedRectView!
	
	
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
	
	var announcementTime: Date = Date() {
		didSet {
			relativeTimeLabel.text = StringUtilities.relativeTimeString(forDate: announcementTime)
		}
	}
	
	var text: NSAttributedString = NSAttributedString() {
		didSet {
			announcementTextView.attributedText = text
			cellSizeChanged()
		}
	}
	
	override func awakeFromNib() {
		super.awakeFromNib()
		
		// Font styling
		announcementHeaderLabel.styleFor(.body)
		authorLabel.styleFor(.body)
		relativeTimeLabel.styleFor(.body)
		announcementTextView.styleFor(.body)

		// Every 10 seconds, update the post time.
		NotificationCenter.default.addObserver(forName: RefreshTimers.TenSecUpdateNotification, object: nil,
				queue: nil) { [weak self] notification in
    		if let self = self {
				self.relativeTimeLabel.text = StringUtilities.relativeTimeString(forDate: self.announcementTime)
			}
		}
	}
	
	// Handler for tapping on linktext. The textView is non-editable.
	func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange,  interaction: UITextItemInteraction) -> Bool {
		if let vc = viewController as? BaseCollectionViewController {
	 		vc.segueOrNavToLink(URL.absoluteString)
		}
        return false
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

//let announcementAlertColors: [String] = [
//	"Fuschia Alert",
//	"Chartreuse Alert",
//	"Violet Alert",
//	"Marmalade Alert"
//	"Scarlet Alert"
//	"Magenta Alert"
//	"Mauve Alert"]

