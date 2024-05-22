//
//  ScheduleSingleEventController.swift
//  Kraken
//
//  Created by Chall Fry on 5/11/24.
//  Copyright © 2024 Chall Fry. All rights reserved.
//

import UIKit
import CoreData
import EventKitUI

@objc class ScheduleSingleEventController: BaseCollectionViewController, GlobalNavEnabled {
	
	let dataManager = EventsDataManager.shared
	let scheduleLayout = ScheduleLayout()
	var scheduleDataSource = KrakenDataSource()
	var eventsSegment: FRCDataSourceSegment<Event>?
	
	public var eventID: UUID?
		
// MARK: Methods 
	override func viewDidLoad() {
        super.viewDidLoad()
        title = "Schedule"

		collectionView.collectionViewLayout = scheduleLayout
		
		// Add the loading segment up top
 		let loadingSegment = FilteringDataSourceSegment() 
 		let statusCell = LoadingStatusCellModel()
 		statusCell.statusText = "Loading Events"
 		statusCell.shouldBeVisible = false
 		statusCell.showSpinner = true
 		loadingSegment.append(statusCell)
 		loadingSegment.forceSectionVisible = true
 		scheduleDataSource.append(segment: loadingSegment)
 		dataManager.tell(self, when: "networkUpdateActive") { observer, observed in
 			statusCell.shouldBeVisible = observed.networkUpdateActive  		
 		}?.execute()
 		
		// Then, the events segment
		let events = FRCDataSourceSegment<Event>()
		if let eventID = eventID {
			events.fetchRequest.predicate = NSPredicate(format: "id == %@", eventID as CVarArg)
		}
		else {
			events.fetchRequest.predicate = NSPredicate(value: true)
		}
		events.fetchRequest.sortDescriptors = [ NSSortDescriptor(key: "startTime", ascending: true),
				 NSSortDescriptor(key: "endTime", ascending: true),
				 NSSortDescriptor(key: "title", ascending: true)]
  		scheduleDataSource.append(segment: events)
		eventsSegment = events
		scheduleLayout.eventsSegment = eventsSegment

		// Debug Logging
//		scheduleDataSource.log.instanceEnabled = true
//		events.log.instanceEnabled = true
//		loadingSegment.log.instanceEnabled = true

		events.activate(predicate: nil, sort: nil, cellModelFactory: createCellModel, sectionNameKeyPath: "startTime")
		scheduleDataSource.register(with: collectionView, viewController: self)
		
		// Register the nib for the section header view
		scheduleDataSource.registerSectionHeaderClass(newClass: EventSectionHeaderView.self)
    }
	
    override func viewDidAppear(_ animated: Bool) {
    	super.viewDidAppear(animated)
		dataManager.refreshEventsIfNecessary()
		scheduleDataSource.enableAnimations = true
	}
	
	override func viewDidDisappear(_ animated: Bool) {
    	super.viewDidDisappear(animated)
	}
	
	override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
		collectionView.collectionViewLayout.invalidateLayout()
	}
        
	func createCellModel(_ model: Event) -> BaseCellModel {
		let cellModel = EventCellModel(withModel: model)
				
		return cellModel
	}
			
// MARK: Actions
	
	
	
    // MARK: - Navigation
	override var knownSegues : Set<GlobalKnownSegue> {
		Set<GlobalKnownSegue>([ .showRoomOnDeckMap, .showForumThread ])
	}

	func globalNavigateTo(packet: GlobalNavPacket) -> Bool {
		// Force the view to load
		let _ = self.view
		
		return true
	}
}

