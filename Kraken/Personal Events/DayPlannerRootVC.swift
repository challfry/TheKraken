//
//  DayPlannerRootVC.swift
//  Kraken
//
//  Created by Chall Fry on 10/25/24.
//  Copyright © 2024 Chall Fry. All rights reserved.
//

import UIKit
import CoreData

class DayPlannerRootVC: BaseCollectionViewController, GlobalNavEnabled {
	@IBOutlet var newEventButton: UIBarButtonItem!

	let loginDataSource = KrakenDataSource()
		let loginSection = LoginDataSourceSegment()
	let dayPlannerDataSource = KrakenDataSource()
//		var dayPlannerSegments: [FilteringDataSourceSegment] = []
			var dayPlannerCells: [DayPlannerCellModel] = []
			
	private var firstLayout: Bool = true

	override func viewDidLoad() {
        super.viewDidLoad()
		title = "Day Planner"
       
        loginDataSource.append(segment: loginSection)
		loginSection.headerCellText = "In order to see your Day Planner, you will need to log in first."

		for index in 0..<cruiseNumDays() {
			let newSegment = FilteringDataSourceSegment()
			let newCell = DayPlannerCellModel(makeItBig: true, day: index)
			dayPlannerCells.append(newCell)
			newSegment.append(newCell)
			dayPlannerDataSource.append(segment: newSegment)
		}

		// Register the nib for the section header view
		dayPlannerDataSource.registerSectionHeaderClass(newClass: DayPlannerSectionHeader.self)
        collectionView.collectionViewLayout = UICollectionViewFlowLayout()
		if let layout = collectionView.collectionViewLayout as? UICollectionViewFlowLayout {
			layout.sectionHeadersPinToVisibleBounds = true
		}

		// When a user is logged in we'll set up the FRC to load the threads which that user can 'see'. Remember, CoreData
		// stores ALL the seamail we ever download, for any user who logs in on this device.
        CurrentUser.shared.tell(self, when: "loggedInUser") { observer, observed in        		
			if let _ = observed.loggedInUser?.userID {
        		observer.dayPlannerDataSource.register(with: observer.collectionView, viewController: observer)
				observer.newEventButton.isEnabled = true
				observer.navigationController?.popToViewController(self, animated: false)
			}
       		else {
       			// If nobody's logged in, pop to root, show the login cells.
				observer.loginDataSource.register(with: observer.collectionView, viewController: observer)
				observer.newEventButton.isEnabled = false
				observer.navigationController?.popToRootViewController(animated: false)
       		}
        }?.execute()     
	}
		
	// Sets content offset after layout happens
	override func viewDidLayoutSubviews() {
		super.viewDidLayoutSubviews()
		guard firstLayout else { return }
		firstLayout = false
        // Scroll to today's cell if it's during cruise week
		if let cruiseDay = dayOfCruise(), let startDate = cruiseStartDate() {
			collectionView.layoutIfNeeded()
			let cruiseHour = cruiseCurrentDate().timeIntervalSince(startDate) / 3600.0
			// Calculation: ~30px for each day's header, 50 pixels per hour (1200 pixels per day cell) Doesn't deal with timezones
			// because if we're off by 50 pixels it doesn't matter.
			var yOffset: CGFloat = CGFloat(cruiseDay) * 30.0 + CGFloat(cruiseHour) * 50 - collectionView.bounds.height / 3.0
			yOffset = min(collectionView.contentSize.height - collectionView.bounds.height, yOffset)
			yOffset = max(0, yOffset)
			collectionView.setContentOffset(CGPoint(x: 0, y: yOffset), animated: false)
		}
	}
	
    override func viewDidAppear(_ animated: Bool) {
    	super.viewDidAppear(animated)
		loginDataSource.enableAnimations = true
		dayPlannerDataSource.enableAnimations = true
		loginSection.clearAllSensitiveFields()
		EventsDataManager.shared.refreshEventsIfNecessary()
	}
	    
// MARK: - Actions

	@IBAction func addEventButtonHit(_ sender: Any) {
		performKrakenSegue(.privateEventCreate, sender: nil)
	}
	
    
// MARK: - Navigation
	override var knownSegues : Set<GlobalKnownSegue> {
		Set<GlobalKnownSegue>([ 
				.privateEventCreate, .showSeamailThread, .showSeamailThreadID, .singleEvent
		])
	}

	@discardableResult func globalNavigateTo(packet: GlobalNavPacket) -> Bool {
		if let eventID = packet.arguments["PrivateEvent"] as? UUID {
			performKrakenSegue(.showSeamailThreadID, sender: eventID)
		}
		else if let segue = packet.segue, [.showForumCategory, .showForumThread, .showForumFilterPack].contains(segue) {
			performKrakenSegue(segue, sender: packet.sender)
			return true
		}
		return false
	}

	// This is the unwind segue from the compose view for Personal Events.
	@IBAction func dismissingCreateEvent(_ segue: UIStoryboardSegue) {
		SeamailDataManager.shared.loadSeamails()
	}	
}
