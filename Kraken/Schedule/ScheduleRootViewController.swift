//
//  ScheduleRootViewController.swift
//  Kraken
//
//  Created by Chall Fry on 8/12/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit
import CoreData
import EventKitUI

@objc class ScheduleRootViewController: BaseCollectionViewController, GlobalNavEnabled {
	@IBOutlet var filterButton: UIBarButtonItem!
	@IBOutlet var filterView: UIVisualEffectView!
	@IBOutlet var filterViewTrailingConstraint: NSLayoutConstraint!
	
	@IBOutlet weak var disclosureSlider: UISlider!
	@IBOutlet weak var 	favoritesFilterButton: UIButton!
	@IBOutlet weak var	alarmSetFilterButton: UIButton!
	@IBOutlet weak var	calendarItemFilterButton: UIButton!
	
	@IBOutlet weak var searchTextField: UITextField!
	@IBOutlet weak var showPastEventsSwitch: UISwitch!
	
	@IBOutlet weak var locationPickerContainer: UIView!
	@IBOutlet weak var 	locationPicker: UIPickerView!
	

	let dataManager = EventsDataManager.shared
	let scheduleLayout = ScheduleLayout()
	var scheduleDataSource = KrakenDataSource()
	var eventsSegment: FRCDataSourceSegment<Event>?
	
	var favoritesPredicate: NSPredicate?
	var textPredicate: NSPredicate?
	var locationPredicate: NSPredicate?
	var pastEventsPredicate: NSPredicate?
	
	@objc dynamic var disclosureLevel: Int = 4

// MARK: Methods 
	override func viewDidLoad() {
        super.viewDidLoad()
        title = "Schedule"

		dataManager.loadEvents()
		collectionView.collectionViewLayout = scheduleLayout
		
		// Manually register the nib for the section header view
		let headerNib = UINib(nibName: "EventSectionHeaderView", bundle: nil)
		collectionView.register(headerNib, forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, 
				withReuseIdentifier: "EventSectionHeaderView")
		scheduleDataSource.buildSupplementaryView = createSectionHeaderView

		// Add the loading segment up top
 		let loadingSegment = FilteringDataSourceSegment() 
 		let statusCell = LoadingStatusCellModel()
 		statusCell.statusText = "Loading Events"
 		statusCell.shouldBeVisible = true
 		statusCell.showSpinner = true
 		loadingSegment.append(statusCell)
 		loadingSegment.forceSectionVisible = true
 		scheduleDataSource.append(segment: loadingSegment)
 		dataManager.tell(self, when: "networkUpdateActive") { observer, observed in
 			statusCell.shouldBeVisible = observed.networkUpdateActive  		
 		}
 		
		// Then, the events segment
		let events = FRCDataSourceSegment<Event>()
		events.fetchRequest.predicate = NSPredicate(value: true)
		events.fetchRequest.sortDescriptors = [ NSSortDescriptor(key: "startTimestamp", ascending: true),
				 NSSortDescriptor(key: "endTimestamp", ascending: true),
				 NSSortDescriptor(key: "title", ascending: true)]
  		scheduleDataSource.append(segment: events)
		eventsSegment = events
		scheduleLayout.eventsSegment = eventsSegment

		// Debug Logging
//		scheduleDataSource.log.instanceEnabled = true
//		events.log.instanceEnabled = true
//		loadingSegment.log.instanceEnabled = true

		events.activate(predicate: nil, sort: nil, cellModelFactory: createCellModel, sectionNameKeyPath: "startTimestamp")
		scheduleDataSource.register(with: collectionView, viewController: self)
		
		// Hide the filter view
		filterViewTrailingConstraint.constant = 0 - filterView.bounds.size.width
		searchTextField.delegate = self
		locationPicker.dataSource = self
		locationPicker.delegate = self
		locationPickerContainer.isHidden = true

		setupGestureRecognizer()
		knownSegues = Set([.modalLogin, .showRoomOnDeckMap])
    }
	
	var minuteNotification: Any?
    override func viewDidAppear(_ animated: Bool) {
		scheduleDataSource.enableAnimations = true
		locationPicker.reloadAllComponents()
		if !self.showPastEventsSwitch.isOn {
			self.showPastEventsTapped()
		}

		minuteNotification = NotificationCenter.default.addObserver(forName: RefreshTimers.MinuteUpdateNotification, object: nil,
				queue: nil) { [weak self] notification in
    		if let self = self {
    			// Slightly hackish, as we're using the tapped handler to update the predicate, when the switch didn't change value.
    			if !self.showPastEventsSwitch.isOn {
    				self.showPastEventsTapped()
				}
			}
		}
	}
	
	override func viewDidDisappear(_ animated: Bool) {
		if let mn = minuteNotification	{
			NotificationCenter.default.removeObserver(mn)
		}
	}
	
	override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
		collectionView.collectionViewLayout.invalidateLayout()
	}
        
	func createCellModel(_ model: Event) -> BaseCellModel {
		let cellModel = EventCellModel(withModel: model)
		
		self.tell(cellModel, when: "disclosureLevel") { observer, observed in 
			observer.disclosureLevel = observed.disclosureLevel
		}?.execute()
		
		return cellModel
	}
	
	func createSectionHeaderView(_ cv: UICollectionView, _ kind: String, _ indexPath: IndexPath, 
			_ cellModel: BaseCellModel?) -> UICollectionReusableView {
		if let newView = cv.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: "EventSectionHeaderView", 
				for: indexPath) as? EventSectionHeaderView {
			if let eventCellModel = cellModel as? EventCellModel, let event = eventCellModel.model as? Event,
					let sectionStartTime = event.startTime {
				newView.setTime(to: sectionStartTime)
			}
			return newView
		}
		return UICollectionReusableView()
	}
	
	// This is the filter predicate that controls which events are shown. It ANDs together multiple sub-predicates
	// to build an overall filter that selects events to show in the list.
	func setCompoundPredicate() {
		var subPreds: [NSPredicate] = []
		if let favPred = favoritesPredicate { subPreds.append(favPred) }
		if let textPred = textPredicate { subPreds.append(textPred) }
		if let locationPred = locationPredicate { subPreds.append(locationPred) }
		if let pastEventPred = pastEventsPredicate { subPreds.append(pastEventPred) }
		let compoundPred = NSCompoundPredicate(andPredicateWithSubpredicates: subPreds)
		eventsSegment?.changePredicate(to: compoundPred)
	}

	// Tries to find an event happening now. Specifically:
	//		1. Ideally, an event of duration <= 2 hours with an end time in the future, start time in the past, and
	//			the earliest start time.
	// 		2. Otherwise, the first event in the list (ordered by start time) with an end time in the future.
	// It's possible with this algorithm to select an event that hasn't started yet, if there are no currently running events.
	// This algorithm should favor 'active' events over 'all-day' events when an 'active' event is running.
	func findIndexPathForEventAt(date: Date) -> IndexPath {
		var currentTime = date
		if Settings.shared.debugTimeWarpToCruiseWeek2019 {
			currentTime = Date(timeInterval: EventsDataManager.shared.debugEventsTimeOffset, since: currentTime)
		}
		
		var bestResult: IndexPath?
		if let sections = eventsSegment?.frc?.sections {
			foundEvent: for (sectionIndex, section) in sections.enumerated() {
				if let objects = section.objects {
					for (rowIndex, object) in objects.enumerated() {
						if let event = object as? Event {
							// Grab the first result that has an end time in the future.
							if bestResult == nil, event.endTime?.compare(currentTime) == .orderedDescending {
								bestResult = IndexPath(row: rowIndex, section: sectionIndex)
							}
							
							// Look for a better match--an event < 2 hours long that's currently occuring.
							if event.endTime?.compare(currentTime) == .orderedDescending, 
									event.startTime?.compare(currentTime) == .orderedAscending,
									(event.endTimestamp - event.startTimestamp) / 1000  <= 2 * 60 * 60 {
								bestResult = IndexPath(row: rowIndex, section: sectionIndex)
								break foundEvent
							}
							
							if event.startTime?.compare(currentTime) == .orderedDescending {
								break foundEvent
							}
						}
					}
				}
			}
		}
		
		return bestResult ?? IndexPath(row: 0, section: 0)
	}
	
// MARK: Actions
	
	// This is the Now button in the top-left of the navbar
	@IBAction func rightNowButtonTapped() {
		var indexPath = findIndexPathForEventAt(date: Date())
		indexPath.section += 1
		collectionView.scrollToItem(at: indexPath, at: .top, animated: true)
	}
	
	@IBAction func filterButtonTapped() {
		view.layoutIfNeeded()
		if filterView.frame.origin.x >= collectionView.bounds.maxX {
			// Show the filter view
			UIView.animate(withDuration: 0.3) {
				self.filterViewTrailingConstraint.constant = 0
				self.view.layoutIfNeeded()
			}
			
			// When the filter view is visible, make it the focus.
			collectionView.accessibilityElementsHidden = true
		}
		else {
			// Hide the filter view
			UIView.animate(withDuration: 0.3) {
				self.filterViewTrailingConstraint.constant = 0 - self.filterView.bounds.size.width
				self.view.layoutIfNeeded()
			}
			collectionView.accessibilityElementsHidden = false
		}
	}
	
	@IBAction func disclosureSliderTapped() {
		let newLevel = Int(disclosureSlider.value + 0.5)
	//	self.disclosureSlider.value = Float(newLevel)
		if newLevel != disclosureLevel {
//			eventsSegment?.cellModelSections.forEach {
//				$0.cellModels.forEach {
//					if let cell = $0 as? EventCellModel {
//						cell.disclosureLevel = newLevel
//					}
//				}
//			}
			disclosureLevel = newLevel

			// Tell the layout that we're focusing on the topmost visible cell--this makes the layout object
			// try to keep that cell at top of screen.
			if collectionView.visibleCells.count > 0 {
				var focusCell = collectionView.visibleCells[0]
				collectionView.visibleCells.forEach { if $0.frame.minY < focusCell.frame.minY { focusCell = $0 } }
				
				if let focusEventCell = focusCell as? EventCell, let cellModel = focusEventCell.cellModel as? EventCellModel {
					scheduleLayout.focusCellModel = cellModel
				}
			}
			
			scheduleLayout.disclosureLevel = newLevel
			scheduleDataSource.invalidateLayout()
		}
	}
	
	@IBAction func disclosureSliderTouchUp() {
		let newLevel = Int(disclosureSlider.value + 0.5)
		disclosureSlider.value = Float(newLevel)
	}
	
	// Filters to only show favorited events
	@IBAction func favoritesButtonTapped() {
		if !favoritesFilterButton.isSelected {
			if let currentUser = CurrentUser.shared.loggedInUser {
				favoritesPredicate = NSPredicate(format: "followedBy contains %@", currentUser)
			}
			favoritesFilterButton.isSelected = true
		}
		else {
			favoritesPredicate = nil
			favoritesFilterButton.isSelected = false
		}
		alarmSetFilterButton.isSelected = false
		calendarItemFilterButton.isSelected = false
		
		setCompoundPredicate()
	}
	
	// Filters to only show alarmclocked events
	@IBAction func alarmSetButtonTapped() {
		if !alarmSetFilterButton.isSelected {
			favoritesPredicate = NSPredicate(format: "localNotificationID != NULL AND localNotificationID != ''")
			alarmSetFilterButton.isSelected = true
		}
		else {
			favoritesPredicate = nil
			alarmSetFilterButton.isSelected = false
		}
		favoritesFilterButton.isSelected = false
		calendarItemFilterButton.isSelected = false
		setCompoundPredicate()
	}
	
	@IBAction func hasCalendarItemButtonTapped() {
		if !calendarItemFilterButton.isSelected {
			favoritesPredicate = NSPredicate(format: "ekEventID != NULL AND ekEventID != ''")
			calendarItemFilterButton.isSelected = true
		}
		else {
			favoritesPredicate = nil
			calendarItemFilterButton.isSelected = false
		}
		favoritesFilterButton.isSelected = false
		alarmSetFilterButton.isSelected = false
		setCompoundPredicate()
	}
	
	var searchText: String? {
		didSet {
			var newPred: NSPredicate
			if let search = searchText, !search.isEmpty {
				newPred = NSPredicate(format:
						"title contains[cd] %@ OR eventDescription contains[cd] %@ OR location contains[cd] %@",
						search, search, search)
			}
			else {
				newPred = NSPredicate(value: true)
			}
			textPredicate = newPred
			setCompoundPredicate()
		}
	}
	
	@IBAction func locationButtonTapped() {
		locationPickerContainer.isHidden = false
		filterButtonTapped()
	}
	
	@IBAction func locationDoneButtonTapped() {
		let index = locationPicker.selectedRow(inComponent: 0)
		let location = dataManager.allLocations[index]
		let newPred = NSPredicate(format: "location contains[cd] %@", location)
		locationPredicate = newPred
		setCompoundPredicate()
		locationPickerContainer.isHidden = true
	}
	
	@IBAction func showPastEventsTapped() {
		if showPastEventsSwitch.isOn {
			pastEventsPredicate = nil
		}
		else {
			let currentTime = Date(timeInterval: EventsDataManager.shared.debugEventsTimeOffset, since: Date())
			let currentTimeTimestamp: Int64 = Int64(currentTime.timeIntervalSince1970 * 1000.0)
			pastEventsPredicate = NSPredicate(format: "endTimestamp > %@", argumentArray: [currentTimeTimestamp])
		}
		setCompoundPredicate()
	}
	
	@IBAction func dayOfWeekButtonTapped(sender: UIButton) {
		var dayOfWeek = 0
		switch sender.title(for: .normal) {
		case "Sunday" : 	dayOfWeek = 1
		case "Monday" : 	dayOfWeek = 2
		case "Tuesday" : 	dayOfWeek = 3
		case "Wednesday" : 	dayOfWeek = 4
		case "Thursday" : 	dayOfWeek = 5
		case "Friday" : 	dayOfWeek = 6
		case "Saturday" : 	dayOfWeek = 7
		default: 			dayOfWeek = 7
		}
		
		if let selectedEvent = eventsSegment?.frc?.fetchedObjects?.first( where: { event in
					if let startTime = event.startTime {
						return Calendar.current.component(.weekday, from: startTime) == dayOfWeek
					}
					return false
				}) {
			
			if var indexPath = eventsSegment?.frc?.indexPath(forObject: selectedEvent) {
				indexPath.section += 1
				collectionView.scrollToItem(at: indexPath, at: .top, animated: true)
			}
		}
	}
	
	@IBAction func resetButtonTapped() {
		resetFilters()
	}
	
	func resetFilters() {
		favoritesPredicate = nil
		locationPredicate = nil
		textPredicate = nil
		pastEventsPredicate	= nil
		setCompoundPredicate()
		searchTextField.text = ""
		searchTextField.resignFirstResponder()

		// Hide the filter panel
		if filterViewTrailingConstraint.constant == 0 {
			filterButtonTapped()
		}
		view.layoutIfNeeded()
	}

    // MARK: - Navigation

	func globalNavigateTo(packet: GlobalNavPacket) -> Bool {
		if let eventID = packet.arguments["eventID"] as? String {
			resetFilters()
			if let results = eventsSegment?.frc?.fetchedObjects, let event = results.first(where: { $0.id == eventID } ),
					var indexPath = eventsSegment?.frc?.indexPath(forObject: event) {
				indexPath.section += 1
				collectionView.scrollToItem(at: indexPath, at: .top, animated: true)
			}
		}
		return true
	}

	@IBAction func dismissingLoginModal(_ segue: UIStoryboardSegue) {
		// Try to continue whatever we were doing before having to log in.
		if let loginVC = segue.source as? ModalLoginViewController {
			if CurrentUser.shared.isLoggedIn() {
				loginVC.segueData?.loginSuccessAction?()
			}
			else {
				loginVC.segueData?.loginFailureAction?()
			}
		}
	}	
}



extension ScheduleRootViewController: UITextFieldDelegate {
	func textFieldDidBeginEditing(_ textField: UITextField) {
		activeTextEntry = textField
	}
	
	func textFieldDidEndEditing(_ textField: UITextField, reason: UITextField.DidEndEditingReason) {
		activeTextEntry = nil
	}
	
	func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
		if var textFieldContents = textField.text {
			let swiftRange: Range<String.Index> = Range(range, in: textFieldContents)!
			textFieldContents.replaceSubrange(swiftRange, with: string)
			searchText = textFieldContents
		}
		return true
	}

	func textFieldShouldClear(_ textField: UITextField) -> Bool {
		searchText = nil
		return true
	}
}

extension ScheduleRootViewController: UIPickerViewDataSource, UIPickerViewDelegate {
	func numberOfComponents(in pickerView: UIPickerView) -> Int {
		return 1
	}
	
	func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
		return dataManager.allLocations.count
	}
	
	func pickerView(_ pickerView: UIPickerView, widthForComponent component: Int) -> CGFloat {
		return view.bounds.size.width
	}

	func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
		if row < dataManager.allLocations.count {
			return dataManager.allLocations[row]
		}
		return nil
	}
}



// at disclosure 5, cv is 73708 high. 155 sections, 395 cells Av cell height is 186.
// at 4, cv is 73587 high. still 186 per cell.
// at 3, cv is 33450 high. 84 per cell
// at 2, cv is 24590 high. 62 per cell
// at 0, cv is 16439 high. 41 per cell.


// MARK: -
class ScheduleLayout: UICollectionViewLayout {
	var sectionHeaderPositions: [CGRect] = []
	var cellPositions: [[CGRect]] = []
	var privateContentSize: CGSize = CGSize(width: 0, height: 0)
	var focusCellModel: EventCellModel?
	var disclosureLevel: Int = 4
	
	weak var eventsSegment: FRCDataSourceSegment<Event>?
		
// MARK: Methods	
	func showingSectionHeaders() -> Bool {
		return disclosureLevel >= 1
	}
	
	override func prepare() {
		guard let cv = collectionView, let ds = cv.dataSource, let del = cv.delegate else { return }
		
		let flowDelegate = del as? UICollectionViewDelegateFlowLayout
		cellPositions.removeAll()
		sectionHeaderPositions.removeAll()
		let cvWidth = cv.bounds.width
		
		// Iterate through each cell in each section, get the cell's size, and place each cell in a big stack.
		var pixelOffset: CGFloat = 0.0
		let sectionCount = ds.numberOfSections?(in: cv) ?? 1
		for sectionIndex in 0..<sectionCount {
			
			// Only show cell headers if the disclosure level is high enough
			if showingSectionHeaders() {
				//
				if sectionIndex == 0 {
					sectionHeaderPositions.append(CGRect(x: 0, y: 0, width: 0, height: 0))
				}
				else {
					sectionHeaderPositions.append(CGRect(x: 0, y: pixelOffset, width: cvWidth, height: 27))
					pixelOffset += 27
				}
			}
			
			let cellCount = ds.collectionView(cv, numberOfItemsInSection: sectionIndex)
			var cellLocations = [CGRect]()
			for cellIndex in 0..<cellCount {
				// In more generic code if sizeForItemAt isn't implemented we get the value from other sources.
				let cellSize = flowDelegate?.collectionView?(cv, layout: self, sizeForItemAt: 
						IndexPath(row: cellIndex, section: sectionIndex)) ?? CGSize(width: cvWidth, height: 50)
				cellLocations.append(CGRect(x: CGFloat(0.0), y: pixelOffset, width: cvWidth, height: cellSize.height))
				pixelOffset += cellSize.height
			}
			cellPositions.append(cellLocations)
		}
		
		privateContentSize = CGSize(width: cvWidth, height: pixelOffset)
	}
	
	override var collectionViewContentSize: CGSize {
		return privateContentSize
	}

	override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {	
		var result: [UICollectionViewLayoutAttributes] = []
		
		// Better to use a binary search for this, but a strict binary search of a multilevel array is painful.
		var indexPath = IndexPath(row: 0, section: 0)
		let numSections = cellPositions.count
		while indexPath.section < numSections {
			if cellPositions[indexPath.section].count > 0, cellPositions[indexPath.section][0].maxY > rect.origin.y {
				if cellPositions[indexPath.section][0].origin.y > rect.origin.y {
					repeat {
						if indexPath.section == 0 { break }
						indexPath.section -= 1
					} while cellPositions[indexPath.section].count == 0 && indexPath.section > 0
				}
				break
			}
			indexPath.section += 1
		}
		if indexPath.section >= numSections {
			return nil
		}

		// Now find the first cell in this section that intersects the rect
		while indexPath.row < cellPositions[indexPath.section].count {
			if cellPositions[indexPath.section][indexPath.row].maxY > rect.origin.y {
				break
			}
			indexPath.row += 1
		}
		
		// Create layout attrs for every cell in the rect, add to result
		let rectYMax = rect.maxY
		while true {
		
			// Skip empty sections
			while indexPath.row >= cellPositions[indexPath.section].count {
				indexPath.section += 1
				indexPath.row = 0
				if indexPath.section >= cellPositions.count {
					break
				}
			}
			
			// Break if we're past the bottom of the rect
			if indexPath.section >= cellPositions.count || cellPositions[indexPath.section][indexPath.row].origin.y > rectYMax {
				break
			}
			let val = UICollectionViewLayoutAttributes(forCellWith: indexPath)
			val.isHidden = false
			val.frame = cellPositions[indexPath.section][indexPath.row]
			result.append(val)
			
			indexPath.row += 1
			if indexPath.row >= cellPositions[indexPath.section].count {
				indexPath.row = 0
				indexPath.section += 1
				if indexPath.section >= cellPositions.count {
					break
				}
			}
		}
		
		// Add in layoutAttributes for section headers
		if showingSectionHeaders() {
			for index in 0..<sectionHeaderPositions.count {
				let sectionHeaderRect = sectionHeaderPositions[index]
				if sectionHeaderRect.size.height > 0, sectionHeaderRect.intersects(rect) {
					let val = UICollectionViewLayoutAttributes(forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
							with: IndexPath(row: 0, section: index))
					val.isHidden = false
					val.frame = sectionHeaderRect
					result.append(val)
				}
				if sectionHeaderRect.minY > rect.maxY {
					break
				}
			}
		}
		
		return result
	}
	
	override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
		let result = UICollectionViewLayoutAttributes(forCellWith: indexPath)
		
		let cellRect = cellPositions[indexPath.section][indexPath.row]
		result.frame = cellRect
		result.isHidden = false
		
		return result
	}
	
	override func layoutAttributesForSupplementaryView(ofKind elementKind: String, at indexPath: IndexPath) 
			-> UICollectionViewLayoutAttributes? {
		if !showingSectionHeaders() || indexPath.count < 2 || indexPath.row != 0 {
			return nil
		}
		
		let result = UICollectionViewLayoutAttributes(forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
							with: indexPath)
		let cellRect = sectionHeaderPositions[indexPath.section]
		result.frame = cellRect
		result.isHidden = false
		
		return result
	}
	
	// This makes the selection animations work correctly. 
	override func initialLayoutAttributesForAppearingItem(at itemIndexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
		guard cellPositions.count > itemIndexPath.section else { return nil }
		let section = cellPositions[itemIndexPath.section]
		guard section.count > itemIndexPath.row else { return nil }
		
		let val = UICollectionViewLayoutAttributes(forCellWith: itemIndexPath)
		val.isHidden = false
		val.frame = section[itemIndexPath.row]
		return val
	}
	
	// This makes the selection animations work correctly. 
	override func initialLayoutAttributesForAppearingSupplementaryElement(ofKind elementKind: String, 
			at elementIndexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
		guard cellPositions.count > elementIndexPath.section else { return nil }

		if !showingSectionHeaders() {
			return nil
		}
		
		let sectionHeaderRect = sectionHeaderPositions[elementIndexPath.section]
		let val = UICollectionViewLayoutAttributes(forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
				with: IndexPath(row: 0, section: elementIndexPath.section))
		val.isHidden = false
		val.frame = sectionHeaderRect
		return val
	}

// MARK: Insert/Delete handling

	var currentUpdateList: [UICollectionViewUpdateItem]?
	override func prepare(forCollectionViewUpdates updateItems: [UICollectionViewUpdateItem]) {
		currentUpdateList = updateItems
	}
	
	override func finalizeCollectionViewUpdates() {
		currentUpdateList = nil
	}

	override func indexPathsToInsertForSupplementaryView(ofKind elementKind: String) -> [IndexPath] {
		if !showingSectionHeaders() {
			return []
		}
		
		var result = [IndexPath]()
		if let updates = currentUpdateList {
			for update in updates {
				if update.updateAction == .insert, update.indexPathAfterUpdate?.count == 1, 
						let section = update.indexPathAfterUpdate?.section  {
					result.append(IndexPath(row: 0, section: section))
				}
			}
		}
		
		return result
	}
	
	override func indexPathsToDeleteForSupplementaryView(ofKind elementKind: String) -> [IndexPath] {
		var result = [IndexPath]()
		if let updates = currentUpdateList {
			for update in updates {
				if update.updateAction == .delete, update.indexPathBeforeUpdate?.count == 1, 
						let section = update.indexPathBeforeUpdate?.section  {
					result.append(IndexPath(row: 0, section: section))
				}
			}
		}
		
		return result
	}
	
//	override func initialLayoutAttributesForAppearingSupplementaryElement(ofKind elementKind: String, 
//			at elementIndexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
//				
//	}
	
//	override func finalLayoutAttributesForDisappearingSupplementaryElement(ofKind elementKind: String, 
//			at elementIndexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
//			
//	}

// MARK: Invalidation

	override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
		if let cv = collectionView, newBounds.size.width != cv.bounds.size.width {
			return true
		}
		return false
	}
	
	override func targetContentOffset(forProposedContentOffset proposedContentOffset: CGPoint) -> CGPoint {
		guard let focusCellModel = focusCellModel, let eventsSegment = eventsSegment else { return proposedContentOffset }
		
		if currentUpdateList == nil {
			return proposedContentOffset
		}
		
		if var focusIndexPath = eventsSegment.indexPathNearest(to: focusCellModel) {
		
			// Hack
			focusIndexPath.section += 1
		
			let cellRect = cellPositions[focusIndexPath.section][focusIndexPath.row]
			return cellRect.origin
		}
		
		return proposedContentOffset
	}
}
