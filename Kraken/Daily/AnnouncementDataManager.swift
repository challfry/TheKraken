//
//  AnnouncementDataManager.swift
//  Kraken
//
//  Created by Chall Fry on 1/20/20.
//  Copyright © 2020 Chall Fry. All rights reserved.
//

import UIKit

@objc(Announcement) public class Announcement: KrakenManagedObject {
    @NSManaged public var id: String?
    @NSManaged public var text: String?
    @NSManaged public var timestamp: Int64					// Time the announcement was created.
    @NSManaged public var author: KrakenUser?
    @NSManaged public var isActive: Bool					// TRUE if the announcement isn't expired. Defaults to true.
    
    @NSManaged public var viewedBy: Set<KrakenUser>
    
	func buildFromV2(context: NSManagedObjectContext, v2Object: TwitarrV2Announcement) {
		TestAndUpdate(\.id, v2Object.id)
		TestAndUpdate(\.text, v2Object.text)
		TestAndUpdate(\.timestamp, v2Object.timestamp)	
		
		// Set the author
		if author?.username != v2Object.author.username {
			let userPool: [String : KrakenUser ] = context.userInfo.object(forKey: "Users") as! [String : KrakenUser] 
			if let cdAuthor = userPool[v2Object.author.username] {
				author = cdAuthor
			}
		}
	}

	func creationDate() -> Date {
		return Date(timeIntervalSince1970: Double(timestamp) / 1000.0)
	}
	
}

@objc class AnnouncementDataManager: NSObject {
	static let shared = AnnouncementDataManager()
	
	var currentAnnouncements: [Announcement] = []
	@objc dynamic var dailyTabBadgeCount: Int = 0
	
	private var fetchedData: NSFetchedResultsController<Announcement>
	private var rawCurrentAnnouncements: [Announcement] = []

	override init() {
		let fetchRequest = NSFetchRequest<Announcement>(entityName: "Announcement")
		fetchRequest.predicate = NSPredicate(format: "isActive == true")
		fetchRequest.sortDescriptors = [ NSSortDescriptor(key: "timestamp", ascending: false)]
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
				CoreDataLog.error("Couldn't fetch Twitarr posts.", [ "error" : error ])
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

	// Only call this with isComprehensive = true if announcements contains all currently active announcements. If true,
	// we use this to mark any announcements not in the list as expired.
	func ingestAnnouncements(from announcements: [TwitarrV2Announcement], isComprehensive: Bool = false) {
		LocalCoreData.shared.performNetworkParsing { context in
			context.pushOpErrorExplanation("Failure adding announcements to Core Data.")
			
			// This populates "Users" in our context's userInfo to be a dict of [username : KrakenUser]
			let authors = announcements.map { $0.author }
			UserManager.shared.update(users: authors, inContext: context)

			// Get all the Announcement objects already in Core Data whose IDs match those of the announcements we're merging in.
			let newAnnouncementIDs = announcements.map { $0.id }
			let request = LocalCoreData.shared.persistentContainer.managedObjectModel.fetchRequestFromTemplate(withName: "AnnouncementsWithIDs", 
					substitutionVariables: [ "ids" : newAnnouncementIDs ]) as! NSFetchRequest<Announcement>
			let cdAnnouncements = try request.execute()
			let cdAnnouncementsDict = Dictionary(cdAnnouncements.map { ($0.id, $0) }, uniquingKeysWith: { (first,_) in first })

			for ann in announcements {
				let cdAnnouncement = cdAnnouncementsDict[ann.id] ?? Announcement(context: context)
				cdAnnouncement.buildFromV2(context: context, v2Object: ann)
			}
			
			if isComprehensive {
				self.currentAnnouncements.forEach { ann in
					if let currentID = ann.id, !newAnnouncementIDs.contains(currentID) {
						ann.isActive = false
					}
				}
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

class AnnouncementsUpdater: ServerUpdater {
	static let shared = AnnouncementsUpdater()
	var lastError: ServerError?

	init() {
		// Update every 3 minutes. AlertsUpdater, which fires every minute, will also tell us about new announcements.
		// However, only this call will clean up old announcements.
		super.init(60 * 3 )
		refreshOnLogin = false
	}
	
	override func updateMethod() {
		let request = NetworkGovernor.buildTwittarV2Request(withPath:"/api/v2/announcements", query: nil)
		NetworkGovernor.shared.queue(request) { (package: NetworkResponse) in
			var success = false
			if let error = NetworkGovernor.shared.parseServerError(package) {
				self.lastError = error
			}
			else if let data = package.data {
				do {
					self.lastError = nil
					let response = try JSONDecoder().decode(TwitarrV2AnnouncementsResponse.self, from: data)
					AnnouncementDataManager.shared.ingestAnnouncements(from: response.announcements, isComprehensive: true)
					success = true
				}
				catch {
					NetworkLog.error("Failure parsing Announcements response.", ["Error" : error, "url" : request.url as Any])
				}
			}
			
			self.updateComplete(success: success)
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

