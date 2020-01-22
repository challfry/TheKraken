//
//  DailyViewController.swift
//  Kraken
//
//  Created by Chall Fry on 9/5/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit

class DailyViewController: BaseCollectionViewController {
	let dataSource = KrakenDataSource()
	var dailySegment = FilteringDataSourceSegment()
	lazy var announcementSegment = FRCDataSourceSegment<Announcement>()
	var appFeaturesSegment = FilteringDataSourceSegment()
	
	override func awakeFromNib() {
		// Set the badge on the Daily tab
		AnnouncementDataManager.shared.tell(self, when: ["dailyTabBadgeCount"]) { observer, observed in
			let badgeCount = observed.dailyTabBadgeCount
			observer.navigationController?.tabBarItem.badgeValue = badgeCount > 0 ? "\(badgeCount)" : nil
		}?.execute()
	}

    override func viewDidLoad() {
        super.viewDidLoad()
		title = "Today"

		dataSource.append(segment: dailySegment)
		dailySegment.append(DailyActivityCellModel())
		
		announcementSegment.activate(predicate: NSPredicate(format: "isActive == true"),
				sort: [ NSSortDescriptor(key: "timestamp", ascending: false) ], 
				cellModelFactory: self.createAnnouncementCellModel)
		dataSource.append(segment: announcementSegment)
		
		
		dataSource.append(segment: appFeaturesSegment)
		appFeaturesSegment.append(SocialCellModel("Twittar", imageNamed: "Twitarr",  nav: GlobalNavPacket(tab: .twitarr, arguments: [:])))
		appFeaturesSegment.append(SocialCellModel("Forums", imageNamed: "Forums", nav: GlobalNavPacket(tab: .forums, arguments: [:])))
		appFeaturesSegment.append(SocialCellModel("Seamail", imageNamed: "Seamail", nav: GlobalNavPacket(tab: .seamail, arguments: [:])))
		appFeaturesSegment.append(SocialCellModel("Schedule", imageNamed: "Schedule", nav: GlobalNavPacket(tab: .events, arguments: [:])))
		appFeaturesSegment.append(SocialCellModel("Karaoke", imageNamed: "Karaoke", nav: GlobalNavPacket(tab: .karaoke, arguments: [:])))
		appFeaturesSegment.append(SocialCellModel("Scrapbook", imageNamed: "Scrapbook", nav: GlobalNavPacket(tab: .scrapbook, arguments: [:])))
		appFeaturesSegment.append(SocialCellModel("Settings", imageNamed: "Settings", nav: GlobalNavPacket(tab: .settings, arguments: [:])))
		
  		dataSource.register(with: collectionView, viewController: self)

		//
		// Tweet Mentions
		// Forum Mentions
		// Unread Seamail
		// Announcements?
		
		setupGestureRecognizer()
    }
    
    override func viewDidAppear(_ animated: Bool) {
		dataSource.enableAnimations = true
		AnnouncementDataManager.shared.markAllAnnouncementsRead()
	}
	
	override func viewDidDisappear(_ animated: Bool) {
		// Mark Announcements read both when we appear and when we disappear.
		AnnouncementDataManager.shared.markAllAnnouncementsRead()
	}
    
    func createAnnouncementCellModel(_ model: Announcement) -> BaseCellModel {
    	let cellModel = AnnouncementCellModel()
    	cellModel.model = model
    	return cellModel
    }
}
