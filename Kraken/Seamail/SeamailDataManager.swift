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
    @NSManaged public var opsAddingMessages: Set<PostOpSeamailMessage>?
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
	var lastError : ServerError?
	
	func loadSeamails(done: (() -> Void)? = nil) {
	
		var queryParams: [URLQueryItem] = []
		queryParams.append(URLQueryItem(name:"after", value: self.lastSeamailCheckTime()))
//		queryParams.append(URLQueryItem(name:"app", value:"plain"))
		
		var request = NetworkGovernor.buildTwittarV2Request(withPath:"/api/v2/seamail_threads", query: queryParams)
		NetworkGovernor.addUserCredential(to: &request)
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
				UserManager.shared.update(users: allParticipants, inContext: context)

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
	
	func addNewSeamailMessage(context: NSManagedObjectContext, threadID: String, v2Object: TwitarrV2SeamailMessage) {
		do {
			let request = self.coreData.persistentContainer.managedObjectModel.fetchRequestFromTemplate(withName: "SeamailThreadsWithIDs", 
					substitutionVariables: [ "ids" : [threadID] ]) as! NSFetchRequest<SeamailThread>
			let cdThreads = try request.execute()
			if let thread = cdThreads.first {
				UserManager.shared.update(users: v2Object.readUsers, inContext: context)

				// Yes, even if we're adding a new message, check to see if it's already here. Because networking.
				let message = thread.messages.first { $0.id == v2Object.id } ?? SeamailMessage(context: context)
				message.buildFromV2(context: context, v2Object: v2Object, newThread: thread)
				thread.messages.insert(message)
			}
		}
		catch {
			CoreDataLog.error("Failed to add new Seamail message to CoreData.", ["error" : error])
		}
	}
	
	// Creates a pending POST operation to create a new Seamail thread
	func queueNewSeamailThreadOp(existingOp: PostOpSeamailThread?, subject: String, message: String, 
			recipients: Set<PossibleKrakenUser>, done: @escaping (PostOpSeamailThread?) -> Void) {
		let context = LocalCoreData.shared.networkOperationContext
		context.perform {
			guard let currentUser = CurrentUser.shared.getLoggedInUser(in: context) else { return }
			
			var existingThread: PostOpSeamailThread?
			if let existingOp = existingOp {
				try? existingThread = context.existingObject(with: existingOp.objectID) as? PostOpSeamailThread
			}
			
			let newThread = existingThread ?? PostOpSeamailThread(context: context)
			newThread.subject = subject
			newThread.text = message
			newThread.author = currentUser
			
			// Why both possibleUsers and potentialUsers? I didn't want to create the CoreData objects until a 
			// thread was queued for sending, and I therefore can't create CoreData PotentialUsers while the user is still
			// selecting thread participants.
			for possibleUser in recipients {
				let newPotential = PotentialUser(context: context)
				newPotential.username = possibleUser.username
				if let actualUser = possibleUser.user {
					let actualUserInContext = context.object(with: actualUser.objectID) as? KrakenUser
					newPotential.actualUser = actualUserInContext
				}
				newThread.recipients?.insert(newPotential)
				
				// We could at this point do a final search for actual users matching a username that doesn't have 
				// a KrakenUser attached. But why? If we don't find one, it's still not definitive, it's too late to
				// tell the user anything useful (they already know there might not be an actual user with this name)
				// and we're just going to send the name to the server where it'll get validated anyway.
			}
						
			newThread.readyToSend = true
			do {
				try context.save()
				let mainThreadPost = LocalCoreData.shared.mainThreadContext.object(with: newThread.objectID) as? PostOpSeamailThread 
				done(mainThreadPost)
			}
			catch {
				CoreDataLog.error("Couldn't save context while creating new Seamail thread.", ["error" : error])
				done(nil)
			}
		}
	}
	
	// Creates a pending POST operation to create a new Seamail message
	func queueNewSeamailMessageOp(existingOp: PostOpSeamailMessage?, message: String, 
			thread: SeamailThread, done: @escaping (PostOpSeamailMessage?) -> Void) {
		let context = LocalCoreData.shared.networkOperationContext
		context.perform {
			guard let currentUser = CurrentUser.shared.getLoggedInUser(in: context) else { return }
			do {
				var messageOp: PostOpSeamailMessage
				if let existingOp = existingOp {
					try messageOp = context.existingObject(with: existingOp.objectID) as! PostOpSeamailMessage
				}
				else {
					messageOp = PostOpSeamailMessage(context: context)
				}
				let threadInContext = try context.existingObject(with: thread.objectID) as? SeamailThread
				
				messageOp.text = message
				messageOp.thread = threadInContext
				messageOp.author = currentUser
				messageOp.readyToSend = true
				try context.save()
				let mainThreadPost = LocalCoreData.shared.mainThreadContext.object(with: messageOp.objectID) as? PostOpSeamailMessage 
				done(mainThreadPost)
			}
			catch {
				CoreDataLog.error("Couldn't save context while creating new Seamail thread.", ["error" : error])
				done(nil)
			}
		}
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
