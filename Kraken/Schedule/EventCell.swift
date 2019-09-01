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
	@objc dynamic var disclosureLevel: Int = 4
	@objc dynamic var specialHighlight: Bool = false
	
	var heightAtDisclosureLevel: [CGFloat] = []
	
	init(withModel: NSFetchRequestResult?) {
		super.init(withModel: withModel, reuse: "EventCell", bindingWith: EventCellBindingProtocol.self)
	}
	
	// This fn caches cell height at all disclosure levels from the 1 prototype cell. This prevents us from
	// doing an expensive recalc every time the disclosure level changes.
	override func makePrototypeCell(for collectionView: UICollectionView, indexPath: IndexPath) -> BaseCollectionViewCell? {
 //		let savedDisclosureLevel = disclosureLevel
 		let protoCell = super.makePrototypeCell(for: collectionView, indexPath: indexPath) as! EventCell
 		if disclosureLevel == 4 && heightAtDisclosureLevel.count < 4 {
			let newSize = protoCell.calculateSize()
			heightAtDisclosureLevel.removeAll()
			heightAtDisclosureLevel.append(newSize.height - protoCell.eventTimeLabel.bounds.size.height - 
					protoCell.locationLabel.bounds.size.height - protoCell.descriptionLabel.bounds.size.height)
			heightAtDisclosureLevel.append(newSize.height - protoCell.eventTimeLabel.bounds.size.height - 
					protoCell.locationLabel.bounds.size.height - protoCell.descriptionLabel.bounds.size.height)
			heightAtDisclosureLevel.append(newSize.height - protoCell.locationLabel.bounds.size.height - 
					protoCell.descriptionLabel.bounds.size.height)
			heightAtDisclosureLevel.append(newSize.height - protoCell.descriptionLabel.bounds.size.height)
			heightAtDisclosureLevel.append(newSize.height)
		}
		
 		return protoCell
	}

}

// Disclosure Levels
//
// 1: Title
// 2: Title, Time
// 3: Title, Time, Location
// 4: Title, Time, Location, Description, Official/Shadow
// Selected, 4+ action bar with Favorite, Set Notification, Make Calendar Event?

class EventCell: BaseCollectionViewCell, EventCellBindingProtocol {
	@IBOutlet var titleLabel: UILabel!
	@IBOutlet var eventTimeLabel: UILabel!
	@IBOutlet var locationLabel: UILabel!
	@IBOutlet var descriptionLabel: UILabel!
	@IBOutlet var ribbonView: RibbonView!
	@IBOutlet var ribbonViewLabel: UILabel!
	
	private static let cellInfo = [ "EventCell" : PrototypeCellInfo("EventCell") ]
	override class var validReuseIDDict: [ String: PrototypeCellInfo] { return EventCell.cellInfo }


// MARK: Methods	
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
	
	var disclosureLevel: Int = 4 {
		didSet {
			isPrototypeCell ? setLabelStrings() : UIView.animate(withDuration: 0.3, animations: setLabelStrings)
			cellSizeChanged()
		}
	}

	var specialHighlight: Bool = false

	var model: NSFetchRequestResult? {
		didSet {
			setLabelStrings()
		}
	}
	
	func setLabelStrings() {
		guard let event = model as? Event else { return }
		let effectiveDisclosure = privateSelected ? 4 : disclosureLevel
		titleLabel.text = event.title
		descriptionLabel.text = effectiveDisclosure > 3 ?  event.eventDescription : ""
		locationLabel.text = effectiveDisclosure > 2 ? event.location : ""
		eventTimeLabel.text = effectiveDisclosure > 1 ? makeTimeString() : ""
		setRibbonStates()

		cellSizeChanged()
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
				ribbonView.ribbonColor = UIColor(red: 167.0 / 255.0, green: 0.0, blue: 180.0 / 255.0, alpha: 1.0)
				ribbonViewLabel.text = "Now"
				ribbonViewLabel.backgroundColor = ribbonView.ribbonColor
				ribbonViewLabel.textColor = UIColor.white
				ribbonView.useStripes = event.isAllDayTypeEvent()
				ribbonView.setNeedsDisplay()
			}
			else if event.isHappeningSoon() {
				ribbonView.isHidden = false
				ribbonView.ribbonColor = UIColor(red: 250.0 / 255.0, green: 250.0 / 255.0, blue: 50.0 / 255.0, alpha: 1.0)
				ribbonViewLabel.text = "Soon"
				ribbonViewLabel.backgroundColor = ribbonView.ribbonColor
				ribbonViewLabel.textColor = UIColor.black
				ribbonView.useStripes = event.isAllDayTypeEvent()
				ribbonView.setNeedsDisplay()
			}
			else {
				ribbonView.isHidden = true
			}
		}
		else {
			ribbonView.isHidden = true
		}
	}
	
	override func calculateSize() -> CGSize {
		let size: CGSize
		if let model = cellModel as? EventCellModel, model.heightAtDisclosureLevel.count >= 4 {
			let effectiveDisclosure = privateSelected ? 4 : disclosureLevel
			size = CGSize(width: dataSource?.collectionView?.bounds.size.width ?? bounds.size.width,
					height: model.heightAtDisclosureLevel[effectiveDisclosure])
		}
		else {
			size = super.calculateSize()
		}

		return size
	}

	
	var highlightAnimation: UIViewPropertyAnimator?
	override var isHighlighted: Bool {
		didSet {
			if let oldAnim = highlightAnimation {
				oldAnim.stopAnimation(true)
			}
			let anim = UIViewPropertyAnimator(duration: 0.2, curve: .easeInOut) {
				self.contentView.backgroundColor = self.isHighlighted || self.privateSelected ? UIColor(white:0.95, alpha: 1.0) : UIColor.white
			}
			anim.isUserInteractionEnabled = true
			anim.isInterruptible = true
			anim.startAnimation()
			highlightAnimation = anim
		}
	}

	override var privateSelected: Bool {
		didSet {
			if !isPrototypeCell, privateSelected == oldValue { return }
			setLabelStrings()
			contentView.backgroundColor = privateSelected ? UIColor(white: 0.95, alpha: 1.0) : UIColor.white
		}
	}
}

class RibbonView: UIView {
	var useStripes: Bool = true
	var ribbonColor: UIColor?

	override func draw(_ rect: CGRect) {
		let context = UIGraphicsGetCurrentContext()!

		if useStripes {
			context.setFillColor(UIColor.white.cgColor)
			context.fill(rect)
		
			let viewWidth = bounds.size.width
			context.setFillColor(ribbonColor?.cgColor ?? UIColor.white.cgColor)
			context.fill(CGRect(x: bounds.origin.x, y: bounds.origin.y, width: bounds.size.width, height: 8))
			var yPos = bounds.origin.y
			let shearTransform = CGAffineTransform(a: 1.0, b: 1.0, c: 0.0, d: 1.0, tx: 0.0, ty: 0.0)
			context.concatenate(shearTransform)
			while yPos < bounds.maxY {
				context.fill(CGRect(x: 0, y: yPos, width: viewWidth, height: viewWidth))
				yPos += viewWidth * 2
			}
		}
		else {
			context.setFillColor(ribbonColor?.cgColor ?? UIColor.white.cgColor)
			context.fill(rect)
		}
	}
}
