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
	@IBOutlet var performersContainerView: UIView!
	@IBOutlet var performersVisibleConstraint: NSLayoutConstraint!
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
	@IBOutlet var 	forumButton: UIButton!
	
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
		forumButton.styleFor(.body)

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
			animateIfNotPrototype(withDuration: 0.3, block: { self.setLabelStrings() })
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
				addObservation(eventModel.tell(self, when:"forumThreadID") { observer, observed in
					observer.setForumButtonState()
				}?.execute())
				addObservation(CurrentUser.shared.tell(self, when:"loggedInUser") { observer, observed in
					observer.setForumButtonState()
				}?.execute())
				
				addObservation(eventModel.tell(self, when: "performers") { (observer: EventCell, observed) in 
					observer.performersContainerView.subviews.forEach { $0.removeFromSuperview() }
					var lastCapsuleLine = [UIView]()
					observed.performers.enumerated().forEach { index, performerHeader in
						let performerCapsule = UIView()
						let nameLabel = UILabel()
						let imageView = UIImageView(image: UserManager.shared.noAvatarImage)
						performerCapsule.translatesAutoresizingMaskIntoConstraints = false
						nameLabel.translatesAutoresizingMaskIntoConstraints = false
						imageView.translatesAutoresizingMaskIntoConstraints = false

						nameLabel.text = performerHeader.name
						nameLabel.numberOfLines = 0
						nameLabel.lineBreakMode = .byWordWrapping
						performerCapsule.addSubview(nameLabel)
						performerCapsule.addSubview(imageView)
						NSLayoutConstraint.activate([ performerCapsule.topAnchor.constraint(equalTo: imageView.topAnchor, constant: 0),
								performerCapsule.leadingAnchor.constraint(equalTo: imageView.leadingAnchor, constant: 0),
								imageView.heightAnchor.constraint(equalToConstant: 24),
								imageView.widthAnchor.constraint(equalToConstant: 24)
						])
						let bottomConstraint = performerCapsule.bottomAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 0)
						bottomConstraint.priority = UILayoutPriority(rawValue: 700)
						bottomConstraint.isActive = true
						NSLayoutConstraint.activate([ performerCapsule.topAnchor.constraint(lessThanOrEqualTo: nameLabel.topAnchor, constant: 2.0),
								performerCapsule.bottomAnchor.constraint(greaterThanOrEqualTo: nameLabel.bottomAnchor, constant: 2.0),
								performerCapsule.trailingAnchor.constraint(equalTo: nameLabel.trailingAnchor, constant: 0),
								performerCapsule.widthAnchor.constraint(equalToConstant: 
										(observer.performersContainerView.frame.size.width - 10.0) / 2.0),
								imageView.trailingAnchor.constraint(equalTo: nameLabel.leadingAnchor, constant: -8)
						])
						if let imageFilename = performerHeader.imageFilename {
							ImageManager.shared.image(withSize:.medium, forKey: imageFilename) { image in
								imageView.image = image ?? UserManager.shared.noAvatarImage
								self.cellSizeChanged()
							}
						}
						observer.performersContainerView.addSubview(performerCapsule)
						if let lastCap = lastCapsuleLine.last {
							if index % 2 == 0 {
								NSLayoutConstraint.activate([
										observer.performersContainerView.leadingAnchor.constraint(equalTo: performerCapsule.leadingAnchor, constant: 0),
										lastCap.bottomAnchor.constraint(lessThanOrEqualTo: performerCapsule.topAnchor, constant: -8),
										])
								if let firstCap = lastCapsuleLine.first {
									firstCap.bottomAnchor.constraint(lessThanOrEqualTo: performerCapsule.topAnchor, constant: -8).isActive = true
								}
								lastCapsuleLine.removeAll()
							}
							else {
								NSLayoutConstraint.activate([
										lastCap.trailingAnchor.constraint(lessThanOrEqualTo: performerCapsule.leadingAnchor, constant: -10),
								//		observer.performersContainerView.trailingAnchor.constraint(equalTo: performerCapsule.trailingAnchor, constant: 0),
										lastCap.topAnchor.constraint(equalTo: performerCapsule.topAnchor, constant: 0)
										])
								let trail = observer.performersContainerView.trailingAnchor.constraint(equalTo: performerCapsule.trailingAnchor, constant: 0)
								trail.priority = UILayoutPriority(rawValue: 900)
								trail.isActive = true
							}
						}
						else {
							NSLayoutConstraint.activate([
									observer.performersContainerView.leadingAnchor.constraint(equalTo: performerCapsule.leadingAnchor, constant: 0),
									observer.performersContainerView.topAnchor.constraint(equalTo: performerCapsule.topAnchor, constant: -8)])
						}
						lastCapsuleLine.append(performerCapsule)
					}
					if let lastCap = lastCapsuleLine.last {
						let bottomConstraint = observer.performersContainerView.bottomAnchor.constraint(equalTo: lastCap.bottomAnchor, constant: 0)
						bottomConstraint.priority = UILayoutPriority(rawValue: 900)
						bottomConstraint.isActive = true
					}
				}?.execute())
			}
			else {
				setFollowState()
				setForumButtonState()
				performersContainerView.subviews.forEach { $0.removeFromSuperview() }
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
		if let eventModel = model as? Event, eventModel.startTime > cruiseCurrentDate() + 300.0 {
			enableButton = true
		}
		localNotificationButton.isEnabled = enableButton
	}
	
	func setForumButtonState() {
		if let eventModel = model as? Event {
			forumButton.isHidden = eventModel.forumThreadID == nil || !CurrentUser.shared.isLoggedIn()
		}
		else {
			forumButton.isHidden = true
		}
	}
	
	func setLabelStrings() {
		guard let event = model as? Event else { return }
		let effectiveDisclosure = privateSelected ? 4 : disclosureLevel
		UIView.animate(withDuration: 0.3, animations: { 
			self.titleLabel.text = event.title
			self.descriptionLabel.text = effectiveDisclosure > 3 ?  event.eventDescription : ""
			self.locationLabel.text = effectiveDisclosure > 2 ? event.location : ""
			self.eventTimeLabel.attributedText = effectiveDisclosure > 1 ? self.makeTimeString() : nil
			
			self.performersVisibleConstraint.priority = self.privateSelected ? UILayoutPriority(rawValue: 1) : UILayoutPriority(rawValue: 1000)
			self.layoutIfNeeded() 
		})
//		UIView.animate(withDuration: 0.3, animations: { self.layoutIfNeeded() } )

		setRibbonStates()
		cellSizeChanged()
	}
	
	func makeTimeString() -> NSAttributedString {
		let timeString = NSMutableAttributedString()
		let baseFont = eventTimeLabel.font ?? UIFont.systemFont(ofSize: 17.0)
		let baseAttrs = timeStringAttributes(baseFont: baseFont)
		let boatAttrs = timeStringBoatTimeAttributes(baseFont: baseFont)
		
		if let event = model as? Event {
			let dateFormatter = DateFormatter()
			dateFormatter.dateStyle = .short
			dateFormatter.timeStyle = .short
			dateFormatter.locale = Locale(identifier: "en_US")
			var includeDeviceTime = false
			if let serverTZ = ServerTime.shared.serverTimezone {
				dateFormatter.timeZone = serverTZ
				timeString.append(string: dateFormatter.string(from: event.startTime), attrs: baseAttrs)
				dateFormatter.dateStyle = .none
				timeString.append(string: " - \(dateFormatter.string(from: event.endTime))")

				if abs(ServerTime.shared.deviceTimeOffset + TimeInterval(ServerTime.shared.timeZoneOffset)) > 300.0 {
					timeString.append(string: " (Boat Time)\n", attrs: boatAttrs)
					includeDeviceTime = true
				}
			}
			else {
				includeDeviceTime = true
			}
			
			// If we're ashore and don't have access to server time (and, specifically, the server timezone),
			// OR we do have access and the serverTime is > 5 mins off of deviceTime, show device time.
			if includeDeviceTime {
				dateFormatter.timeZone = ServerTime.shared.deviceTimezone
				dateFormatter.dateStyle = .none
				timeString.append(string: "\(dateFormatter.string(from: event.startTime))", attrs: baseAttrs)
				timeString.append(string: " - \(dateFormatter.string(from: event.endTime))")
				timeString.append(string: " (Device Time)", attrs: boatAttrs)
			}
		}
		return timeString
	}
	
	func timeStringAttributes(baseFont: UIFont) -> [NSAttributedString.Key : Any] {
		let bodyAttrs: [NSAttributedString.Key : Any] = [ .font : baseFont as Any, 
				.foregroundColor : UIColor(named: "Kraken Label Text") as Any ]
		return bodyAttrs
	}

	func timeStringBoatTimeAttributes(baseFont: UIFont) -> [NSAttributedString.Key : Any] {
        let descriptor = baseFont.fontDescriptor.withSymbolicTraits(.traitItalic)
        let italicFont = UIFont(descriptor: descriptor!, size: 0) 
		let bodyAttrs: [NSAttributedString.Key : Any] = [ .font : italicFont as Any, 
				.foregroundColor : UIColor(named: "Kraken Secondary Text") as Any ]
		return bodyAttrs
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
			if !isInteractive { return }
			standardHighlightHandler()
		}
	}

	override var privateSelected: Bool {
		didSet {
			if !isInteractive { return }
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
   		if eventModel.localNotificationID != nil {
   			eventModel.cancelAlarmNotification()
   		}
   		else {
	   		eventModel.createLocalAlarmNotification(done: localNotificationCreated) 
		}
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
	
	@IBAction func forumButtonHit() {
		if let eventModel = model as? Event {
			// FIXME: Shortcut where we don't try loading the thead
			if let thread = eventModel.forum {
				dataSource?.performKrakenSegue(.showForumThread, sender: thread)
			}
			else if let threadID = eventModel.forumThreadID {
				dataSource?.performKrakenSegue(.showForumThread, sender: threadID)
			}
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
