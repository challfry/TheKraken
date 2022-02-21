//
//  AnnouncementDataManager.swift
//  Kraken
//
//  Created by Chall Fry on 1/20/20.
//  Copyright © 2020 Chall Fry. All rights reserved.
//

import UIKit
import CoreData

@objc(Announcement) public class Announcement: KrakenManagedObject {
    @NSManaged public var id: Int64
    @NSManaged public var text: String?
    @NSManaged public var updatedAt: Date					// Time the announcement was created/updated
    @NSManaged public var displayUntil: Date				
    @NSManaged public var author: KrakenUser?
    @NSManaged public var isActive: Bool					// TRUE if the announcement isn't expired. Defaults to true.
    
    @NSManaged public var viewedBy: Set<KrakenUser>
    
	override public func awakeFromInsert() {
		setPrimitiveValue(Date(), forKey: "updatedAt")
		setPrimitiveValue(Date(), forKey: "displayUntil")
	}

	func buildFromV3(context: NSManagedObjectContext, v3Object: TwitarrV3AnnouncementData) {
		TestAndUpdate(\.id, Int64(v3Object.id))
		TestAndUpdate(\.text, v3Object.text)
		if updatedAt != v3Object.updatedAt {
			self.updatedAt = v3Object.updatedAt
		}
		if displayUntil != v3Object.displayUntil {
			self.displayUntil = v3Object.displayUntil
		}
		isActive = true
		
		// Set the author
		if author?.userID != v3Object.author.userID {
			let userPool: [UUID : KrakenUser] = context.userInfo.object(forKey: "Users") as! [UUID : KrakenUser] 
			if let cdAuthor = userPool[v3Object.author.userID] {
				author = cdAuthor
			}
		}
	}
	
	// Cells showing announcements should call this on a timer to force expiration, because FetchedResultsControllers can't.
	// Well, they can handle the initial check, but once the FRC is open, an expired announcement can't be dismissed.
	func updateIsActive() {
		if isActive, displayUntil < Date() {
			LocalCoreData.shared.performLocalCoreDataChange() { context, currentUser in
				if let announcementInContext = try? context.existingObject(with: self.objectID) as? Announcement {
					announcementInContext.isActive = false
				}
			}
		}
	}
}

@objc class AnnouncementDataManager: NSObject {
	static let shared = AnnouncementDataManager()
	var lastError: Error?
	
	var currentAnnouncements: [Announcement] = []
	
	@objc dynamic var dailyTabBadgeCount: Int = 0
	
	private var fetchedData: NSFetchedResultsController<Announcement>
	private var serverActiveIds: [Int64] = []
	
	override init() {
		let fetchRequest = NSFetchRequest<Announcement>(entityName: "Announcement")
//		fetchRequest.predicate = NSPredicate(format: "isActive == true AND displayUntil > %@", Date() as NSDate)
		fetchRequest.predicate = NSPredicate(format: "isActive == true")
		fetchRequest.sortDescriptors = [ NSSortDescriptor(key: "updatedAt", ascending: false)]
		fetchRequest.fetchBatchSize = 50
		self.fetchedData = NSFetchedResultsController(fetchRequest: fetchRequest, managedObjectContext: LocalCoreData.shared.mainThreadContext, 
				sectionNameKeyPath: nil, cacheName: nil)
		super.init()
		
		DispatchQueue.main.async {
			
			self.fetchedData.delegate = self
			do {
				try self.fetchedData.performFetch()
				if let announcements = self.fetchedData.fetchedObjects {
					self.currentAnnouncements = announcements
				}
			}
			catch {
				CoreDataLog.error("Couldn't fetch Announcements.", [ "error" : error ])
			}
			
			// Update our badge count if user state changes
			CurrentUser.shared.tell(self, when: ["loggedInUser", "loggedInUser.upToDateAnnouncements.count"]) { observer, observed in
				observer.updateBadgeCount()
			}?.execute()
		}
	}
	
	func updateBadgeCount() {
		if let currentUser = CurrentUser.shared.loggedInUser {
			dailyTabBadgeCount = Set(currentAnnouncements).subtracting(currentUser.upToDateAnnouncements).count
		}
		else {
			// If nobody's logged in, let's just not show a badge for Announcements. The issue is that I'd need to add
			// a new way to mark announcements as 'seen' when nobody's logged in, in order to clear the badge.
			dailyTabBadgeCount = 0
		}
	}
		
	func markAllAnnouncementsRead() {
		LocalCoreData.shared.performLocalCoreDataChange() { context, currentUser in
			for announcement in self.currentAnnouncements {
				if let announcementInContext = try? context.existingObject(with: announcement.objectID) as? Announcement {
					if !announcementInContext.viewedBy.contains(currentUser) {
						announcementInContext.viewedBy.insert(currentUser)
					}
				}
			}
		}
	}
	
	func updateAnnouncementCounts(activeIDs: [Int64], unseenCount: Int64) {
		// Don't use unseenCount to decide whether to grab announcements. Even if the user has 'seen' the announcement
		// on another device we still need to load it.
		currentAnnouncements.forEach { $0.updateIsActive() }
		let localActiveIDs = Set(currentAnnouncements.map { $0.id })
		serverActiveIds = activeIDs
		if !localActiveIDs.isSuperset(of: activeIDs) {
			updateAnnouncements()
		}
	}

	func updateAnnouncements() {
		let request = NetworkGovernor.buildTwittarRequest(withPath:"/api/v3/notification/announcements", query: nil)
		NetworkGovernor.shared.queue(request) { (package: NetworkResponse) in
			if let error = NetworkGovernor.shared.parseServerError(package) {
				self.lastError = error
			}
			else if let data = package.data {
				do {
					self.lastError = nil
					let response = try Settings.v3Decoder.decode([TwitarrV3AnnouncementData].self, from: data)
					self.ingestAnnouncements(from: response, isComprehensive: true)
				}
				catch {
					NetworkLog.error("Failure parsing Announcements response.", ["Error" : error, "url" : request.url as Any])
				}
			}
		}
	}

	// Only call this with isComprehensive = true if announcements contains all currently active announcements. If true,
	// we use this to mark any announcements not in the list as expired.
	func ingestAnnouncements(from announcements: [TwitarrV3AnnouncementData], isComprehensive: Bool = false) {
		LocalCoreData.shared.performNetworkParsing { context in
			context.pushOpErrorExplanation("Failure adding announcements to Core Data.")
			
			// This populates "Users" in our context's userInfo to be a dict of [username : KrakenUser]
			let authors = announcements.map { $0.author }
			UserManager.shared.update(users: authors, inContext: context)

			// Get all the Announcement objects already in Core Data whose IDs match those of the announcements we're merging in.
			let newAnnouncementIDs = announcements.map { Int64($0.id) }
			let request = LocalCoreData.shared.persistentContainer.managedObjectModel.fetchRequestFromTemplate(withName: "AnnouncementsWithIDs", 
					substitutionVariables: [ "ids" : newAnnouncementIDs ]) as! NSFetchRequest<Announcement>
			let cdAnnouncements = try request.execute()
			let cdAnnouncementsDict = Dictionary(cdAnnouncements.map { ($0.id, $0) }, uniquingKeysWith: { (first,_) in first })

			var hasNewAnnouncement = false
			for ann in announcements {
				if cdAnnouncementsDict[Int64(ann.id)] == nil {
					hasNewAnnouncement = true
				}
				let cdAnnouncement = cdAnnouncementsDict[Int64(ann.id)] ?? Announcement(context: context)
				cdAnnouncement.buildFromV3(context: context, v3Object: ann)
			}
			
			if isComprehensive {
				self.currentAnnouncements = self.currentAnnouncements.filter { ann in
					if !newAnnouncementIDs.contains(ann.id) || ann.displayUntil < Date() {
						ann.isActive = false
						return false
					}
					return true
				}
			}
			
			DispatchQueue.main.asyncAfter(deadline: .now() + DispatchTimeInterval.seconds(1)) {
				self.updateBadgeCount()
				if hasNewAnnouncement {
					self.postNewAnnouncementNotification()
				}
			}
		}
	}
	
	// Only call this fn when there's a new announcement to show the user. Creates a local notification.
	// And, only call this fn ONCE for each new announcement.
	// For now, the notification just tells the user to open the app and read the announcement--it doesn't put the
	// contents of the announcement in the notification.
	func postNewAnnouncementNotification() {
		// If the pushProvider is running, it'll post this for us
		guard LocalPush.shared.pushManager?.isActive != true else { return }
		let content = UNMutableNotificationContent()
		content.title = "New Twitarr Announcement"
		content.body = "Tap to view this announcement in The Kraken."
		content.userInfo = ["Announcement" : 0]

		let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
		let uuidString = UUID().uuidString
		let request = UNNotificationRequest(identifier: uuidString, content: content, trigger: trigger)

		// Schedule the request with the system.
		let notificationCenter = UNUserNotificationCenter.current()
		notificationCenter.add(request) { (error) in
			if error != nil {
				RefreshLog.error("Couldn't create local notification for Announcement.", ["error": error as Any])
			}
			else {
			}
		}
	}
	
}

extension AnnouncementDataManager: NSFetchedResultsControllerDelegate {
	// MARK: NSFetchedResultsControllerDelegate

	func controllerWillChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
	}

	func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange anObject: Any,
			at indexPath: IndexPath?, for type: NSFetchedResultsChangeType, newIndexPath: IndexPath?) {
	}

    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange sectionInfo: NSFetchedResultsSectionInfo, 
    		atSectionIndex sectionIndex: Int, for type: NSFetchedResultsChangeType) {
	}
    
	func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
		if let announcements = controller.fetchedObjects as? [Announcement] {
			currentAnnouncements = announcements
		}
	}
}


// MARK: - V2 API Decoding 

struct TwitarrV2Announcement: Codable {
    let id: String
	let author: TwitarrV2UserInfo
	let text: String
    let timestamp: Int64
}

// GET /api/v2/announcements
struct TwitarrV2AnnouncementsResponse: Codable {
	let status: String
	let announcements: [TwitarrV2Announcement]
}

// MARK: V3 API Decoding

public struct TwitarrV3AnnouncementData: Codable {
	/// Only THO and admins need to send Announcement IDs back to the API (to modify or delete announcements, for example), but caching clients can still use the ID
	/// to correlate announcements returned by the API with cached ones.
	var id: Int
	/// The author of the announcement.
	var author: TwitarrV3UserHeader
	/// The contents of the announcement.
	var text: String
	/// When the announcement was last modified.
	var updatedAt: Date
	/// Announcements are considered 'active' until this time. After this time, `GET /api/v3/notification/announcements` will no longer return the announcement,
	/// and caching clients should stop showing it to users.
	var displayUntil: Date
	/// TRUE if the announcement has been deleted. Only THO/admins can fetch deleted announcements; will always be FALSE for other users.
	var isDeleted: Bool
}
