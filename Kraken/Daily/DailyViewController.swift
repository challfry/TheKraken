//
//  DailyViewController.swift
//  Kraken
//
//  Created by Chall Fry on 9/5/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit

class DailyViewController: BaseCollectionViewController, GlobalNavEnabled {

	lazy var dataSource = KrakenDataSource()
	lazy var dailySegment = FilteringDataSourceSegment()
	lazy var announcementSegment = FRCDataSourceSegment<Announcement>()
	lazy var appFeaturesSegment = FilteringDataSourceSegment()
	
	lazy var betaCellModel: LocalAnnouncementCellModel = {
		let cell = LocalAnnouncementCellModel()
		let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as! String
		let buildVersion = Bundle.main.infoDictionary?["CFBundleVersion"] as! String
		cell.headerText = "Kraken Version \(appVersion)b\(buildVersion)"
		cell.authorName = "From: Chall Fry"
		cell.text = "A big thank you to our wonderful beta testers!"
		return cell
	}()
	
	// Shows up after cruise
	lazy var dataDeletionReminderCellModel: LocalAnnouncementCellModel = {
		let cell = LocalAnnouncementCellModel()
		let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as! String
		let buildVersion = Bundle.main.infoDictionary?["CFBundleVersion"] as! String
		cell.headerText = "Reminder"
		cell.authorName = "From: Chall Fry"
		cell.text = """
				Kraken will automatically purge all cached data on April 1, a couple of weeks after the cruise ends. Photos, \
				posts, messages, favorites, and users will all be gone. You should save any info you want to keep.
				
				If you have photos you want to save, you can do so by tapping on the photo, tapping the Share button, \
				and tapping Save Image.
				"""
				
		cell.shouldBeVisible = (dayAfterCruise() ?? 0) > 1
		return cell
	}()

	var twitarrCell: SocialCellModel?
	var forumsCell: SocialCellModel?
	var mailCell: SocialCellModel?
	var scheduleCell: SocialCellModel?
	var deckMapCell: SocialCellModel?
	var karaokeCell: SocialCellModel?
	var gamesCell: SocialCellModel?
	var scrapbookCell: SocialCellModel?
	var lighterModeCell: SocialCellModel?
	var settingsCell : SocialCellModel?
	var helpCell: SocialCellModel?
	var aboutCell: SocialCellModel?
	
	override func awakeFromNib() {
		super.awakeFromNib()
		knownSegues = [.twitarrRoot, .forumsRoot, .seamailRoot, .eventsRoot, .deckMapRoot, .karaokeRoot, .gamesRoot,
				.scrapbookRoot, .settingsRoot, .twitarrHelp, .about, .lighterMode]
		
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
	
//		dataSource.log.instanceEnabled = true

		dataSource.append(segment: dailySegment)
		dailySegment.append(DailyActivityCellModel())
		dailySegment.append(PortAndThemeCellModel())
//		dailySegment.append(betaCellModel)
		dailySegment.append(dataDeletionReminderCellModel)
		
		announcementSegment.activate(predicate: NSPredicate(format: "isActive == true"),
				sort: [ NSSortDescriptor(key: "timestamp", ascending: false) ], 
				cellModelFactory: self.createAnnouncementCellModel)
		dataSource.append(segment: announcementSegment)
		
		// Lazy or not, we can't make these cells until viewDidLoad time
		twitarrCell = SocialCellModel("Twittar", imageNamed: "Twitarr",  nav: GlobalNavPacket(from: self, tab: .twitarr))
		forumsCell = SocialCellModel("Forums", imageNamed: "Forums", nav: GlobalNavPacket(from: self, tab: .forums))
		mailCell = SocialCellModel("Seamail", imageNamed: "Seamail", nav: GlobalNavPacket(from: self, tab: .seamail))
		scheduleCell = SocialCellModel("Schedule", imageNamed: "Schedule", nav: GlobalNavPacket(from: self, tab: .events))
		deckMapCell = SocialCellModel("Deck Maps", imageNamed: "Map", nav: GlobalNavPacket(from: self, tab: .deckPlans))
		karaokeCell = SocialCellModel("Karaoke", imageNamed: "Karaoke", nav: GlobalNavPacket(from: self, tab: .karaoke))
		gamesCell = SocialCellModel("Games", imageNamed: "Games", nav: GlobalNavPacket(from: self, tab: .games))
		scrapbookCell = SocialCellModel("Scrapbook", imageNamed: "Scrapbook", nav: GlobalNavPacket(from: self, tab: .scrapbook))
		lighterModeCell = SocialCellModel("Lighter Mode", imageNamed: "Flame", nav: GlobalNavPacket(from: self, tab: .lighter))
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
		appFeaturesSegment.append(gamesCell!)
		appFeaturesSegment.append(scrapbookCell!)
		appFeaturesSegment.append(lighterModeCell!)
		appFeaturesSegment.append(settingsCell!)
		appFeaturesSegment.append(helpCell!)
		appFeaturesSegment.append(aboutCell!)
		
		// Lighter Mode
		#if targetEnvironment(macCatalyst) 
			lighterModeCell?.shouldBeVisible = false		
		#endif
		if UIDevice.current.userInterfaceIdiom != .phone {
			lighterModeCell?.shouldBeVisible = false		
		}

  		dataSource.register(with: collectionView, viewController: self)
  		
		// Set the badge on the Seamail cell
		CurrentUser.shared.tell(self, when: ["loggedInUser", "loggedInUser.upToDateSeamailThreads.count", 
				"loggedInUser.seamailParticipant.count"]) { observer, observed in
			if let currentUser = observed.loggedInUser {
				let badgeCount = currentUser.seamailParticipant.count - currentUser.upToDateSeamailThreads.count
				observer.mailCell?.badgeValue = badgeCount > 0 ? "\(badgeCount) new" : nil
			}
			else {
				observer.mailCell?.badgeValue = nil
			}
		}?.execute()

    }
    
    override func viewDidAppear(_ animated: Bool) {
    	super.viewDidAppear(animated)
		dataSource.enableAnimations = true
		AnnouncementDataManager.shared.markAllAnnouncementsRead()
	}
	
	override func viewDidDisappear(_ animated: Bool) {
    	super.viewDidDisappear(animated)
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
    	navigationController?.popToRootViewController(animated: false)
    
    	if ValidSectionUpdater.shared.disabledTabs.contains(packet.tab) {
			let replacementVC = DisabledContentViewController(forTab: packet.tab)
			self.navigationController?.pushViewController(replacementVC, animated: true)
			return true
    	}
    
		switch packet.tab {
			case .daily: break
			case .twitarr: performKrakenSegue(.twitarrRoot, sender: packet)
			case .forums: performKrakenSegue(.forumsRoot, sender: packet)
			case .seamail: performKrakenSegue(.seamailRoot, sender: packet)
			case .events: performKrakenSegue(.eventsRoot, sender: packet)
			case .deckPlans: performKrakenSegue(.deckMapRoot, sender: packet)
			case .karaoke: performKrakenSegue(.karaokeRoot, sender: packet)
			case .games: performKrakenSegue(.gamesRoot, sender: packet)
			case .scrapbook: performKrakenSegue(.scrapbookRoot, sender: packet)
			case .settings: performKrakenSegue(.settingsRoot, sender: packet)
			case .lighter: performKrakenSegue(.lighterMode, sender: packet)
			case .twitarrHelp: performKrakenSegue(.twitarrHelp, sender: packet.arguments["filename"])
			case .about: performKrakenSegue(.about, sender: packet)			
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
