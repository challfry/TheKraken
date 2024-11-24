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
		cell.text = NSAttributedString(string: "A big thank you to our wonderful beta testers!")
		return cell
	}()
	
	// Shows up after cruise
	lazy var dataDeletionReminderCellModel: LocalAnnouncementCellModel = {
		let cell = LocalAnnouncementCellModel()
		let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as! String
		let buildVersion = Bundle.main.infoDictionary?["CFBundleVersion"] as! String
		cell.headerText = "Reminder"
		cell.authorName = "From: Chall Fry"
		cell.text = NSAttributedString(string: """
				Kraken will automatically purge all cached data on April 1, a couple of weeks after the cruise ends. Photos, \
				posts, messages, favorites, and users will all be gone. You should save any info you want to keep.
				
				If you have photos you want to save, you can do so by tapping on the photo, tapping the Share button, \
				and tapping Save Image.
				""")
				
		cell.shouldBeVisible = (dayAfterCruise() ?? 0) > 1
		return cell
	}()
	
	var photostreamCell = PhotostreamCellModel()
	var dayPlannerCell: DayPlannerCellModel = {
		let cell = DayPlannerCellModel()
		CurrentUser.shared.tell(cell, when: "loggedInUser") { observer, observed in 
			observer.shouldBeVisible = observed.isLoggedIn()
		}?.execute()
		return cell
	}()

//	var twitarrCell = SocialCellModel("Twittar", imageNamed: "hourglass")
	var forumsCell = SocialCellModel("Forums", imageNamed: "person.2")
	var mailCell = SocialCellModel("Seamail", imageNamed: "text.bubble")
	var lfgCell = SocialCellModel("LFG", imageNamed: "person.3.sequence.fill")
	var scheduleCell = SocialCellModel("Schedule", imageNamed: "calendar")
	var officialPerformersCell = SocialCellModel("Performers", imageNamed: "figure.taichi")
	var shadowPerformersCell = SocialCellModel("Shadow Cruise", imageNamed: "figure.taichi")
	var deckMapCell = SocialCellModel("Deck Maps", imageNamed: "map")
	var karaokeCell = SocialCellModel("Karaoke", imageNamed: "music.mic")
	var microKaraokeCell = SocialCellModel("Micro Karaoke", imageNamed: "music.mic.circle")
	var gamesCell = SocialCellModel("Games", imageNamed: "suit.club")
//	var phoneCell = SocialCellModel("Shipwide Confabulator", imageNamed: "phone") // voice flinger, hurl chatter
	var phoneCell = SocialCellModel("KrakenTalk", imageNamed: "phone") // voice flinger, hurl chatter
	var scrapbookCell = SocialCellModel("Scrapbook", imageNamed: "Scrapbook")
	var lighterModeCell = SocialCellModel("Lighter Mode", imageNamed: "flame")
	var pirateARCell = SocialCellModel("Pirate Selfie", imageNamed: "flame")
	var profileCell = SocialCellModel("Edit Profile", imageNamed: "person")
	var settingsCell = SocialCellModel("Settings", imageNamed: "wrench.and.screwdriver")
	var helpCell = SocialCellModel("About Twitarr", imageNamed: "questionmark.circle")
	var aboutCell = SocialCellModel("About The Kraken", imageNamed: "questionmark.circle")
	
	required init?(coder: NSCoder) {
		super.init(coder: coder)
		
//		twitarrCell.navPacket = GlobalNavPacket(from: self, tab: .twitarr)
		forumsCell.navPacket = GlobalNavPacket(from: self, tab: .forums)
		mailCell.navPacket = GlobalNavPacket(from: self, tab: .seamail)
		lfgCell.navPacket = GlobalNavPacket(from: self, tab: .lfg)
		scheduleCell.navPacket = GlobalNavPacket(from: self, tab: .events)
		officialPerformersCell.navPacket = GlobalNavPacket(from: self, tab: .officialPerformers, segue: .performerRoot, sender: true)
		shadowPerformersCell.navPacket = GlobalNavPacket(from: self, tab: .shadowPerformers, segue: .performerRoot, sender: false)
		deckMapCell.navPacket = GlobalNavPacket(from: self, tab: .deckPlans)
		karaokeCell.navPacket = GlobalNavPacket(from: self, tab: .karaoke)
		microKaraokeCell.navPacket = GlobalNavPacket(from: self, tab: .microKaraoke)
		gamesCell.navPacket = GlobalNavPacket(from: self, tab: .games)
		phoneCell.navPacket = GlobalNavPacket(from: self, tab: .initiatePhoneCall, segue: .initiatePhoneCall, sender: nil)
		scrapbookCell.navPacket = GlobalNavPacket(from: self, tab: .scrapbook)
		lighterModeCell.navPacket = GlobalNavPacket(from: self, tab: .lighter)
		pirateARCell.navPacket = GlobalNavPacket(from: self, tab: .pirateAR)
		profileCell.navPacket = GlobalNavPacket(from: self, tab: .daily, segue: .editUserProfile, sender: nil)
		settingsCell.navPacket = GlobalNavPacket(from: self, tab: .settings)
		helpCell.navPacket = GlobalNavPacket(from: self,tab: .twitarrHelp, arguments: ["filename" : "twitarrhelptext.md", "title" : "Twitarr Help"])
		aboutCell.navPacket = GlobalNavPacket(from: self, tab: .about)
	}
	
	override func awakeFromNib() {
		super.awakeFromNib()
		
		// Watch for updates to valid sections
		AlertsUpdater.shared.tell(self, when: "lastUpdateTime") {observer, observed in
			observer.updateEnabledFeatures(ValidSections.shared.disabledSections)
		}?.execute()
		
		// Hide cells that are only for logged-in states
		CurrentUser.shared.tell(self, when: "loggedInUser") { observer, observed in
			// The idea here is that while we put a login-gate around content the user may want to get to (like Forums),
			// nobody wants to make an account just so they can...set up their account's profile.
			observer.profileCell.shouldBeVisible = observed.loggedInUser != nil
			
			// Also, reload some data on login 
			if observed.loggedInUser != nil {
				PhotostreamDataManager.shared.updatePhotostream()
			}
		}?.execute()

		// Set the badge on the Daily tab
		AnnouncementDataManager.shared.tell(self, when: ["dailyTabBadgeCount"]) { observer, observed in
			observer.setDailyTabBadgeCount()
		}?.execute()
		CurrentUser.shared.tell(self, when: "loggedInUser.postOps.count") { observer, observed in
			observer.setDailyTabBadgeCount()
		}?.execute()

		// Set the badges on the Seamail cell and tab
		CurrentUser.shared.tell(self, when: "loggedInUser.newSeamailMessages") { (observer: DailyViewController, observed: CurrentUser) in
			let badgeCount = observed.loggedInUser?.newSeamailMessages ?? 0
			observer.mailCell.badgeValue = badgeCount > 0 ? "\(badgeCount) new" : nil
			if let tabController = observer.navigationController?.tabBarController as? RootTabBarViewController {
				tabController.setBadge(for: .seamail, to: Int(badgeCount))
			}
		}?.execute()
		
		// Set the badge on the LFG cell
		CurrentUser.shared.tell(self, when: "loggedInUser.newLFGMessages") { observer, observed in
			let badgeCount = observed.loggedInUser?.newLFGMessages ?? 0
			observer.lfgCell.badgeValue = badgeCount > 0 ? "\(badgeCount) new" : nil
		}?.execute()
		
		// Set the badge on the MicroKaraoke cell
		CurrentUser.shared.tell(self, when: "loggedInUser.microKaraokeVideos") { observer, observed in
			let badgeCount = observed.loggedInUser?.microKaraokeVideos ?? 0
			observer.microKaraokeCell.badgeValue = badgeCount > 0 ? "\(badgeCount) new" : nil
		}?.execute()
		
		// Set the badge on the Settings cell
		CurrentUser.shared.tell(self, when: "loggedInUser.postOps.count") { observer, observed in
			let badgeCount = observed.loggedInUser?.postOps?.count ?? 0
			observer.settingsCell.badgeValue = badgeCount > 0 ? "\(badgeCount) new" : nil
		}?.execute()
	}
	
	func setDailyTabBadgeCount() {
		let badgeCount = AnnouncementDataManager.shared.dailyTabBadgeCount + (CurrentUser.shared.loggedInUser?.postOps?.count ?? 0)
		navigationController?.tabBarItem.badgeValue = badgeCount > 0 ? "\(badgeCount)" : nil
	}

    override func viewDidLoad() {
        super.viewDidLoad()
		title = "Today"
	
//		dataSource.log.instanceEnabled = true
		dataSource.viewController = self

		dataSource.append(segment: dailySegment)
		dailySegment.append(DailyActivityCellModel())
		dailySegment.append(PortAndThemeCellModel())
//		dailySegment.append(betaCellModel)
		dailySegment.append(dataDeletionReminderCellModel)
		
		// displayUntil > Date() only works to filter out announcements that expired before the app launched. While running,
		// we have to test on a timer and set isActive to false when they expire.
		announcementSegment.activate(predicate: NSPredicate(format: "isActive == true AND displayUntil > %@", cruiseCurrentDate() as NSDate),
				sort: [ NSSortDescriptor(key: "updatedAt", ascending: false) ], 
				cellModelFactory: self.createAnnouncementCellModel)
		dataSource.append(segment: announcementSegment)
		
		dataSource.append(segment: appFeaturesSegment)
		appFeaturesSegment.append(photostreamCell)		
		appFeaturesSegment.append(dayPlannerCell)		
//		appFeaturesSegment.append(twitarrCell)
		appFeaturesSegment.append(forumsCell)
		appFeaturesSegment.append(mailCell)
		appFeaturesSegment.append(lfgCell)
		appFeaturesSegment.append(scheduleCell)
		appFeaturesSegment.append(officialPerformersCell)
		appFeaturesSegment.append(shadowPerformersCell)
		appFeaturesSegment.append(deckMapCell)
		appFeaturesSegment.append(karaokeCell)
		appFeaturesSegment.append(microKaraokeCell)
		appFeaturesSegment.append(gamesCell)
//		appFeaturesSegment.append(scrapbookCell)
		appFeaturesSegment.append(lighterModeCell)
		appFeaturesSegment.append(phoneCell)
//		appFeaturesSegment.append(pirateARCell)
		appFeaturesSegment.append(profileCell)
		appFeaturesSegment.append(settingsCell)
		appFeaturesSegment.append(helpCell)
		appFeaturesSegment.append(aboutCell)
		
		// Lighter Mode
		#if targetEnvironment(macCatalyst) 
			lighterModeCell.shouldBeVisible = false		
		#endif
		if UIDevice.current.userInterfaceIdiom != .phone {
			lighterModeCell.shouldBeVisible = false		
		}

  		dataSource.register(with: collectionView, viewController: self)
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
    
// MARK: Navigation
	override var knownSegues : Set<GlobalKnownSegue> {
		Set<GlobalKnownSegue>([ 
				.twitarrRoot,
				.forumsRoot, 
				.seamailRoot, .showSeamailThread, .lfgRoot,
				.eventsRoot, .singleEvent, .performerRoot, 
				.privateEventCreate, .dayPlannerRoot,
				.gamesRoot, .karaokeRoot, .microKaraokeRoot, 
				.userProfile_Name, .userProfile_User, .editUserProfile, 
				.deckMapRoot, .scrapbookRoot, .settingsRoot, .twitarrHelp, .about, .lighterMode, 
				.pirateAR, .initiatePhoneCall, .photoStreamCamera])
	}
    
    // Why is this done with globaNav? Because some of these segues are tab switches on iPhone, and they're all
    // nav pushes on iPad.
    @discardableResult func globalNavigateTo(packet: GlobalNavPacket) -> Bool {
    	// If this is a true 'global' nav, switch to the Daily tab and pop all VCs.
    	if let tbc = self.tabBarController {
    		tbc.selectedViewController = self.navigationController
    	}
    	navigationController?.popToRootViewController(animated: false)
    
    	if ValidSections.shared.disabledTabs.contains(packet.tab) {
			let replacementVC = DisabledContentViewController(forTab: packet.tab)
			self.navigationController?.pushViewController(replacementVC, animated: true)
			return true
    	}
    
		switch packet.tab {
			case .daily:
				if let segue = packet.segue {
					performKrakenSegue(segue, sender: packet.sender)
				}
			case .twitarr: performKrakenSegue(.twitarrRoot, sender: packet)
			case .forums: performKrakenSegue(.forumsRoot, sender: packet)
			case .seamail: performKrakenSegue(.seamailRoot, sender: packet)
			case .lfg: performKrakenSegue(.lfgRoot, sender: packet)
			case .events: performKrakenSegue(.eventsRoot, sender: packet)
			
			case .officialPerformers: performKrakenSegue(.performerRoot, sender: packet)
			case .shadowPerformers: performKrakenSegue(.performerRoot, sender: packet)
			case .deckPlans: performKrakenSegue(.deckMapRoot, sender: packet)
			case .karaoke: performKrakenSegue(.karaokeRoot, sender: packet)
			case .microKaraoke: performKrakenSegue(.microKaraokeRoot, sender: packet)
			case .games: performKrakenSegue(.gamesRoot, sender: packet)
			case .initiatePhoneCall: performKrakenSegue(.initiatePhoneCall, sender: packet)
			case .editUserProfile: performKrakenSegue(.editUserProfile, sender: packet)
			case .scrapbook: performKrakenSegue(.scrapbookRoot, sender: packet)
			case .settings: performKrakenSegue(.settingsRoot, sender: packet)
			case .lighter: performKrakenSegue(.lighterMode, sender: packet)
			case .pirateAR: performKrakenSegue(.pirateAR, sender: packet)
			
			case .twitarrHelp: showTextFile(title: "Twitarr Help", serverPath: "/public/twitarrhelptext.md")
			case .codeOfConduct: showTextFile(title: "Code Of Conduct", serverPath: "/public/codeofconduct.md")
			case .about: showTextFile(title: "About Kraken", serverPath: "", localPath: "AboutKraken.md")
			case .faq: showTextFile(title: "Cruise FAQ", serverPath: "/public/faq.html")
			case .serverFile:
				if let url = packet.arguments["url"] as? URL,  ["twitarr.com", "joco.hollandamerica.com", 
						Settings.shared.settingsBaseURL.host].contains(url.host ?? "nohostfoundasdfasfasf") {
					showTextFile(title: "", serverPath: url.path)
				}
				else {
					// Alert
				}

			case .unknown: break
		}
		
		if let username = packet.arguments["profile"] {
			performKrakenSegue(.userProfile_Name, sender: username)			
		}
		return true
	}
	
	func showTextFile(serverURL: URL) {
		// Filetypes we can show with ServerTextFileViewController
		if ServerTextFileParser.parseableFileTypes().contains(serverURL.pathExtension) || ["html", ""].contains(serverURL.pathExtension) {
			showTextFile(title: "", serverPath: serverURL.path)
		}
		else {
			let alert = UIAlertController(title: "Download and Save", message: 
					"Download the file \(serverURL.lastPathComponent) and save it locally? You can manage the file in the Files app once downloaded.", 
					preferredStyle: .alert) 
			alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: "Cancel action"), style: .cancel, handler: nil))
			alert.addAction(UIAlertAction(title: NSLocalizedString("Save", comment: "Default action"), 
					style: .default, handler: { _ in
						_ = ServerTextFileParser(forPath: serverURL.path, saveFile: true)
					}))
			present(alert, animated: true, completion: nil)
		}
	}
	
	func showTextFile(title: String, serverPath: String, localPath: String? = nil) {
		let storyboard = UIStoryboard(name: "Main", bundle: nil)
		if let textFileVC = storyboard.instantiateViewController(withIdentifier: "ServerTextFileDisplay") as? ServerTextFileViewController {
			textFileVC.package = ServerTextFileSeguePackage(titleText: title, serverFilePath: serverPath, localFilePath: localPath)
			present(textFileVC, animated: true, completion: nil)
		}
	}
	
    func updateEnabledFeatures(_ disabledSections: Set<ValidSections.Section>) {
//		twitarrCell.contentDisabled = disabledSections.contains(.stream)
		forumsCell.contentDisabled = disabledSections.contains(.forums)
		mailCell.contentDisabled = disabledSections.contains(.seamail)
		lfgCell.contentDisabled = disabledSections.contains(.lfg)
		scheduleCell.contentDisabled = disabledSections.contains(.calendar)
		officialPerformersCell.contentDisabled = disabledSections.contains(.performers)
		shadowPerformersCell.contentDisabled = disabledSections.contains(.performers)
		deckMapCell.contentDisabled = disabledSections.contains(.deckPlans)
		karaokeCell.contentDisabled = disabledSections.contains(.karaoke)
		microKaraokeCell.contentDisabled = disabledSections.contains(.microKaraoke)
		gamesCell.contentDisabled = disabledSections.contains(.games)
		phoneCell.contentDisabled = disabledSections.contains(.phonecall)
		profileCell.contentDisabled = disabledSections.contains(.editUserProfile)
    }
    
	// This is the handler for the CameraViewController's unwind segue. Pull the captured photo out of the
	// source VC to get the photo that was taken.
	@IBAction func dismissingCamera(_ segue: UIStoryboardSegue) {
//		guard let sourceVC = segue.source as? CameraViewController else { return }
//		if let photoPacket = sourceVC.capturedPhoto {
//			switch photoPacket {
//			case .camera(let photo): break
//			case .image(let image): break
//			case .library: break
//			case .data: break
//			case .server: break
//			}
//		}
	}	

	// This is the unwind segue from the compose view for Personal Events.
	@IBAction func dismissingCreateEvent(_ segue: UIStoryboardSegue) {
		SeamailDataManager.shared.loadSeamails()
	}	
	

}
