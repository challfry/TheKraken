//
//  EventCell.swift
//  Kraken
//
//  Created by Chall Fry on 8/13/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit
import EventKit
import EventKitUI
import UserNotifications

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
	var cachedTraitCollectionSizeClass: UIContentSizeCategory?
	
	init(withModel: NSFetchRequestResult?) {
		super.init(withModel: withModel, reuse: "EventCell", bindingWith: EventCellBindingProtocol.self)
	}
	
	// The datasouce calls this fn when it needs to know the cell size. We cache cell sizes at all the disclosure
	// levels, and can set cellSize appropriately when the level changes. But if the cache has gone stale, 
	// we return 0, 0 so the datasource will do a full re-calc.
	override func updateCachedCellSize(for collectionView: UICollectionView) {
		if cachedTraitCollectionSizeClass == collectionView.traitCollection.preferredContentSizeCategory,
				heightAtDisclosureLevel.count >= 4, !privateSelected {
	 		let height = heightAtDisclosureLevel[disclosureLevel]
			cellSize = CGSize(width: cellSize.width, height: height)
		}
		else {
			cellSize = CGSize(width: 0, height: 0)
		}
	}
	
	// This fn caches cell height at all disclosure levels from the 1 prototype cell. This prevents us from
	// doing an expensive recalc every time the disclosure level changes.
	override func makePrototypeCell(for collectionView: UICollectionView, indexPath: IndexPath) -> BaseCollectionViewCell? {
 		let protoCell = super.makePrototypeCell(for: collectionView, indexPath: indexPath) as! EventCell
 		
 		// If the size class changes, we need to dump the cache as it's no longer fresh.
 		if cachedTraitCollectionSizeClass != collectionView.traitCollection.preferredContentSizeCategory {
			heightAtDisclosureLevel.removeAll()
			cachedTraitCollectionSizeClass = nil
 		}
 		
 		// We only create the cache at full disclosure. This way, we can use the protoCell metrics to calculate
 		// the cell size at all the other disclosure levels.
 		if disclosureLevel == 4 && heightAtDisclosureLevel.count < 4 {
			let newSize = protoCell.calculateSize()
			heightAtDisclosureLevel.removeAll()
			
			let timeSize = protoCell.eventTimeLabel.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
			let locationSize = protoCell.locationLabel.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
			let descriptionSize = protoCell.descriptionLabel.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)

			heightAtDisclosureLevel.append(newSize.height - timeSize.height - locationSize.height - 
					descriptionSize.height)
			heightAtDisclosureLevel.append(newSize.height - timeSize.height - locationSize.height - 
					descriptionSize.height)
			heightAtDisclosureLevel.append(newSize.height - locationSize.height - descriptionSize.height)
			heightAtDisclosureLevel.append(newSize.height - descriptionSize.height)
			heightAtDisclosureLevel.append(newSize.height)
			
			// Save the size class that we used when building the cache
			cachedTraitCollectionSizeClass = collectionView.traitCollection.preferredContentSizeCategory
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
	@IBOutlet var followLabel: UILabel!
	@IBOutlet var eventTimeLabel: UILabel!
	@IBOutlet var locationLabel: UILabel!
	@IBOutlet var descriptionLabel: UILabel!
	@IBOutlet var ribbonView: RibbonView!
	@IBOutlet var ribbonViewLabel: UILabel!
	
	@IBOutlet var followPendingView: UIView!
	@IBOutlet var 	followPendingLabel: UILabel!
	@IBOutlet var	followPendingCancelButton: UIButton!
	
	
	@IBOutlet var actionBarView: UIView!
	@IBOutlet var 	followButton: UIButton!
	@IBOutlet var 	localNotificationButton: UIButton!
	@IBOutlet var 	addToCalendarButton: UIButton!
	@IBOutlet var 	mapButton: UIButton!
	
	private static let cellInfo = [ "EventCell" : PrototypeCellInfo("EventCell") ]
	override class var validReuseIDDict: [ String: PrototypeCellInfo] { return EventCell.cellInfo }


// MARK: Methods	
	override func awakeFromNib() {
		super.awakeFromNib()
		allowsSelection = true

		// Font styling
		titleLabel.styleFor(.body)
		followLabel.styleFor(.body)
		eventTimeLabel.styleFor(.body)
		locationLabel.styleFor(.body)
		descriptionLabel.styleFor(.body)
		ribbonViewLabel.styleFor(.body)
		followPendingLabel.styleFor(.body)
		followPendingCancelButton.styleFor(.body)
		followButton.styleFor(.body)
		localNotificationButton.styleFor(.body)
		addToCalendarButton.styleFor(.body)
		mapButton.styleFor(.body)

		// Set up the ribbon view -- the colored label on the left edge
		ribbonViewLabel.layer.anchorPoint = CGPoint(x: 0.0, y: 0.0)
		ribbonViewLabel.transform = CGAffineTransform(rotationAngle: .pi / 2)
		
		// Every 10 seconds, update the ribbon
		NotificationCenter.default.addObserver(forName: RefreshTimers.TenSecUpdateNotification, object: nil,
				queue: nil) { [weak self] notification in
			self?.setRibbonStates()
		}
		
		// Make sure the action bar starts off hidden, even if we unhide it in IB.
		actionBarView.isHidden = true
		followPendingView.isHidden = true
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
    		clearObservations()
			setLabelStrings()

			// Observe following state, set heart label visibility
			if let eventModel = model as? Event {
				addObservation(CurrentUser.shared.tell(self, when: "loggedInUser") { observer, observed in
					observer.setFollowState()
				})
				addObservation(eventModel.tell(self, when:"followCount") { observer, observed in
					observer.setFollowState()
				}?.execute())
				addObservation(eventModel.tell(self, when:"opsFollowingCount") { observer, observed in
					observer.setFollowPendingState()
				}?.execute())
				addObservation(eventModel.tell(self, when:"ekEventID") { observer, observed in
					let title = observed.ekEventID == nil ? "Add To Calendar" : "Edit Calendar Event"
					observer.addToCalendarButton.setTitle(title, for: .normal)
				}?.execute())
				addObservation(eventModel.tell(self, when:"localNotificationID") { observer, observed in
					let title = observed.localNotificationID == nil ? "Set Alarm" : "Remove Alarm"
					observer.localNotificationButton.setTitle(title, for: .normal)
				}?.execute())
				addObservation(eventModel.tell(self, when:"location") { observer, observed in
					// Hides the map buton for events with no location, and events that are "Whole Ship"
					if let title = observed.location {
						observer.mapButton.isHidden = (title == "Whole Ship" || title == "")
					}
					else {
						observer.mapButton.isHidden = true
					}
				}?.execute())
			}
			else {
				setFollowState()
			}
		}
	}
	
	func setFollowState() {	
		if let eventModel = model as? Event, let currentUser = CurrentUser.shared.loggedInUser,
				eventModel.followedBy.contains( where: { user in user.username == currentUser.username }) {
			followLabel.isHidden = false
			followButton.setTitle("Unfollow", for: .normal)
		} 
		else {
			followLabel.isHidden = true
			followButton.setTitle("Follow", for: .normal)
		}
	}
	
	func setAlarmButtonState() {
		var enableButton = false
		if Settings.shared.debugTestLocalNotificationsForEvents {
			enableButton = true
		}
		if let eventModel = model as? Event, let startTime = eventModel.startTime, startTime > Date() + 300.0 {
			enableButton = true
		}
		localNotificationButton.isEnabled = enableButton
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
	
	func setFollowPendingState() {
		var newState = true
		if privateSelected == true, 
				let currentUser = CurrentUser.shared.loggedInUser, 
				let event = model as? Event,
				let op = event.opsFollowing.first(where: { $0.author.username == currentUser.username }) {
			followPendingLabel.text = op.newState ? "Follow Pending" : "Unfollow Pending"
			newState = false
		}
		
		if newState != followPendingView.isHidden {
			UIView.animate(withDuration: 0.3) {
				self.followPendingView.isHidden = newState
			}
		}
	}
	
	override func calculateSize() -> CGSize {
		let size: CGSize
		if let model = cellModel as? EventCellModel, model.heightAtDisclosureLevel.count >= 4, !privateSelected {
			let effectiveDisclosure = privateSelected ? 4 : disclosureLevel
			size = CGSize(width: dataSource?.collectionView?.bounds.size.width ?? bounds.size.width,
					height: model.heightAtDisclosureLevel[effectiveDisclosure])
		}
		else {
			size = super.calculateSize()
		}

		return size
	}

	
	override var isHighlighted: Bool {
		didSet {
			standardHighlightHandler()
		}
	}

	override var privateSelected: Bool {
		didSet {
			if !isPrototypeCell, privateSelected == oldValue { return }
			standardSelectionHandler()
			
			actionBarView.isHidden = !privateSelected
			
			// Upon selection we actually check the linked calendar event and local notification to see whether they're 
			// still there.
			if let event = model as? Event {
				event.verifyLinkedCalendarEvent()
				event.verifyLinkedLocalNotification()
			}

			setLabelStrings()
			setAlarmButtonState()
			setFollowPendingState()
			cellSizeChanged()
		}
	}
	
// MARK: Actions
	// Followed, favorited, liked. 
	@IBAction func favoriteButtonHit() {
 		guard isInteractive else { return }
   		guard let eventModel = model as? Event else { return } 
   		
   		var alreadyLikesThis = false
		if let currentUser = CurrentUser.shared.loggedInUser,
				eventModel.followedBy.contains(where: { user in return user.username == currentUser.username }) {
			alreadyLikesThis = true
		}

		if !CurrentUser.shared.isLoggedIn() {
 			let seguePackage = LoginSegueWithAction(promptText: "In order to follow this Schedule event, you'll need to log in first.",
 					loginSuccessAction: { eventModel.addFollowOp(newState: true) }, loginFailureAction: nil)
  			dataSource?.performKrakenSegue(.modalLogin, sender: seguePackage)
   		}
   		else {
			eventModel.addFollowOp(newState: !alreadyLikesThis)
   		}
	}
	
	@IBAction func cancelFavoriteOpButtonHit() {
   		guard let eventModel = model as? Event else { return } 
   		eventModel.cancelFollowOp()
	}
	
	@IBAction func setAlarmButtonHit() {
   		guard let eventModel = model as? Event else { return }
   		eventModel.createLocalAlarmNotification(done: localNotificationCreated) 
	}
	
	func localNotificationCreated(notification: UNNotificationRequest) {
		guard let trigger = notification.trigger as? UNTimeIntervalNotificationTrigger, 
				let alarmTime = trigger.nextTriggerDate() else { return }

		let dateFormatter = DateFormatter()
		dateFormatter.dateStyle = .none
		dateFormatter.timeStyle = .short
		dateFormatter.locale = Locale(identifier: "en_US")
		let timeString = dateFormatter.string(from: alarmTime)
		
		let alert = UIAlertController(title: "Reminder Alarm Set", 
				message: "You'll receive a notification at \(timeString), 5 minutes before the event starts." , preferredStyle: .alert)
		alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
		if let topVC = UIApplication.getTopViewController() {
			topVC.present(alert, animated: true, completion: nil)
		}
	}
	
	@IBAction func addToCalendarButtonHit() {
   		guard let eventModel = model as? Event else { return } 
   		eventModel.createCalendarEvent(done: eventCreated)
	}
	
	// Called when Add To Calendar successfully makes its event
	func eventCreated(event: EKEvent?) {
		guard let ev = event else { return }
		DispatchQueue.main.async {
			let vc = EKEventViewController(nibName: nil, bundle: nil)
			vc.allowsEditing = true
			vc.allowsCalendarPreview = true
//			let vc = EKEventEditViewController(nibName: nil, bundle: nil)
			vc.event = ev
			vc.delegate = self
 			let nav = UINavigationController(rootViewController: vc)
			self.viewController?.present(nav, animated: true, completion: nil)
		}
	}
	
	@IBAction func mapButtonHit() {
		if let eventModel = model as? Event, let locationName = eventModel.location {
			dataSource?.performKrakenSegue(.showRoomOnDeckMap, sender: locationName)
		}
	}
	
}

extension EventCell: EKEventViewDelegate {
	func eventViewController(_ controller: EKEventViewController, didCompleteWith action: EKEventViewAction) {
		self.viewController?.dismiss(animated: true, completion: nil)
		if action == .deleted, let eventModel = model as? Event {
			eventModel.markCalendarEventDeleted()
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
