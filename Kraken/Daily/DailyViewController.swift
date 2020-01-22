//
//  DailyViewController.swift
//  Kraken
//
//  Created by Chall Fry on 9/5/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit

class DailyViewController: BaseCollectionViewController, GlobalNavEnabled {

	// FIXME: I don't shy away from singletons, but this isn't how they're supposed to be used.
	static var shared: DailyViewController?

	let dataSource = KrakenDataSource()
	var dailySegment = FilteringDataSourceSegment()
	lazy var announcementSegment = FRCDataSourceSegment<Announcement>()
	var appFeaturesSegment = FilteringDataSourceSegment()
	
	override func awakeFromNib() {
		super.awakeFromNib()
		DailyViewController.shared = self
		knownSegues = [.twitarrRoot, .forumsRoot, .seamailRoot, .eventsRoot, .deckMapRoot, .karaokeRoot, .scrapbookRoot, .settingsRoot]
		
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
		appFeaturesSegment.append(SocialCellModel("Deck Maps", imageNamed: "Map", nav: GlobalNavPacket(tab: .deckPlans, arguments: [:])))
		appFeaturesSegment.append(SocialCellModel("Karaoke", imageNamed: "Karaoke", nav: GlobalNavPacket(tab: .karaoke, arguments: [:])))
		appFeaturesSegment.append(SocialCellModel("Scrapbook", imageNamed: "Scrapbook", nav: GlobalNavPacket(tab: .scrapbook, arguments: [:])))
		appFeaturesSegment.append(SocialCellModel("Settings", imageNamed: "Settings", nav: GlobalNavPacket(tab: .settings, arguments: [:])))
		// Games Library
		// Lighter Mode
		// About Kraken

  		dataSource.register(with: collectionView, viewController: self)

		
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
    
    // Why is this done with globaNav? Because some of these segues are tab switches on iPhone, and they're all
    // nav pushes on iPad.
    @discardableResult func globalNavigateTo(packet: GlobalNavPacket) -> Bool {
		switch packet.tab {
			case .daily: break
			case .twitarr: performKrakenSegue(.twitarrRoot, sender: nil)
			case .forums: performKrakenSegue(.forumsRoot, sender: nil)
			case .seamail: performKrakenSegue(.seamailRoot, sender: nil)
			case .events: performKrakenSegue(.eventsRoot, sender: nil)
			case .deckPlans: performKrakenSegue(.deckMapRoot, sender: nil)
			case .karaoke: performKrakenSegue(.karaokeRoot, sender: nil)
			case .scrapbook: performKrakenSegue(.scrapbookRoot, sender: nil)
			case .settings: performKrakenSegue(.settingsRoot, sender: nil)
			
			
			default: break
		}
		return true
	}
}
