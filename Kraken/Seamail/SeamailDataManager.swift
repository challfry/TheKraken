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
    @NSManaged public var id: Int64
    @NSManaged public var author: KrakenUser?
    @NSManaged public var text: String
    @NSManaged public var timestamp: Date	
    @NSManaged public var readUsers: Set<KrakenUser>
    @NSManaged public var thread: SeamailThread?

	override public func awakeFromInsert() {
		super.awakeFromInsert()
		timestamp = Date()
	}
	
	func buildFromV3(context: NSManagedObjectContext, v3Object: TwitarrV3FezPostData, newThread: SeamailThread) {
		TestAndUpdate(\.id, Int64(v3Object.postID))
		TestAndUpdate(\.text, v3Object.text)
		TestAndUpdate(\.timestamp, v3Object.timestamp)
		if newThread.id != thread?.id {
			thread = newThread
		}
		if author?.userID != v3Object.author.userID {
			let userPool: [UUID : KrakenUser ] = context.userInfo.object(forKey: "Users") as! [UUID : KrakenUser] 
			if let cdAuthor = userPool[v3Object.author.userID] {
				author = cdAuthor
			}
		}
		
		// FIXME: Not handled: Image
	}
}

@objc(SeamailReadCount) public class SeamailReadCount: KrakenManagedObject {
    @NSManaged public var postCount: Int32			// How many posts *this user* sees
    @NSManaged public var readCount: Int32			// From server: How many posts this user has read. Should be <= postCount
    @NSManaged public var viewedCount: Int32		// Highest # post this user has scrolled to locally.
    
    @NSManaged public var thread: SeamailThread
    @NSManaged public var user: KrakenUser

}

@objc(SeamailThread) public class SeamailThread: KrakenManagedObject {

    @NSManaged public var id: UUID
    @NSManaged public var fezType: String
    @NSManaged public var participants: Set<KrakenUser>		// ALL participants: attendees + waitlisters. Unordered.
    @NSManaged public var subject: String
    @NSManaged public var messages: Set<SeamailMessage>
    @NSManaged public var opsAddingMessages: Set<PostOpSeamailMessage>?
    @NSManaged public var owner: KrakenUser?
    @NSManaged public var lastModTime: Date			// Date of last post, user join/leave, or info change
    @NSManaged public var readCounts: Set<SeamailReadCount>	// only for intersection(participants & logged in users)
    
    
    // Only used for LFGs (not .open or .closed fezType values)
    @NSManaged public var info: String?
    @NSManaged public var startTime: Date?				// Start/end time for the event, not related to create time of thread.
    @NSManaged public var endTime: Date?
    @NSManaged public var location: String?
    @NSManaged public var attendees: NSMutableOrderedSet	// <KrakenUser> Shows the attendees/waitlisters in join order.
    @NSManaged public var waitList: NSMutableOrderedSet		// <KrakenUser>
        
    // When a user reads a Seamail thread we mark it as read read by adding them to this set. When new messages arrive
    // for a thread we removeAll on this set. Therefore, any threads NOT in the currentUser's upToDateSeamailThreads set
    // (the inverse relationship) have new messages.
	@NSManaged public var fullyReadBy: Set<KrakenUser>
    
	override public func awakeFromInsert() {
		super.awakeFromInsert()
		id = UUID()
		lastModTime = Date()
		startTime = Date()
		endTime = Date()
	}

    func buildFromV3(context: NSManagedObjectContext, v3Object: TwitarrV3FezData) throws {
		TestAndUpdate(\.id, v3Object.fezID)
		TestAndUpdate(\.fezType, v3Object.fezType.rawValue)
		TestAndUpdate(\.subject, v3Object.title)
		TestAndUpdate(\.lastModTime, v3Object.lastModificationTime)
		TestAndUpdate(\.info, v3Object.info)
		TestAndUpdate(\.startTime, v3Object.startTime)
		TestAndUpdate(\.endTime, v3Object.endTime)
		TestAndUpdate(\.location, v3Object.location)
		
		// Users: Owner, participants, and waitlisters
		let userPool: [UUID : KrakenUser ] = context.userInfo.object(forKey: "Users") as! [UUID : KrakenUser]
		if let threadOwner = userPool[v3Object.owner.userID], self.owner != threadOwner {
			self.owner = threadOwner
		}
		// Members should be nonnil for seamails--otherwise how did we get here?
		if let members = v3Object.members {
			var newParticipantList: Set<KrakenUser> = []
			let newAttendeeList = NSMutableOrderedSet()
			let newWaitlist = NSMutableOrderedSet()
			for participant in members.participants {
				if let cdUser = userPool[participant.userID] {
					newParticipantList.insert(cdUser)
					newAttendeeList.add(cdUser)
				}
			}
			for waitlister in members.waitingList {
				if let cdUser = userPool[waitlister.userID] {
					newParticipantList.insert(cdUser)
					newWaitlist.add(cdUser)
				}
			}
			if newParticipantList != participants {
				participants = newParticipantList
			}
			if newAttendeeList != attendees {
				attendees = newAttendeeList
			}
			if newWaitlist != waitList {
				waitList = newWaitlist
			}
		
			// Posts
			if let posts = members.posts {
				let postIDs = posts.map { $0.postID }
				let request = NSFetchRequest<SeamailMessage>(entityName: "SeamailMessage")
				request.predicate = NSPredicate(format: "id IN %@", postIDs)
				let cdResults = try context.fetch(request)
				let cdPostsDict = Dictionary(cdResults.map { ($0.id, $0) }, uniquingKeysWith: { (first,_) in first })
				for post in posts {
					let postID = Int64(post.postID)
					let cdPost = cdPostsDict[postID] ?? SeamailMessage(context: context) 
					cdPost.buildFromV3(context: context, v3Object: post, newThread: self)
				}
			}
			
			// Read Counts
			if let currentUser = CurrentUser.shared.getLoggedInUser(in: context) {
				let userParticipant = try getReadCountsInternal(context: context, user: currentUser)
				if userParticipant.postCount != members.postCount {
					userParticipant.postCount = Int32(members.postCount)
					fullyReadBy.removeAll()
					if members.readCount == members.postCount {
						fullyReadBy.insert(currentUser)
					}
				}
				if userParticipant.readCount != members.readCount {
					userParticipant.readCount = Int32(members.readCount)
				}
			}
		}
    }
	
	func getReadCounts(done: @escaping (SeamailReadCount) -> Void) {
		LocalCoreData.shared.performLocalCoreDataChange { context, currentUser in
			let selfInContext = try context.existingObject(with: self.objectID) as! SeamailThread
			let result = try selfInContext.getReadCountsInternal(context: context, user: currentUser)
			LocalCoreData.shared.setAfterSaveBlock(for: context) { success in
				if success {
					DispatchQueue.main.async {
						done(result)
					}
				}
			}
		}
	}	
	
	func getReadCountsInternal(context: NSManagedObjectContext, user: KrakenUser? = nil) throws -> SeamailReadCount {
		guard let userToSearch = user ?? CurrentUser.shared.getLoggedInUser(in: context) else {
			throw KrakenError("Not logged in.")
		}
		guard context == self.managedObjectContext && context == userToSearch.managedObjectContext else {
			throw KrakenError("Wrong Context for getReadCounts.")
		}
		if let userParticipant = readCounts.first(where: { $0.user.userID == userToSearch.userID }) {
			return userParticipant
		}
		let userParticipant = SeamailReadCount(context: context)
		userParticipant.user = userToSearch
		userParticipant.thread = self
		readCounts.insert(userParticipant)
		return userParticipant
	}
		
	func markPostAsRead(index: Int) {
		LocalCoreData.shared.performLocalCoreDataChange() { context, currentUser in
			context.pushOpErrorExplanation("Failed to mark Seamail Thread as read.")
			if let selfInContext = context.object(with: self.objectID) as? SeamailThread {
				let readCounts = try selfInContext.getReadCountsInternal(context: context, user: currentUser)
				if readCounts.viewedCount < index + 1 {
					readCounts.viewedCount = Int32(index) + 1
				}
				if readCounts.viewedCount >= readCounts.postCount, let currentUser = CurrentUser.shared.getLoggedInUser(in: context), 
						 !selfInContext.fullyReadBy.contains(currentUser) {
					selfInContext.fullyReadBy.insert(currentUser) 
				}
				// If there are posts to be loaded, and we're near the end of loaded msgs
				if selfInContext.messages.count < readCounts.postCount && selfInContext.messages.count > index + 15 {
					SeamailDataManager.shared.loadSeamailThread(thread: selfInContext, start: selfInContext.messages.count) {}
				}
			}
		}
	}
}

@objc class SeamailDataManager: NSObject {
	static let shared = SeamailDataManager()
	
	private let coreData = LocalCoreData.shared
	var lastError : ServerError?
	@objc dynamic var isLoading = false
	
	var recentLoads: [UUID : Date] = [:]
	
// MARK: Methods
	func loadSeamails(done: (() -> Void)? = nil) {
		// TODO: Add Limiter

		guard !isLoading, let _ = CurrentUser.shared.loggedInUser else {
			done?()
			return
		}
		isLoading = true
		
		var queryParams: [URLQueryItem] = []
		queryParams.append(URLQueryItem(name: "type", value: "closed"))
		queryParams.append(URLQueryItem(name: "type", value: "open"))
//		queryParams.append(URLQueryItem(name:"after", value: "\(currentUser.lastSeamailCheckTime)"))
//		queryParams.append(URLQueryItem(name:"app", value:"plain"))
		
		var request = NetworkGovernor.buildTwittarRequest(withPath:"/api/v3/fez/joined", query: queryParams)
		NetworkGovernor.addUserCredential(to: &request)
		NetworkGovernor.shared.queue(request) { (package: NetworkResponse) in
			if let error = NetworkGovernor.shared.parseServerError(package) {
				self.lastError = error
			}
			else if let data = package.data {
				do {
					let newSeamails = try Settings.v3Decoder.decode(TwitarrV3FezListData.self, from: data)
					self.ingestSeamailThreads(from: newSeamails.fezzes)
				}
				catch {
					NetworkLog.error("Failure parsing Seamails.", ["Error" : error, "url" : request.url as Any])
				} 
			}
			
			done?()
			self.isLoading = false
		}
	}
	
	func updateSeamailThreadID(threadID: UUID) {
		do {
			let request = NSFetchRequest<SeamailThread>(entityName: "SeamailThread")
			request.predicate = NSPredicate(format: "id == %@", threadID as CVarArg)
			request.fetchLimit = 1
			let cdThreads = try LocalCoreData.shared.mainThreadContext.fetch(request)
			if let cdThread = cdThreads.first {
				loadSeamailThread(thread: cdThread, done: {})
			}
		}
		catch {
			print(error)
		}
	}
	
	func loadSeamailThread(thread: SeamailThread, start: Int = -1, done: @escaping () -> Void) {
		if let lastLoadDate = recentLoads[thread.id], lastLoadDate.timeIntervalSinceNow > -10.0 {
			return
		}
		recentLoads[thread.id] = Date()

		var queryParams: [URLQueryItem] = []
		let startParam = start != -1 ? start : thread.messages.count
		queryParams.append(URLQueryItem(name:"start", value: "\(startParam)"))
		var request = NetworkGovernor.buildTwittarRequest(withPath:"/api/v3/fez/\(thread.id)", query: queryParams)
		NetworkGovernor.addUserCredential(to: &request)
		NetworkGovernor.shared.queue(request) { (package: NetworkResponse) in
			if let error = NetworkGovernor.shared.parseServerError(package) {
				self.lastError = error
			}
			else if let data = package.data {
				do {
					let response = try Settings.v3Decoder.decode(TwitarrV3FezData.self, from: data)
					self.ingestSeamailThreads(from: [response])
					self.recentLoads.removeValue(forKey: thread.id)
				}
				catch {
					NetworkLog.error("Failure parsing Seamails.", ["Error" : error, "url" : request.url as Any])
				} 
			}
			
			done()
		}
	}
		
	func ingestSeamailThreads(from threads: [TwitarrV3FezData]) {
		LocalCoreData.shared.performNetworkParsing { context in
			context.pushOpErrorExplanation("Failed to add new Seamails.")
			
			// Update all the users in all the theads.
			let allParticipants = threads.compactMap { $0.members?.participants }.flatMap { $0 }
			UserManager.shared.update(users: allParticipants, inContext: context)

			// Fetch all the threads from CD
			let allThreadIDs = threads.map { $0.fezID }
			let request = self.coreData.persistentContainer.managedObjectModel.fetchRequestFromTemplate(withName: "SeamailThreadsWithIDs", 
					substitutionVariables: [ "ids" : allThreadIDs ]) as! NSFetchRequest<SeamailThread>
			let cdThreads = try request.execute()
			let cdThreadsDict = Dictionary(cdThreads.map { ($0.id, $0) }, uniquingKeysWith: { (first,_) in first })

			// Tell each CoreData thread to update itself with the new info in the v2 threads
			for mailThread in threads {
				let cdThread = cdThreadsDict[mailThread.fezID] ?? SeamailThread(context: context)
				try cdThread.buildFromV3(context: context, v3Object: mailThread)
			}
			
			// Update our marker for when we last retrieved seamails for this user.
//			if lastChecked > 0, let currentUser = CurrentUser.shared.getLoggedInUser(in: context) {
//				currentUser.lastSeamailCheckTime = lastChecked
//			}
			
			LocalCoreData.shared.setAfterSaveBlock(for: context) { success in 
				self.updateNotifications(context: context)
			}
		}
	}
	
	func ingestSeamailThread(from thread: TwitarrV3FezData, inContext context: NSManagedObjectContext) throws -> SeamailThread {
		// Update all the users in all the theads.
		let allParticipants = thread.members?.participants ?? []
		UserManager.shared.update(users: allParticipants, inContext: context)

		// Fetch all the threads from CD
		let request = NSFetchRequest<SeamailThread>(entityName: "SeamailThread")
		request.predicate = NSPredicate(format: "id == %@", thread.fezID as CVarArg)
		request.fetchLimit = 1
		let cdThreads = try request.execute()
		let cdThread = cdThreads.first ?? SeamailThread(context: context)
		try cdThread.buildFromV3(context: context, v3Object: thread)

		LocalCoreData.shared.setAfterSaveBlock(for: context) { success in 
			self.updateNotifications(context: context)
		}
		return cdThread
	}
	
	func ingestSeamailPost(from post: TwitarrV3FezPostData, toThread: SeamailThread, inContext context: NSManagedObjectContext) throws {
		UserManager.shared.update(users: [post.author], inContext: context)

		let request = NSFetchRequest<SeamailMessage>(entityName: "SeamailMessage")
		request.predicate = NSPredicate(format: "id == %d", post.postID)
		request.fetchLimit = 1
		let cdPosts = try request.execute()
		let cdPost = cdPosts.first ?? SeamailMessage(context: context)
		cdPost.buildFromV3(context: context, v3Object: post, newThread: toThread)
	}
	
	// NOTE: At the time updateNotifications is called on a background thread, ingestSeamailThreads will have been called
	// with data from an /api/v2/alerts call. This response data does not contain the messages in Seamail threads,
	// just the counts.
	func updateNotifications(context: NSManagedObjectContext) {
		print ("updateNotifications")
		guard globalAppIsInBackground else { return }
		guard let currentUser = CurrentUser.shared.getLoggedInUser(in: context) else { return }
		
		// If the number of conversations with new messages hasn't changed, exit.
		let numNewConvos = currentUser.seamailParticipant.count - currentUser.upToDateSeamailThreads.count
//		guard Settings.shared.seamailNotificationBadgeCount != numNewConvos else { return }

		let content = UNMutableNotificationContent()
		content.title = "New Seamail Messages"
		content.body = "\(numNewConvos) seamail conversations have new messages."
		content.userInfo = ["Seamail" : 0]
		if numNewConvos == 1 {
			let newConvoSet = currentUser.seamailParticipant.subtracting(currentUser.upToDateSeamailThreads)
			if let newConvo = newConvoSet.first {
				content.userInfo = ["Seamail" : newConvo.id]
				if newConvo.participants.count == 2,
						let otherUser = newConvo.participants.first(where: { $0.username != currentUser.username }) {
					let displayName = otherUser.displayName.isEmpty ? otherUser.username : otherUser.displayName
					content.body = "1 New seamail message from \(displayName)"

					// For this to work we'd need to call loadSeamailThread to get the messages.
//					if let lastMessage = newConvo.messages.max(by: { $0.timestamp < $1.timestamp }),
//							lastMessage.author.username == otherUser.username {
//						content.body = lastMessage.text
//					}
					
					let debugmeh = newConvo.messages.map { "str: \($0.text) \n" }
					print(debugmeh)
				}
			}
		} 
		
		// Remove prev notification
		let notificationCenter = UNUserNotificationCenter.current()
		let currentNotification = Settings.shared.seamailNotificationUUID 
		if !currentNotification.isEmpty {
			notificationCenter.removePendingNotificationRequests(withIdentifiers: [currentNotification])
		}
				
		let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
		let uuidString = UUID().uuidString
		let request = UNNotificationRequest(identifier: uuidString, content: content, trigger: trigger)

		// Schedule the request with the system.
		notificationCenter.add(request) { (error) in
			if error != nil {
				RefreshLog.error("Couldn't create local notification for Seamail.", ["error": error as Any])
			}
			else {
				Settings.shared.seamailNotificationUUID = uuidString
				Settings.shared.seamailNotificationBadgeCount = numNewConvos
			}
		}
	}
	
	func markNotificationCompleted(_ eventID: String) {
		Settings.shared.seamailNotificationUUID = ""
		Settings.shared.seamailNotificationBadgeCount = 0
	}
	
// MARK: Actions
	
	// Creates a pending POST operation to create a new Seamail thread
	func queueNewSeamailThreadOp(existingOp: PostOpSeamailThread?, subject: String, message: String, 
			recipients: Set<PossibleKrakenUser>, makeOpen: Bool, done: @escaping (PostOpSeamailThread?) -> Void) {
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
			newThread.makeOpen = makeOpen
			
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
						
			newThread.operationState = .readyToSend
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
				messageOp.operationState = .readyToSend
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
	
	// Does NOT post an op--user must be in network range. Reasoning is that adding users to LFGs is time-dependent, and 
	// unlike posting while ashore, adding a user to a LFG hours later is gonna cause issues (i.e. the LFG fills up in the interim
	// and the user doesn't understand how they got waitlisted).
	func addUserToChat(user: KrakenUser, thread: SeamailThread) {
		// POST /api/v3/fez/ID/user/ID/add. The response is an updated FezData. So, mark this as a recent load but always perform it.
		recentLoads[thread.id] = Date()
		var request = NetworkGovernor.buildTwittarRequest(withPath:"/api/v3/fez/\(thread.id)/user/\(user.userID)/add")
		request.httpMethod = "POST"
		NetworkGovernor.addUserCredential(to: &request)
		NetworkGovernor.shared.queue(request) { (package: NetworkResponse) in
			if let error = NetworkGovernor.shared.parseServerError(package) {
				self.lastError = error
			}
			else if let data = package.data {
				do {
					let response = try Settings.v3Decoder.decode(TwitarrV3FezData.self, from: data)
					self.ingestSeamailThreads(from: [response])
					self.recentLoads.removeValue(forKey: thread.id)
				}
				catch {
					NetworkLog.error("Failure parsing network response.", ["Error" : error, "url" : request.url as Any])
				} 
			}
		}
	}
	
	// Does NOT post an op--user must be in network range.
	func removeUserFromChat(user: KrakenUser, thread: SeamailThread) {
		// POST /api/v3/fez/:ID/user/:userID/remove. The response is an updated FezData. So, mark this as a recent load but always perform it.
		recentLoads[thread.id] = Date()
		var request = NetworkGovernor.buildTwittarRequest(withPath:"/api/v3/fez/\(thread.id)/user/\(user.userID)/remove")
		request.httpMethod = "POST"
		NetworkGovernor.addUserCredential(to: &request)
		NetworkGovernor.shared.queue(request) { (package: NetworkResponse) in
			if let error = NetworkGovernor.shared.parseServerError(package) {
				self.lastError = error
			}
			else if let data = package.data {
				do {
					let response = try Settings.v3Decoder.decode(TwitarrV3FezData.self, from: data)
					self.ingestSeamailThreads(from: [response])
					self.recentLoads.removeValue(forKey: thread.id)
				}
				catch {
					NetworkLog.error("Failure parsing network response.", ["Error" : error, "url" : request.url as Any])
				} 
			}
		}
	}
}

// MARK: - V3 Structs

enum TwitarrV3FezType: String, CaseIterable, Codable {
    /// A closed chat. Participants are set at creation and can't be changed. No location, start/end time, or capacity. 
    case closed
	/// An open chat. Participants can be added/removed after creation *and your UI should make this clear*. No location, start/end time, or capacity. 
	case open

    /// Some type of activity.
    case activity
    /// A dining LFG.
    case dining
    /// A gaming LFG.
    case gaming
    /// A general meetup.
    case meeetup
    /// A music-related LFG.
    case music
    /// Some other type of LFG.
    case other
    /// A shore excursion LFG.
    case shore
    
    /// `.label` returns consumer-friendly case names.
    var label: String {
        switch self {
            case .activity: return "Activity"
            case .dining: return "Dining"
            case .gaming: return "Gaming"
            case .meeetup: return "Meetup"
            case .music: return "Music"
            case .shore: return "Shore"
            case .open: return "Open"
            case .closed: return "Private"
            default: return "Other"
        }
    }
}

struct TwitarrV3FezPostData: Codable {
    /// The ID of the fez post.
    var postID: Int
    /// The fez post's author.
    var author: TwitarrV3UserHeader
    /// The text content of the fez post.
    var text: String
    /// The time the post was submitted.
    var timestamp: Date
    /// The image content of the fez post.
    var image: String?
}

struct TwitarrV3FezData: Codable {
    /// The ID of the fez.
    var fezID: UUID
    /// The fez's owner.
    var owner: TwitarrV3UserHeader
    /// The `FezType` .label of the fez.
    var fezType: TwitarrV3FezType
    /// The title of the fez.
    var title: String
    /// A description of the fez.
    var info: String
    /// The starting time of the fez.
    var startTime: Date?
    /// The ending time of the fez.
    var endTime: Date?
    /// The location for the fez.
    var location: String?
    /// How many users are currently members of the fez. Can be larger than maxParticipants; which indicates a waitlist.
	var participantCount: Int
    /// The min number of people for the activity. Set by the host. Fezzes may?? auto-cancel if the minimum participant count isn't met when the fez is scheduled to start.
	var minParticipants: Int
    /// The max number of people for the activity. Set by the host.
	var maxParticipants: Int
	/// TRUE if the fez has been cancelled by the owner. Cancelled fezzes should display CANCELLED so users know not to show up, but cancelled fezzes are not deleted.
	var cancelled: Bool
	/// The most recent of: Creation time for the fez, time of the last post (may not exactly match post time), user add/remove, or update to fezzes' fields. 
	var lastModificationTime: Date
	
    /// FezData.MembersOnlyData returns data only available to participants in a Fez. 
    public struct MembersOnlyData: Codable {
		/// The users participating in the fez.
		var participants: [TwitarrV3UserHeader]
		/// The users on a waiting list for the fez.
		var waitingList: [TwitarrV3UserHeader]
		/// How many posts the user can see in the fez. The count is returned even for calls that don't return the actual posts, but is not returned for 
		/// fezzes where the user is not a member. PostCount does not include posts from blocked/muted users.
		var postCount: Int
		/// How many posts the user has read. If postCount > readCount, there's posts to be read. UI can also use readCount to set the initial view 
		/// to the first unread message.ReadCount does not include posts from blocked/muted users.
		var readCount: Int
		/// Paginates the array in posts--gives the start and limit of the returned posts array relative to all the posts in the thread.
		var paginator: TwitarrV3Paginator?
		/// The FezPosts in the fez discussion. Methods that return arrays of Fezzes, or that add or remove users, do not populate this field (it will be nil).
		var posts: [TwitarrV3FezPostData]?
	}
	var members: MembersOnlyData?
}

public struct TwitarrV3FezListData: Codable {
	/// Pagination into the results set..
	var paginator: TwitarrV3Paginator
    ///The fezzes in the result set.
	var fezzes: [TwitarrV3FezData]
}
