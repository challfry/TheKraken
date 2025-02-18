//
//  DayPlannerCell.swift
//  Kraken
//
//  Created by Chall Fry on 10/14/24.
//  Copyright © 2024 Chall Fry. All rights reserved.
//

import UIKit
import CoreData

enum AppointmentColor {
	case redTeam(Event)
	case goldTeam(Event)
	case schedule(Event)			// Blue
	case lfg(SeamailThread)			// Green
	case personal(SeamailThread)	// Purple?
	case testing(String)
}

@objc class AppointmentVisualData: NSObject {
	var startTime: Date
	var endTime: Date
	var concurrentCount: Int
	var column: Int
	var color: AppointmentColor
	
//	init(personalEvent: PersonalEvent) {
//		startTime = personalEvent.startTime
//		endTime = personalEvent.endTime
//		concurrentCount = 0
//		column = 0
//		color = .personal(personalEvent)
//	}
	
	init?(lfg: SeamailThread) {
		guard let start = lfg.startTime, let end = lfg.endTime else {
			return nil
		}
		startTime = start
		endTime = end
		concurrentCount = 0
		column = 0
		if lfg.isLFGType() {
			color = .lfg(lfg)
		}
		else {
			color = .personal(lfg)
		}
	}
	
	init(event: Event) {
		startTime = event.startTime
		endTime = event.endTime
		concurrentCount = 0
		column = 0
		if event.description.range(of: "Gold Team", options: .caseInsensitive) != nil {
			color = .goldTeam(event)
		}
		else if event.description.range(of: "Red Team", options: .caseInsensitive) != nil {
			color = .redTeam(event)
		}
		else {
			color = .schedule(event)
		}
	}
	
	init(startTime: Date, endTime: Date) {
		self.startTime = startTime
		self.endTime = endTime
		concurrentCount = 0
		column = 0
		color = .testing("Twitarr Help Desk Hours")
	}
}

@objc protocol DayPlannerCellBindingProtocol  {
	var fullDay: Bool { get set }
	var displayStartTime: Date { get set }
	var displayEndTime: Date { get set }
	var appointments: [AppointmentVisualData] { get set }
	var errorStr: String { get set }
}


@objc class DayPlannerCellModel: BaseCellModel, DayPlannerCellBindingProtocol, NSFetchedResultsControllerDelegate {
	override class var validReuseIDDict: [String: BaseCollectionViewCell.Type ] { 
		return [ "DayPlannerCell" : DayPlannerCell.self ] 
	}
	
	@objc dynamic var fullDay = false
	@objc dynamic var appointments: [AppointmentVisualData] = []
	@objc dynamic var errorStr: String = ""
	
	@objc dynamic var displayStartTime: Date
	@objc dynamic var displayEndTime: Date
	var dayOfCruise: Int?
	
	private var eventFRC: NSFetchedResultsController<Event>?
	private var lfgFRC: NSFetchedResultsController<SeamailThread>?
	
	init(makeItBig: Bool = false, day: Int? = nil) {
		self.fullDay = makeItBig
		self.displayStartTime = Date()
		self.displayEndTime = Date()
		self.dayOfCruise = day
		super.init(bindingWith: DayPlannerCellBindingProtocol.self)
		
		// Set times
		setStartAndEndTimes(forCruiseDay: day)
		
        CurrentUser.shared.tell(self, when: "loggedInUser") { observer, observed in
        	observer.setupFRCs()
		}?.execute()
		
		NotificationCenter.default.addObserver(forName: RefreshTimers.MinuteUpdateNotification, object: nil,
				queue: nil) { [weak self] notification in
			self?.setStartAndEndTimes(forCruiseDay: day)
		}
	}
	
	func setStartAndEndTimes(forCruiseDay: Int?) {
		var comp = Calendar.current.dateComponents(in: TimeZone.current, from: Date())
		comp.minute = 0
		comp.second = 0
		comp.nanosecond = 0
		if fullDay, let forCruiseDay {
			// Calendar here is midnight to midnight, which may be more or less than 24 hours with tz changes.
	//		let noonEmbark = (cruiseStartDate() ?? Date()) + 3600.0 * 12.0
			let noonEmbark = lastCruiseStartDate() + 3600.0 * 12.0
			var cal = Calendar.current
			cal.timeZone = ServerTime.shared.tzAtTime(noonEmbark)
			let noon = cal.date(byAdding: .day, value: forCruiseDay, to: noonEmbark) ?? Date()
			var components = cal.dateComponents(in: cal.timeZone, from: noon)
			components.hour = 0
			let nearMidnightRightDate = cal.date(from: components) ?? Date()
			cal.timeZone = ServerTime.shared.tzAtTime(nearMidnightRightDate)
			displayStartTime = cal.date(from: components) ?? Date()
			let approxEndTime = displayStartTime + 24.0 * 60.0 * 60.0
			cal.timeZone = ServerTime.shared.tzAtTime(approxEndTime)
			displayEndTime = cal.date(byAdding: .day, value: 1, to: displayStartTime) ?? Date() + 24.0 * 60.0 * 60.0
		}
		else {
			// Always a 4 hour window
			displayStartTime = Calendar.current.date(from: comp) ?? Date()
			displayEndTime = Calendar.current.date(byAdding: .hour, value: 4, to: displayStartTime) ?? Date() + 4.0 * 60.0 * 60.0
		}
	}
	
	func setupFRCs() {
		guard let currentUser = CurrentUser.shared.loggedInUser else {
			// Clear all appointments
			appointments = []
			return
		}
		
		let timePred = NSPredicate(format: "endTime >= %@ && startTime < %@", displayStartTime as NSDate, displayEndTime as NSDate)
	
		let currentUserID = currentUser.userID
		let eventFetch: NSFetchRequest<Event> = NSFetchRequest(entityName: "Event")
		eventFetch.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
				NSPredicate(format: "followedBy contains %@", currentUser), timePred])
		eventFetch.sortDescriptors = [NSSortDescriptor(key: "startTime", ascending: true)]
		eventFRC = NSFetchedResultsController(fetchRequest: eventFetch, managedObjectContext: LocalCoreData.shared.mainThreadContext, 
				sectionNameKeyPath: nil, cacheName: nil)
		eventFRC?.delegate = self

		let lfgFetch: NSFetchRequest<SeamailThread> = NSFetchRequest(entityName: "SeamailThread") // SeamailThread.fetchRequest()
		lfgFetch.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
				NSCompoundPredicate(orPredicateWithSubpredicates: [
						NSPredicate(format: "owner.userID == %@", currentUserID as CVarArg),
						NSPredicate(format: "ANY participants.userID == %@", currentUserID as CVarArg),
						NSPredicate(format: "cancelled == false")
				]),
				NSPredicate(format: "NOT (fezType IN %@)", ["open", "closed"] as CVarArg),
				timePred])
		lfgFetch.sortDescriptors = [NSSortDescriptor(key: "startTime", ascending: true)]
		lfgFRC = NSFetchedResultsController(fetchRequest: lfgFetch, managedObjectContext: LocalCoreData.shared.mainThreadContext, 
				sectionNameKeyPath: nil, cacheName: nil)
		lfgFRC?.delegate = self
				
		//
		errorStr = ""
		(try? eventFRC?.performFetch()) ?? errorStr.append("Failed to fetch events you're following.")
		(try? lfgFRC?.performFetch()) ?? errorStr.append(" Failed to fetch Looking For Groups you've joined.")
//		(try? personalEventFRC?.performFetch()) ?? errorStr.append(" Failed to fetch your Personal Events.")
		
		updateAppointmentList()
	}
	
	func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
		// whichever FRC changed, just update the whole array
		self.updateAppointmentList()
	}
	
	func updateAppointmentList() {
		var appointments: [AppointmentVisualData] = []
		
//		for personalEvent in personalEventFRC?.fetchedObjects ?? [] {
//			appointments.append(AppointmentVisualData(personalEvent: personalEvent))
//		}
		for lfg in lfgFRC?.fetchedObjects ?? [] {
			if let lfgAVD = AppointmentVisualData(lfg: lfg) {
				appointments.append(lfgAVD)
			}
		}
		for event in eventFRC?.fetchedObjects ?? [] {
			appointments.append(AppointmentVisualData(event: event))
		}
		// Testing
//		let hour = 3600.0
//		appointments.append(AppointmentVisualData(startTime: displayStartTime + hour, endTime: displayStartTime + hour * 2))
//		appointments.append(AppointmentVisualData(startTime: displayStartTime + hour, endTime: displayStartTime + hour * 2))
//		appointments.append(AppointmentVisualData(startTime: displayStartTime + hour, endTime: displayStartTime + hour * 2))
//		appointments.append(AppointmentVisualData(startTime: displayStartTime + hour * 2, endTime: displayStartTime + hour * 3))
//		addTestScheduleEvent(at: displayStartTime + hour * 1)
//		addTestLFGEvent(at: displayStartTime + hour * 0)
				
		var group = [AppointmentVisualData]()
		var columnEndTimes = [Date]()
		var groupEndTime = Date.distantPast
		let sorted = appointments.sorted(by: { $0.startTime < $1.startTime })
		for appt in sorted {
			if groupEndTime <= appt.startTime {
				// Previous Group complete. Every group member gets the same concurrentCount and will draw with that many columns.
				for groupedAppt in group {
					groupedAppt.concurrentCount = columnEndTimes.count
				}
				columnEndTimes = []
				groupEndTime = Date.distantPast
				group.removeAll()
			}
			if let colIndex = columnEndTimes.firstIndex(where: { $0 <= appt.startTime }) {
				// Add new appt to existing column
				appt.column = colIndex
				columnEndTimes[colIndex] = appt.endTime
			}
			else {
				// Add new column
				appt.column = columnEndTimes.count
				columnEndTimes.append(appt.endTime)
			}
			groupEndTime = max(groupEndTime, appt.endTime)
			group.append(appt)
		}
		// Close out the last group
		for groupedAppt in group {
			groupedAppt.concurrentCount = columnEndTimes.count
		}
		
		self.appointments = sorted
	}
}

// For testing; creates mocked events in the next few hours
extension DayPlannerCellModel {
	func addTestScheduleEvent(at mockStartTime: Date)  {
		let eventFetch: NSFetchRequest<Event> = NSFetchRequest(entityName: "Event")
		if let currentUser = CurrentUser.shared.loggedInUser {
			eventFetch.predicate = NSPredicate(format: "followedBy contains %@", currentUser)
		}
		guard let event = try! LocalCoreData.shared.mainThreadContext.fetch(eventFetch).first else { return }
		let appt = AppointmentVisualData.init(event: event)
		appt.endTime = mockStartTime.addingTimeInterval(appt.endTime.timeIntervalSince(appt.startTime))
		appt.startTime = mockStartTime
		appointments.append(appt)
	}
	
	func addTestLFGEvent(at mockStartTime: Date) {
		guard let currentUserID = CurrentUser.shared.loggedInUser?.userID else { return }
		let lfgFetch: NSFetchRequest<SeamailThread> = NSFetchRequest(entityName: "SeamailThread") 
		lfgFetch.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
				NSCompoundPredicate(orPredicateWithSubpredicates: [
						NSPredicate(format: "owner.userID == %@", currentUserID as CVarArg),
						NSPredicate(format: "ANY participants.userID == %@", currentUserID as CVarArg)
				]),
				NSPredicate(format: "NOT (fezType IN %@)", ["open", "closed"] as CVarArg)])
		guard let lfg = try! LocalCoreData.shared.mainThreadContext.fetch(lfgFetch).first,
				let appt = AppointmentVisualData.init(lfg: lfg) else { return }
		appt.endTime = mockStartTime.addingTimeInterval(appt.endTime.timeIntervalSince(appt.startTime))
		appt.startTime = mockStartTime
		appointments.append(appt)
	}
}

class DayPlannerCell: BaseCollectionViewCell, DayPlannerCellBindingProtocol {
	private static let cellInfo = [ "DayPlannerCell" : PrototypeCellInfo("DayPlannerCell") ]
	override class var validReuseIDDict: [ String: PrototypeCellInfo] { return DayPlannerCell.cellInfo }

	@IBOutlet weak var pillView: UIView!
		@IBOutlet weak var pillViewLeading: NSLayoutConstraint!
		@IBOutlet weak var pillViewTrailing: NSLayoutConstraint!
		@IBOutlet weak var pillViewTop: NSLayoutConstraint!
		@IBOutlet weak var pillViewBottom: NSLayoutConstraint!
		@IBOutlet weak var headerView: UIView!
			@IBOutlet weak var dayPlannerButton: UIButton!
			@IBOutlet weak var addButton: UIButton!
		@IBOutlet weak var calendarView: DayPlannerBgView!
			@IBOutlet weak var calendarHeight: NSLayoutConstraint!
			
	var fullDay: Bool = false {
		didSet {
			headerView.isHidden = fullDay
			pillView.layer.cornerRadius = fullDay ? 0 : 12
			pillView.layer.borderWidth = fullDay ? 0 : 1
			pillView.layer.borderColor = UIColor(named: "PortAndTheme BG")!.cgColor
			pillView.layer.masksToBounds = true
			pillViewLeading.constant = fullDay ? 0 : 10
			pillViewTrailing.constant = fullDay ? 0 : 10
			pillViewTop.constant = fullDay ? 0 : 5
			pillViewBottom.constant = fullDay ? 0 : 5
		}
	}
	
	var displayStartTime: Date = Date() {
		didSet {
			recreateAppointmentViews()
			calendarView.setNeedsDisplay()
		}
	}
	var displayEndTime: Date = Date() {
		didSet {
			recreateAppointmentViews()
		}
	}
	var errorStr: String = ""
	
	var appointments: [AppointmentVisualData] = [] {
		didSet {
			recreateAppointmentViews()
		}
	}

	override func awakeFromNib() {
		super.awakeFromNib()
		calendarView.cell = self
		
		addButton.setImage(UIImage(systemName: "calendar.badge.plus"), for: .normal)
		var colors = [ UIColor.green, UIColor(named: "Kraken Label Text")! ]
		let normalConfig = UIImage.SymbolConfiguration(pointSize: 22).applying(UIImage.SymbolConfiguration(paletteColors: colors))
		addButton.setPreferredSymbolConfiguration(normalConfig, forImageIn: .normal)
		colors = [ UIColor.green, UIColor.white ]
		let hiliteConfig = UIImage.SymbolConfiguration(pointSize: 22).applying(UIImage.SymbolConfiguration(paletteColors: colors))
		addButton.setPreferredSymbolConfiguration(hiliteConfig, forImageIn: .highlighted)
		
		NotificationCenter.default.addObserver(forName: RefreshTimers.MinuteUpdateNotification, object: nil,
				queue: nil) { [weak self] notification in
			self?.calendarView.setNeedsDisplay()
		}
		
	}
	
	override func prepareForReuse() {
		super.prepareForReuse()
		calendarView.setNeedsDisplay()
	}
	
	func recreateAppointmentViews() {
		calendarHeight.constant = displayEndTime.timeIntervalSince(displayStartTime) * 50.0 / 3600.0
		calendarView.subviews.forEach { $0.removeFromSuperview() }
		for appt in appointments {
		let btn = DayPlannerApptButton(appt: appt, cell: self)
			btn.addTarget(self, action: #selector(DayPlannerCell.appointmentButtonHit), for: .touchUpInside)
			calendarView.addSubview(btn)
		}
	}
	
	@IBAction func dayPlannerButtonHit(_ sender: Any) {
		if let vc = viewController as? BaseCollectionViewController, vc.canPerformSegue(.dayPlannerRoot) {
			vc.performKrakenSegue(.dayPlannerRoot, sender: nil)
		}
	}
	
	// The Add Personal Event button on the right of the cell's header
	@IBAction func addButtonHit(_ sender: Any) {
		if let vc = viewController as? BaseCollectionViewController {
			vc.performKrakenSegue(.privateEventCreate, sender: nil)
		}
	}
	
	@objc func appointmentButtonHit(_ sender: Any) {
		guard let vc = viewController as? BaseCollectionViewController, let appt = (sender as? DayPlannerApptButton)?.appt else { return }
		switch appt.color {
			case .schedule(let event): vc.performKrakenSegue(.singleEvent, sender: event.id)
			case .redTeam(let event): vc.performKrakenSegue(.singleEvent, sender: event.id)
			case .goldTeam(let event): vc.performKrakenSegue(.singleEvent, sender: event.id)
			case .lfg(let lfg): vc.performKrakenSegue(.showSeamailThread, sender: lfg)
			case .personal(let event): vc.performKrakenSegue(.showSeamailThread, sender: event)
			case .testing: break 
		}
	}
}

class DayPlannerBgView: UIView {
	weak var cell: DayPlannerCell?
	
	override func draw(_ rect: CGRect) {
		guard let context = UIGraphicsGetCurrentContext(), let cell = self.cell else { return }
		context.setFillColor(UIColor(named: "DayPlanner Background")!.cgColor)
		context.fill([bounds])

		let nowLineY = -(cell.displayStartTime.timeIntervalSinceNow) * 50 / 3600
		context.setStrokeColor(UIColor(named: "DayPlanner Current Line")!.cgColor)
		context.strokeLineSegments(between: [CGPoint(x: 0, y: nowLineY), CGPoint(x: bounds.width, y: nowLineY)])

		let numHours = Int(cell.calendarHeight.constant / 50)
		for index in 0..<numHours {
			let hour = cell.displayStartTime.addingTimeInterval(Double(index) * 60 * 60)	
		//	let hour = Calendar.current.date(byAdding: .hour, value: index, to: cell.displayStartTime)
			let hourStr = getHourString(for: hour, useDeviceTZ: !cell.fullDay)
			hourStr.draw(at: CGPoint(x: 1, y: CGFloat(index) * 50))
			
			context.setStrokeColor(UIColor(named: "DayPlanner Hour Line")!.cgColor)
			context.strokeLineSegments(between: [CGPoint(x: 0, y: CGFloat(index) * 50), CGPoint(x: bounds.width, y: CGFloat(index) * 50)])
			
			// If the next hour marker or the previous hour merker is in a different TZ, show it.
			let timeZoneAbbrev = cell.fullDay ? ServerTime.shared.abbrevAtTime(hour) : TimeZone.current.abbreviation(for: hour)!
//			if ServerTime.shared.abbrevAtTime(apptStart + 60 * 60) != timeZoneAbbrev  ||
//					ServerTime.shared.abbrevAtTime(apptStart - 60 * 60) != timeZoneAbbrev {
				let attributedStrig = getTZString(str: timeZoneAbbrev)
				attributedStrig.draw(at: CGPoint(x: 1, y: CGFloat(index) * 50 + hourStr.size().height))
//			}
		}
	}
	
	override func layoutSubviews() {
		super.layoutSubviews()
		cell?.recreateAppointmentViews()
	}

	func getHourString(for hour: Date, useDeviceTZ: Bool) -> NSAttributedString {	
		let formatter = DateFormatter()
		formatter.dateFormat = "h a"
		formatter.timeZone = useDeviceTZ ? TimeZone.current : ServerTime.shared.tzAtTime(hour)
		let str = formatter.string(from: hour)
		
		let attributes: [NSAttributedString.Key : Any] = [
				.font: UIFont.systemFont(ofSize: 12.0),
				.foregroundColor: UIColor(named: "DayPlanner Hour Text")!]
		return NSAttributedString(string: str, attributes: attributes)
	}
	
	func getTZString(str: String) -> NSAttributedString {
		let attributes: [NSAttributedString.Key : Any] = [
			.font: UIFont.boldSystemFont(ofSize: 12.0),
			.foregroundColor: UIColor(named: "DayPlanner Hour Text")!]
		return NSAttributedString(string: str, attributes: attributes)
	}
}

class DayPlannerApptButton: UIButton {
	let leftMargin: CGFloat = 40.0
	let rightMargin: CGFloat = 5.0
	let colGap: CGFloat = 5.0
	
	weak var appt: AppointmentVisualData?
//	weak var cell: DayPlannerCell?
	
	init(appt: AppointmentVisualData, cell: DayPlannerCell) {
		let colWidth: CGFloat = (cell.calendarView.bounds.width - leftMargin - rightMargin - colGap * CGFloat(appt.concurrentCount - 1)) / 
				CGFloat(appt.concurrentCount)
		var apptRect = CGRect(x: leftMargin + (CGFloat(appt.column) * (colWidth + colGap)), 
				y: appt.startTime.timeIntervalSince(cell.displayStartTime) * 50 / 3600, 
				width: colWidth, height: appt.endTime.timeIntervalSince(appt.startTime) * 50 / 3600 - 1)
		// Very short events still need to be tall enough to read their text
		apptRect.size.height = max(apptRect.size.height, 16.0)
		self.appt = appt
		super.init(frame: apptRect)
		layer.cornerRadius = 10.0
		self.clipsToBounds = true
		self.isOpaque = false
		setBGColor()
		
		var labelFrame = bounds.insetBy(dx: 10, dy: 0)
		if labelFrame.origin.y < 0 {
			labelFrame.origin.y = 0
		}
		let label = UILabel(frame: labelFrame)
		label.textAlignment = .left
		label.textColor = .white
		label.font = UIFont.boldSystemFont(ofSize: 14.0)
		label.lineBreakMode = .byWordWrapping
		label.numberOfLines = 0
		switch appt.color {
			case .schedule(let event): label.text = event.title
			case .redTeam(let redTeam): label.text = redTeam.title
			case .goldTeam(let goldTeam): label.text = goldTeam.title
			case .lfg(let lfg): label.text = lfg.subject
			case .personal(let personal): label.text = personal.subject
			case .testing(let testing): label.text = testing
		}
		label.sizeToFit()
		addSubview(label)
	}
	
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}
		
	override var isHighlighted: Bool {
		didSet {
			setBGColor()
		}
	}
	
	func setBGColor() {
		guard let appt else { 
			backgroundColor = UIColor(named: "DayPlanner Event BG")!
			return
		}
		switch (appt.color, isHighlighted) {
		case (.schedule, false): backgroundColor = UIColor(named: "DayPlanner Event BG")!
		case (.schedule, true): backgroundColor = UIColor(named: "DayPlanner Event Hilited BG")!
		case (.redTeam, false): backgroundColor = UIColor(named: "DayPlanner RedTeam BG")!
		case (.redTeam, true): backgroundColor = UIColor(named: "DayPlanner RedTeam Hilited BG")!
		case (.goldTeam, false): backgroundColor = UIColor(named: "DayPlanner GoldTeam BG")!
		case (.goldTeam, true): backgroundColor = UIColor(named: "DayPlanner GoldTeam Hilited BG")!
		case (.lfg, false): backgroundColor = UIColor(named: "DayPlanner LFG BG")!
		case (.lfg, true): backgroundColor = UIColor(named: "DayPlanner LFG Hilited BG")!
		case (.personal, false): backgroundColor = UIColor(named: "DayPlanner Personal BG")!
		case (.personal, true): backgroundColor = UIColor(named: "DayPlanner Personal Hilited BG")!
		case (.testing, false): backgroundColor = UIColor.gray
		case (.testing, true): backgroundColor = UIColor.lightGray
		
		}
	}
}
