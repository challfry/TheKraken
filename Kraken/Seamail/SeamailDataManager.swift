//
//  SeamailDataManager.swift
//  Kraken
//
//  Created by Chall Fry on 5/5/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit
import CoreData

@objc(SeamailMessage) public class SeamailMessage: KrakenManagedObject {
    @NSManaged public var id: String
    @NSManaged public var author: KrakenUser
    @NSManaged public var text: String
    @NSManaged public var timestamp: Int64	
    @NSManaged public var readUsers: Set<KrakenUser>
    @NSManaged public var thread: SeamailThread

	func buildFromV2(context: NSManagedObjectContext, v2Object: TwitarrV2SeamailMessage, newThread: SeamailThread) {
		TestAndUpdate(\.id, v2Object.id)
		TestAndUpdate(\.text, v2Object.text)
		TestAndUpdate(\.timestamp, v2Object.timestamp)
		if newThread.id != thread.id {
			thread = newThread
		}
		if author.username != v2Object.author.username {
			let userPool: [String : KrakenUser ] = context.userInfo.object(forKey: "Users") as! [String : KrakenUser] 
			if let cdAuthor = userPool[v2Object.author.username] {
				author = cdAuthor
			}
		}
		
		let cdReadUsers = Set(readUsers.map { $0.username })
		let v2ReadUsers = Set(v2Object.readUsers.map { $0.username })
		if v2ReadUsers != cdReadUsers {
			let userPool: [String : KrakenUser ] = context.userInfo.object(forKey: "Users") as! [String : KrakenUser] 
			let newReadUsers = Set(v2ReadUsers.compactMap { userPool[$0] })
			readUsers = newReadUsers
		}
	}
}

@objc(SeamailThread) public class SeamailThread: KrakenManagedObject {

    @NSManaged public var id: String
    @NSManaged public var participants: Set<KrakenUser>
    @NSManaged public var subject: String
    @NSManaged public var messages: Set<SeamailMessage>
    @NSManaged public var timestamp: Int64					// For threads, time of most recent message posted to thread
    @NSManaged public var hasUnreadMessages: Bool

	func buildFromV2(context: NSManagedObjectContext, v2Object: TwitarrV2SeamailThread) {
		TestAndUpdate(\.id, v2Object.id)
		TestAndUpdate(\.subject, v2Object.subject)
		TestAndUpdate(\.timestamp, v2Object.timestamp)
		hasUnreadMessages = v2Object.hasUnreadMessages
//		TestAndUpdate(\.hasUnreadMessages, v2Object.hasUnreadMessages)
		
		let cdParticipants = Set(participants.map { $0.username })
		let v2Participants = Set(v2Object.participants.map { $0.username })
		if v2Participants != cdParticipants {
			let userPool: [String : KrakenUser ] = context.userInfo.object(forKey: "Users") as! [String : KrakenUser] 
			let newParticipants = Set(v2Participants.compactMap { userPool[$0] })
			participants = newParticipants
		}
		
		for message in v2Object.messages {
			let cdMessage = messages.first { $0.id == message.id } ?? SeamailMessage(context: context)
			cdMessage.buildFromV2(context: context, v2Object: message, newThread: self)
			messages.insert(cdMessage)
		}
	}
}

class SeamailDataManager: NSObject {
	static let shared = SeamailDataManager()
	
	private let coreData = LocalCoreData.shared
	var fetchedData: NSFetchedResultsController<SeamailThread>
	var viewDelegates: [NSObject & NSFetchedResultsControllerDelegate] = []


	var lastError : ServerError?
	
	override init() {
		// Init the fetched results controller with a fetch that returns nothing. See the observation block below.
		let fetchRequest = NSFetchRequest<SeamailThread>(entityName: "SeamailThread")
		fetchRequest.predicate = NSPredicate(value: false)
		fetchRequest.fetchBatchSize = 50
		fetchRequest.sortDescriptors = [ NSSortDescriptor(key: "timestamp", ascending: false)]
		fetchedData = NSFetchedResultsController(fetchRequest: fetchRequest,
				managedObjectContext: coreData.mainThreadContext, sectionNameKeyPath: nil, cacheName: nil)
		super.init()

		// When a user is logged in we'll set up the FRC to load the threads which that user can 'see'. Remember, CoreData
		// stores ALL the seamail we ever download, for any user who logs in on this device.
		CurrentUser.shared.tell(self, when: "loggedInUser") { observer, observed in
			if let username = observed.loggedInUser?.username {
	//			observer.fetchedData.fetchRequest.predicate = NSPredicate(format: "'\(username)' IN participants.username")
				observer.fetchedData.fetchRequest.predicate = NSPredicate(format: "ANY participants.username == '\(username)'")
			}
			else {
				// No user is logged in
				observer.fetchedData.fetchRequest.predicate = NSPredicate(value: false)
			}
			try? observer.fetchedData.performFetch()
		}?.execute()
		
		fetchedData.delegate = self
	}
	
	func addDelegate(_ newDelegate: NSObject & NSFetchedResultsControllerDelegate) {
		if !viewDelegates.contains(where: { $0 === newDelegate } ) {
			viewDelegates.insert(newDelegate, at: 0)
		}
	}
	
	func removeDelegate(_ oldDelegate: NSObject & NSFetchedResultsControllerDelegate) {
		viewDelegates.removeAll(where: { $0 === oldDelegate } )
	}

	func loadSeamails(done: (() -> Void)? = nil) {
	
		var queryParams: [URLQueryItem] = []
		queryParams.append(URLQueryItem(name:"after", value: self.lastSeamailCheckTime()))
//		queryParams.append(URLQueryItem(name:"app", value:"plain"))
		
		let request = NetworkGovernor.buildTwittarV2Request(withPath:"/api/v2/seamail_threads", query: queryParams)
		NetworkGovernor.shared.queue(request) { (data: Data?, response: URLResponse?) in
			if let error = NetworkGovernor.shared.parseServerError(data: data, response: response) {
				self.lastError = error
			}
			else if let data = data {
				let decoder = JSONDecoder()
				do {
					let newSeamails = try decoder.decode(TwitarrV2GetSeamailResponse.self, from: data)
					self.addNewSeamails(from: newSeamails.seamailThreads)
				}
				catch {
					NetworkLog.error("Failure parsing Seamails.", ["Error" : error, "url" : request.url as Any])
				} 
			}
			
			done?()
		}

	}
	
	func lastSeamailCheckTime() -> String {
		let date = Settings.shared.lastSeamailCheckTime
		let resultStr = ISO8601DateFormatter().string(from: date)
		return resultStr
	}
	
	func updateLastSeamailCheckTime() {
	
	}
	
	func addNewSeamails(from threads: [TwitarrV2SeamailThread]) {
		let context = coreData.networkOperationContext
		context.perform {
			do {
				// Update all the users in all the theads.
				let allParticipants = threads.flatMap { $0.participants }
				let appParticipantsDict = Dictionary(allParticipants.map { ($0.username, $0) }, 
						uniquingKeysWith: { first, _ in first })
				UserManager.shared.update(users: appParticipantsDict, inContext: context)

				// Fetch all the threads from CD
				let allThreadIDs = threads.map { $0.id }
				let request = self.coreData.persistentContainer.managedObjectModel.fetchRequestFromTemplate(withName: "SeamailThreadsWithIDs", 
						substitutionVariables: [ "ids" : allThreadIDs ]) as! NSFetchRequest<SeamailThread>
				let cdThreads = try request.execute()
				var cdThreadsDict = Dictionary(cdThreads.map { ($0.id, $0) }, uniquingKeysWith: { (first,_) in first })

				for mailThread in threads {
					let cdThread = cdThreadsDict[mailThread.id] ?? SeamailThread(context: context)
					cdThread.buildFromV2(context: context, v2Object: mailThread)
				}

				try context.save()
				self.updateLastSeamailCheckTime()
			}
			catch {
				CoreDataLog.error("Failed to add new Seamails.", ["error" : error])
			}
		}
	}

}

// The data manager can have multiple delegates, all of which are watching the same results set.
extension SeamailDataManager : NSFetchedResultsControllerDelegate {

	func controllerWillChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
		viewDelegates.forEach( { $0.controllerWillChangeContent?(controller) } )
	}

	func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange anObject: Any,
			at indexPath: IndexPath?, for type: NSFetchedResultsChangeType, newIndexPath: IndexPath?) {
		viewDelegates.forEach( { $0.controller?(controller, didChange: anObject, at: indexPath, for: type, newIndexPath: newIndexPath) } )
	}

    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange sectionInfo: NSFetchedResultsSectionInfo, 
    		atSectionIndex sectionIndex: Int, for type: NSFetchedResultsChangeType) {
    	viewDelegates.forEach( { $0.controller?(controller, didChange: sectionInfo, atSectionIndex: sectionIndex, for: type) } )		
	}

	// We can't actually implement this in a multi-delegate model. Also, wth is NSFetchedResultsController doing having a 
	// delegate method that does this?
 //   func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, sectionIndexTitleForSectionName sectionName: String) -> String?
    
	func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
		viewDelegates.forEach( { $0.controllerDidChangeContent?(controller) } )
	}
}


// MARK: - V2 API Decoding

struct TwitarrV2SeamailMessage: Codable {
	let id: String
	let author: TwitarrV2UserInfo
	let text: String
	let timestamp: Int64
	let readUsers: [ TwitarrV2UserInfo ]
	
	enum CodingKeys: String, CodingKey {
		case id, author, text, timestamp
		case readUsers = "read_users"
	}
}

struct TwitarrV2SeamailThread: Codable {
	let id: String
	let participants: [ TwitarrV2UserInfo ]
	let subject: String
	let messages: [ TwitarrV2SeamailMessage ]
	let messageCount: Int
	let timestamp: Int64
	let countIsUnread: Bool
	let hasUnreadMessages: Bool

	enum CodingKeys: String, CodingKey {
		case id, subject, messages, timestamp
		case participants = "users"
		case messageCount = "message_count"
		case countIsUnread = "count_is_unread"
		case hasUnreadMessages = "is_unread"
	}
	
}

// /api/v2/seamail_threads
struct TwitarrV2GetSeamailResponse: Codable {
	let status: String
	let seamailThreads: [TwitarrV2SeamailThread]
	let lastChecked: Int

	enum CodingKeys: String, CodingKey {
		case status
		case seamailThreads = "seamail_threads"
		case lastChecked = "last_checked"
	}
}
