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
	
	lazy var betaCellModel: LocalAnnouncementCellModel = {
		let cell = LocalAnnouncementCellModel()
		cell.headerText = "Kraken Version 1.0 Beta 2"
		cell.authorName = "From: Chall Fry"
		cell.text = "A big thank you to our wonderful beta testers!"
		return cell
	}()
	
	var twitarrCell: SocialCellModel?
	var forumsCell: SocialCellModel?
	var mailCell: SocialCellModel?
	var scheduleCell: SocialCellModel?
	var deckMapCell: SocialCellModel?
	var karaokeCell: SocialCellModel?
	var scrapbookCell: SocialCellModel?
	var settingsCell : SocialCellModel?
	var helpCell: SocialCellModel?
	var aboutCell: SocialCellModel?
	
	override func awakeFromNib() {
		super.awakeFromNib()
		DailyViewController.shared = self
		knownSegues = [.twitarrRoot, .forumsRoot, .seamailRoot, .eventsRoot, .deckMapRoot, .karaokeRoot, .scrapbookRoot, 
				.settingsRoot, .twitarrHelp, .about]
		
		// Set the badge on the Daily tab
		AnnouncementDataManager.shared.tell(self, when: ["dailyTabBadgeCount"]) { observer, observed in
			let badgeCount = observed.dailyTabBadgeCount
			observer.navigationController?.tabBarItem.badgeValue = badgeCount > 0 ? "\(badgeCount)" : nil
		}?.execute()

		// Watch for updates to valid sections
		ValidSectionUpdater.shared.tell(self, when: "lastUpdateTime") {observer, observed in
			observer.updateEnabledFeatures(observed.disabledSections)
		}?.execute()
	}

    override func viewDidLoad() {
        super.viewDidLoad()
		title = "Today"

		dataSource.append(segment: dailySegment)
		dailySegment.append(DailyActivityCellModel())

		dailySegment.append(betaCellModel)
		
		announcementSegment.activate(predicate: NSPredicate(format: "isActive == true"),
				sort: [ NSSortDescriptor(key: "timestamp", ascending: false) ], 
				cellModelFactory: self.createAnnouncementCellModel)
		dataSource.append(segment: announcementSegment)
		
		
		twitarrCell = SocialCellModel("Twittar", imageNamed: "Twitarr",  nav: GlobalNavPacket(from: self, tab: .twitarr))
		forumsCell = SocialCellModel("Forums", imageNamed: "Forums", nav: GlobalNavPacket(from: self, tab: .forums))
		mailCell = SocialCellModel("Seamail", imageNamed: "Seamail", nav: GlobalNavPacket(from: self, tab: .seamail))
		scheduleCell = SocialCellModel("Schedule", imageNamed: "Schedule", nav: GlobalNavPacket(from: self, tab: .events))
		deckMapCell = SocialCellModel("Deck Maps", imageNamed: "Map", nav: GlobalNavPacket(from: self, tab: .deckPlans))
		karaokeCell = SocialCellModel("Karaoke", imageNamed: "Karaoke", nav: GlobalNavPacket(from: self, tab: .karaoke))
		scrapbookCell = SocialCellModel("Scrapbook", imageNamed: "Scrapbook", nav: GlobalNavPacket(from: self, tab: .scrapbook))
		settingsCell = SocialCellModel("Settings", imageNamed: "Settings", nav: GlobalNavPacket(from: self, tab: .settings))
		helpCell = SocialCellModel("Help", imageNamed: "About", nav: GlobalNavPacket(from: self, tab: .twitarrHelp, arguments: ["filename" : "helptext.json"]))
		aboutCell = SocialCellModel("About", imageNamed: "About", nav: GlobalNavPacket(from: self, tab: .about))

		dataSource.append(segment: appFeaturesSegment)
		appFeaturesSegment.append(twitarrCell!)
		appFeaturesSegment.append(forumsCell!)
		appFeaturesSegment.append(mailCell!)
		appFeaturesSegment.append(scheduleCell!)
		appFeaturesSegment.append(deckMapCell!)
		appFeaturesSegment.append(karaokeCell!)
		appFeaturesSegment.append(scrapbookCell!)
		appFeaturesSegment.append(settingsCell!)
		appFeaturesSegment.append(helpCell!)
		appFeaturesSegment.append(aboutCell!)
		
		// Games Library
		// Lighter Mode

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
    	if ValidSectionUpdater.shared.disabledTabs.contains(packet.tab) {
			let replacementVC = DisabledContentViewController(forTab: packet.tab)
			self.navigationController?.pushViewController(replacementVC, animated: true)
			return true
    	}
    
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
			case .twitarrHelp: performKrakenSegue(.twitarrHelp, sender: packet.arguments["filename"])
			case .about: performKrakenSegue(.about, sender: nil)			
			default: break
		}
		return true
	}
	
    func updateEnabledFeatures(_ disabledSections: Set<ValidSectionUpdater.Section>) {
		twitarrCell?.contentDisabled = disabledSections.contains(.stream)
		forumsCell?.contentDisabled = disabledSections.contains(.forums)
		mailCell?.contentDisabled = disabledSections.contains(.seamail)
		scheduleCell?.contentDisabled = disabledSections.contains(.calendar)
		deckMapCell?.contentDisabled = disabledSections.contains(.deckPlans)
		karaokeCell?.contentDisabled = disabledSections.contains(.karaoke)
    }

}
