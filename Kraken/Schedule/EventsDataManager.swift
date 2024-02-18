//
//  EventsDataManager.swift
//  Kraken
//
//  Created by Chall Fry on 8/12/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit
import EventKit
import UserNotifications
import CoreData

@objc(Event) public class Event: KrakenManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var title: String
	@NSManaged public var eventDescription: String?
	@NSManaged public var location: String?
    @NSManaged public var eventType: String
	@NSManaged public var startTime: Date
	@NSManaged public var endTime: Date
	@NSManaged public var forumThreadID: UUID?
    
    // Note that both the linked Calendar Event and the linked Local Notification are NOT gated on the logged in user!
    // Both of these are local to the device we're running on, and not attached to the Twitarr user!
    @NSManaged public var ekEventID: String?				// EventKit calendar item for this event, if any.
    @NSManaged public var localNotificationID: String?		// Local Notification alert for this event, if any.
  
// Relations
    @NSManaged public var followedBy: Set<KrakenUser>
    @NSManaged public var opsFollowing: Set<PostOpEventFollow>
    @NSManaged public var forum: ForumThread?

// Not saved in CD    
    @objc dynamic public var followCount: Int = 0
    @objc dynamic public var opsFollowingCount: Int = 0
    
	override public func awakeFromInsert() {
		super.awakeFromInsert()
		id = UUID()
	}

	public override func awakeFromFetch() {
		super.awakeFromFetch()

		// Update derived properties
		followCount = followedBy.count
		opsFollowingCount = opsFollowing.count
	}
	
	// TRUE if this event lasts longer than 2 hours. Could be improved in the future, with server support.
	// The purpose of this fn is really to discriminate between events where you can show up anytime and events
	// where you should attend the entire thing from the start.
	public func isAllDayTypeEvent() -> Bool {
		if endTime.timeIntervalSince(startTime) >= 2 * 60 * 60 + 10 {
			return true
		}
		return false
	}
	
	public func isHappeningNow() -> Bool {
		var currentTime = cruiseCurrentDate()
		if Settings.shared.debugTimeWarpToCruiseWeek {
			currentTime = Date(timeInterval: EventsDataManager.shared.debugEventsTimeOffset, since: currentTime)
		}
		
		if startTime.compare(currentTime) == .orderedAscending && endTime.compare(currentTime) == .orderedDescending {
			return true
		}
		
		return false
	}
	
	public func isHappeningSoon(within: TimeInterval = 60.0 * 60.0) -> Bool {
		var currentTime = cruiseCurrentDate()
		if Settings.shared.debugTimeWarpToCruiseWeek {
			currentTime = Date(timeInterval: EventsDataManager.shared.debugEventsTimeOffset, since: currentTime)
		}
		
		let searchEndTime = Date(timeInterval: within, since: currentTime)
		if startTime.compare(currentTime) == .orderedDescending && startTime.compare(searchEndTime) == .orderedAscending {
			return true
		}
		
		return false
	}
	
	func buildFromV3(context: NSManagedObjectContext, v3Object: TwitarrV3EventData) throws {
		TestAndUpdate(\.id, v3Object.eventID)
		TestAndUpdate(\.title, v3Object.title)
		TestAndUpdate(\.eventDescription, v3Object.description.decodeHTMLEntities())
		TestAndUpdate(\.location, v3Object.location)
		TestAndUpdate(\.eventType, v3Object.eventType)
		TestAndUpdate(\.startTime, v3Object.startTime)
		TestAndUpdate(\.endTime, v3Object.endTime)
		TestAndUpdate(\.forumThreadID, v3Object.forum)

		if let currentUser = CurrentUser.shared.getLoggedInUser(in: context) {
			setFavoriteState(context: context, user: currentUser, to: v3Object.isFavorite)
		}

		// Try to associate the event to its thread
		if let threadID = forumThreadID, forum?.id != threadID {
			let request = NSFetchRequest<ForumThread>(entityName: "ForumThread")
			request.predicate = NSPredicate(format: "id == %@", threadID as CVarArg)
			let cdThreads = try request.execute()
			if let foundThread = cdThreads.first {
				forum = foundThread
			}
		}			
	}
	
	func setFavoriteState(context: NSManagedObjectContext, user: KrakenUser, to newState: Bool) {
		if followedBy.contains(user) {
			if !newState {
				followedBy.remove(user)
				followCount = followedBy.count
			}
		}
		else if newState {
			followedBy.insert(user)
			followCount = followedBy.count
		}
	}
	
// MARK: Event Operations
	
	func addFollowOp(newState: Bool) {
		let context = LocalCoreData.shared.networkOperationContext
		context.perform {
			guard let currentUser = CurrentUser.shared.getLoggedInUser(in: context),
					let thisEvent = context.object(with: self.objectID) as? Event else { return }
			
			// Check for existing op for this user
			var existingOp: PostOpEventFollow?
			for op in thisEvent.opsFollowing {
				if op.author.username == currentUser.username {
					existingOp = op
				}
			}
			if existingOp == nil {
				existingOp = PostOpEventFollow(context: context)
			}
			
			existingOp?.newState = newState
			existingOp?.operationState = .readyToSend
			existingOp?.event = thisEvent
			
			do {
				try context.save()
				self.opsFollowingCount = self.opsFollowing.count
			}
			catch {
				CoreDataLog.error("Couldn't save context.", ["error" : error])
			}
		}
	}
	
	func cancelFollowOp() {
		guard let currentUsername = CurrentUser.shared.loggedInUser?.username else { return }
		if let deleteOp = opsFollowing.first(where: { $0.author.username == currentUsername }) {
			PostOperationDataManager.shared.remove(op: deleteOp)
			self.opsFollowingCount = self.opsFollowing.count
		}
	}
	
	// Only calls the done callback on successful creation, which implies access was granted.
	var createCalendarEventDoneCallback: ((EKEvent?) -> ())?
	func createCalendarEvent(done: @escaping (EKEvent?) -> Void) {
		let eventStore = EventsDataManager.shared.ekEventStore
		createCalendarEventDoneCallback = done
		if #available(iOS 17, *) {
			eventStore.requestFullAccessToEvents() { access, error in 
				DispatchQueue.main.async {
					self.calendarAccessCallback(access, error)
				}
			}
		}
		else {
			eventStore.requestAccess(to: .event) { access, error in 
				DispatchQueue.main.async {
					self.calendarAccessCallback(access, error)
				}
			}
		}
	}

	private func calendarAccessCallback(_ access: Bool, _ error: Error?) {
		guard access else { 
			showDelayedTextAlert(title: "No Calendar Access", message: "Calendar access is dsabled. You can reenable it in Settings.")
			return
		}
		let eventStore = EventsDataManager.shared.ekEventStore
		var calendar: EKCalendar?
		do {
			// Is our saved calendar still around?
			if let calendarID = Settings.shared.customCalendarForEvents {
				calendar = eventStore.calendar(withIdentifier: calendarID)
			}
			if calendar == nil {
				let newCalendar = EKCalendar(for: .event, eventStore: eventStore)
 				newCalendar.title = "JoCo Cruise 2024"
				if eventStore.sources.count == 0 {
					newCalendar.source = EKSource()
				}
				else if let defaultCal = eventStore.defaultCalendarForNewEvents {
					newCalendar.source = defaultCal.source
				}
				else {
					newCalendar.source = eventStore.sources.first { $0.sourceType.rawValue == EKSourceType.local.rawValue }
				}
				try eventStore.saveCalendar(newCalendar, commit: true)
				calendar = newCalendar
				Settings.shared.customCalendarForEvents = newCalendar.calendarIdentifier
			}
		}
		catch {
			showErrorAlert(title: "Couldn't create JoCo Calendar in Calendar database.", error: error)
		}
		guard let cal = calendar else { return }
		
		// Look for an existing event first. Note that we don't update an calendar event's data after creation. 
		// If the JoCo Schedule changes, an already-created event won't update. 
		var theEvent: EKEvent?
		if let existingID = ekEventID {
			theEvent = eventStore.event(withIdentifier: existingID)
		}
		if theEvent == nil {
			do {
				// Make a new event, save it to the event store.		
				let ekEvent = EKEvent(eventStore: eventStore)
				ekEvent.startDate = startTime
				ekEvent.endDate = endTime
				ekEvent.isAllDay = false 			// Even JocCo's 'all day' events aren't all day.
				if ekEvent.calendar == nil {
					ekEvent.calendar = cal
				}
				ekEvent.title = title
				ekEvent.location = location
				
				// Pretty sure Calendar events should be 'floating'. That is, without a timezone specified. As I understand it,
				// ekCalendar--at the time we store the event--takes a startTime that maps to 4:00 PM in the current timezone,
				// and converts it into something like a DateComponents with a meaning of "4:00 PM Local Time". If the timezone
				// changes later, the event will still claim to occur at 4:00 PM in the new timezone.
//				newEvent.timeZone = 
				ekEvent.url = URL(string: "\(Settings.shared.baseURL)/#/schedule/event/\(id)")
				
				// Append a Kraken link to the event description
				let descPlusLink = "\(eventDescription ?? "")\n\nOpen this event in Kraken with: kraken://events?eventID=\(id)"
				ekEvent.notes = descPlusLink
		
				try eventStore.save(ekEvent, span: .thisEvent)
				theEvent = ekEvent
			}
			catch {
				showErrorAlert(title: "Couldn't create JoCo Calendar in Calendar database.", error: error)
			}
		}
		
		// Save the eventID if necessary
		let eventIdentifier = theEvent?.eventIdentifier
		if self.ekEventID != eventIdentifier {
			let context = LocalCoreData.shared.networkOperationContext
			context.perform {
				do {
					if let selfInContext = try context.existingObject(with: self.objectID) as? Event {
						selfInContext.ekEventID = eventIdentifier
					}
					
					try context.save()
				}
				catch {
					CoreDataLog.error("Couldn't save context.", ["error" : error])
				}
			}
		}

		createCalendarEventDoneCallback?(theEvent)
		createCalendarEventDoneCallback = nil
	}
	
	// When the event in the Calendar app has been deleted, call this to clear our eventID for it.
	func markCalendarEventDeleted() {
		let context = LocalCoreData.shared.networkOperationContext
		context.perform {
			do {
				if let selfInContext = try context.existingObject(with: self.objectID) as? Event {
					selfInContext.ekEventID = nil
				}
				try context.save()
			}
			catch {
				CoreDataLog.error("Couldn't save context.", ["error" : error])
			}
		}
	}
	
	// Checks if the EKEvent linked from the ekEventID is still valid. Sets ekEventID to nil if the underlying event is gone.
	// Note that the user can delete the event from whithin the Calendar app, so the existence of the link doesn't guarantee
	// there's an event there.
	func verifyLinkedCalendarEvent() {
		guard let linkedEvent = ekEventID else { return }
		var deleteLink = false
		if  EKEventStore.authorizationStatus(for: .event) == .authorized {
			let ekEvent = EventsDataManager.shared.ekEventStore.event(withIdentifier: linkedEvent)
			if ekEvent == nil {
				deleteLink = true
			}
		}
		else {
			deleteLink = true
		}
		
		if deleteLink {
			markCalendarEventDeleted()
		}
	}
		
	func createLocalAlarmNotification(done: @escaping (UNNotificationRequest) -> Void) {
		let center = UNUserNotificationCenter.current()
		center.requestAuthorization(options: [.alert, .sound]) { (granted, error) in
			if granted {
				self.createLocalAlarmAuthCallback(done: done)
			}
		}
	}
	
	private func createLocalAlarmAuthCallback(done: @escaping (UNNotificationRequest) -> Void) {	
		let content = UNMutableNotificationContent()
		content.title = "JoCo Cruise Event Reminder"
		content.body = "\"\(title)\" starts in 5 minutes!"
		content.userInfo = ["eventID" : id]
		
		var alarmTime: Date
		if Settings.shared.debugTestLocalNotificationsForEvents {
			alarmTime = Date() + 10.0 
		}
		else {
			alarmTime = startTime - 300.0
		}
		
//		let tz = TimeZone.current
//		let dateComponents = Calendar(identifier: .gregorian).dateComponents(in: tz, from: alarmTime)
//		let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
		let trigger = UNTimeIntervalNotificationTrigger(timeInterval: alarmTime.timeIntervalSinceNow, repeats: false)

		let uuidString = UUID().uuidString
		let request = UNNotificationRequest(identifier: uuidString, content: content, trigger: trigger)

		// Schedule the request with the system.
		let notificationCenter = UNUserNotificationCenter.current()
		notificationCenter.add(request) { (error) in
			if error != nil {
				CoreDataLog.error("Couldn't create local notification for Event start time.", 
						["error" : error?.localizedDescription as Any])
			}
			else {
				let context = LocalCoreData.shared.networkOperationContext
				context.perform {
					do {
						if let selfInContext = try context.existingObject(with: self.objectID) as? Event {
							selfInContext.localNotificationID = uuidString
						}
						try context.save()
					}
					catch {
						CoreDataLog.error("Couldn't save context.", ["error" : error])
					}
				}
				
				// Even if the CD save fails, the notification is scheduled if we get this far.
				DispatchQueue.main.async {
					done(request)
				} 
			}
		}
	}
	
	// Checks whether the notification is still scheduled. Deletes the UUID if it's deleted or already fired.
	func verifyLinkedLocalNotification() {
		guard let uuidString = localNotificationID else { return }
		
		// TODO: Not sure what happens if authorization is turned off. Hopefully, we can still ask about our pending 
		// notifications and get results back, they just won't ever fire?
		let notificationCenter = UNUserNotificationCenter.current()
		notificationCenter.getPendingNotificationRequests { requests in
			let notificationExists = requests.contains { $0.identifier == uuidString }
			if !notificationExists {
				self.markLocalNotificationDeleted()
			}
		}
	}
		
	// Cancels the notification before it fires.
	func cancelAlarmNotification() {
		if let notificationID = localNotificationID {
			UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [notificationID])
			markLocalNotificationDeleted()
		}
	}
	
	// Called when we receive the notification callback -- when the notification fires.
	func markLocalNotificationDeleted() {
		LocalCoreData.shared.performNetworkParsing { context in
			context.pushOpErrorExplanation("Failure saving change to a Scheduled Ship Event Notification. (the network call succeeded, but we couldn't save the change).")
			if let selfInContext = try context.existingObject(with: self.objectID) as? Event {
				selfInContext.localNotificationID = nil
			}
		}
	}
}




// MARK: -
class EventsDataManager: NSObject {
	static let shared = EventsDataManager()
	private let coreData = LocalCoreData.shared
	fileprivate let ekEventStore = EKEventStore()
		
	// This is how much time to add to the current time to use the cruise schedule. Will be negative if the Schedule
	// is for a previous year. To use: Date() + debugEventTimeOffset -> current time of day and day of week, but date and year 
	// match the week of the Schedule data.
	var debugEventsTimeOffset: TimeInterval = 0.0
	
	// TRUE when we've got a network call running to update the stream, or the current filter.
	@objc dynamic var networkUpdateActive: Bool = false  

	
// MARK: Methods

	override init() {
		// Just once, calc our debug date offset. This is an offset from the current date to give us a date covered by the Schedule.ics file.
		if let lastCruiseEndDate = lastCruiseEndDate() {
			var checkDate = cruiseCurrentDate()
			while checkDate > lastCruiseEndDate {
				if let newDate = Calendar(identifier: .gregorian).date(byAdding: .day, value: -7, to: checkDate) {
					checkDate = newDate
				}
				else {
					break
				}
			}
			debugEventsTimeOffset = checkDate.timeIntervalSince(cruiseCurrentDate())
		}
	}
	
	// Initiates a network load of Schedule events if CD has no events, or if it's been > 1 hour since the last time we checked.
	func refreshEventsIfNecessary() {
		if networkUpdateActive { return }
		
		var needToUpdate = false 
		if Settings.shared.lastEventsUpdateTime.timeIntervalSinceNow < 0 - 60 * 60 {
			needToUpdate = true
		}
		else {
			let fetchRequest = NSFetchRequest<Event>(entityName: "Event")
			let eventCount = (try? coreData.mainThreadContext.count(for: fetchRequest)) ?? 0
			needToUpdate = needToUpdate || eventCount == 0
		}
				
		if needToUpdate {
			// LoadEvents will update the lastEventsUpdateTime when it succeeds.
			loadEvents()
		}
	}
		
	func loadEvents() {
		let path = "/api/v3/events"
		var request = NetworkGovernor.buildTwittarRequest(withPath:path, query: nil)
		NetworkGovernor.addUserCredential(to: &request)
		networkUpdateActive = true
		NetworkGovernor.shared.queue(request) { (package: NetworkResponse) in
			self.networkUpdateActive = false
			if let data = package.data {
//				print (String(decoding:data!, as: UTF8.self))
				let decoder = JSONDecoder()
				do {
					decoder.dateDecodingStrategy = .custom(StringUtilities.parseISO8601DateString)
					let eventResponse = try decoder.decode(TwitarrV3EventResponse.self, from: data)
					self.parseV3Events(eventResponse, isFullList: true)
					Settings.shared.lastEventsUpdateTime = Date()
				} catch 
				{
					NetworkLog.error("Failure parsing Schedule events.", ["Error" : error, "URL" : request.url as Any])
				} 
			}
			
			// TODO: Should probably add code here so that, in the case where the load fails due to network or
			// server errors, we remember it happened and can display a cell telling the user either we don't have
			// events data yet or we do have data but it's out of date.
		}
	}
		
	// pass TRUE for isFullList if events is a comprehensive list of all events; this causes deletion of existing events
	// not in the new list. Otherwise it only adds/updates events.
	func parseV3Events(_ events: [TwitarrV3EventData], isFullList: Bool) {
		LocalCoreData.shared.performNetworkParsing { context in
			context.pushOpErrorExplanation("Failure adding Schedule events from network response to Core Data.")
			let fetchRequest = NSFetchRequest<Event>(entityName: "Event")
			let cdEvents = try? context.fetch(fetchRequest)

			if isFullList {
				// Delete events not in the new event list
				let newEventIds = Set(events.map( { $0.eventID } ))
				cdEvents?.forEach { cdEvent in
					if !newEventIds.contains(cdEvent.id) {
						context.delete(cdEvent)
					}
				}
			}
		
			// Add/update
			for v3Event in events {
				let eventInContext = cdEvents?.first(where: { $0.id == v3Event.eventID }) ?? Event(context: context)
				try eventInContext.buildFromV3(context: context, v3Object: v3Event)
			}
				
			self.getAllLocations()
		}
	}
	
	func setEventFavorite(_ event: Event, to newState: Bool, for user: KrakenUser) {
		LocalCoreData.shared.performNetworkParsing { context in
			context.pushOpErrorExplanation("Failure saving new Schedule Event to Core Data. Was setting follow state on event.")
			let eventInContext = try context.existingObject(with: event.objectID) as! Event
			let userInContext = try context.existingObject(with: user.objectID) as! KrakenUser
			eventInContext.setFavoriteState(context: context, user: userInContext, to: newState)
		}
	}
		
	// Processes the events data to build a list of locations, asynchronously. Works by simply putting all
	// event locations into a set, so near-identical names for the same place won't get uniqued.
	// AllLocations, once it gets set, is sorted alphabetically by location name.
	var allLocations: [String] = []
	func getAllLocations() {
		let context = coreData.networkOperationContext
		context.perform {
			do {
				self.allLocations.removeAll()
				let request = NSFetchRequest<Event>(entityName: "Event")
				let results = try context.fetch(request)
				let locationSet = Set(results.compactMap {
					$0.location?.isEmpty == true ? nil : $0.location
				})
				self.allLocations = locationSet.sorted()
			}
			catch {
				CoreDataLog.error(".", ["Error" : error])
			}
		}
	}
	
	func markNotificationCompleted(_ eventID: String) {
		LocalCoreData.shared.performNetworkParsing { context in
			context.pushOpErrorExplanation("Failure saving change to a Scheduled Ship Event Notification. (the network call succeeded, but we couldn't save the change).")
			let fetchRequest = NSFetchRequest<Event>(entityName: "Event")
			let cdEvents = try? context.fetch(fetchRequest)
			if let event = cdEvents?.first(where: { $0.id == UUID(uuidString: eventID) }) {
				event.localNotificationID = nil
			}
		}
	}
	
}


// MARK: - API V2 Parsing
struct TwitarrV2Event: Codable {
	let id: String
	let title: String
	let eventDescription: String?
	let location: String?
	let official: Bool?

	let startTime: Int64
	let endTime: Int64
	
	let following: Bool

	enum CodingKeys: String, CodingKey {
		case id
		case title
		case eventDescription = "description"
		case location
		case official
		case startTime = "start_time"
		case endTime = "end_time"
		case following
	}
}

// GET /api/v2/event
struct TwitarrV2EventResponse : Codable {
	let status: String
	let total_count: Int
	let events: [TwitarrV2Event]
}

// MARK: - API V3 Parsing
struct TwitarrV3EventData: Codable {
    /// The event's ID. This is the Swiftarr database record for this event.
    var eventID: UUID
    /// The event's UID. This is the VCALENDAR/ICS File/sched.com identifier for this event--what calendar software uses to correllate whether 2 events are the same event.
    var uid: String
    /// The event's title.
    var title: String
    /// A description of the event.
    var description: String
    /// Starting time of the event
    var startTime: Date
    /// Ending time of the event.
    var endTime: Date
    /// The location of the event.
    var location: String
    /// The event category.
    var eventType: String
    /// The event's associated `Forum`.
    var forum: UUID?
    /// Whether user has favorited event.
    var isFavorite: Bool
}

// GET /api/v3/events
typealias TwitarrV3EventResponse = [TwitarrV3EventData]
