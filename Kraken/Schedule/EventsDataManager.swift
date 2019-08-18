//
//  EventsDataManager.swift
//  Kraken
//
//  Created by Chall Fry on 8/12/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit

@objc(Event) public class Event: KrakenManagedObject {
    @NSManaged public var id: String
    @NSManaged public var title: String
	@NSManaged public var eventDescription: String?
	@NSManaged public var location: String?
    @NSManaged public var official: Bool
    
    @NSManaged public var startTimestamp: Int64
    @NSManaged public var endTimestamp: Int64
    public var startTime: Date?
    public var endTime: Date?
    
    @NSManaged public var followedBy: Set<KrakenUser>
    
	public override func awakeFromFetch() {
		super.awakeFromFetch()

		// Update derived properties
		startTime = Date(timeIntervalSince1970: Double(startTimestamp) / 1000.0)
		endTime = Date(timeIntervalSince1970: Double(endTimestamp) / 1000.0)
	}

	func buildFromV2(context: NSManagedObjectContext, v2Object: TwitarrV2Event) {
		TestAndUpdate(\.id, v2Object.id)
		TestAndUpdate(\.title, v2Object.title)
		TestAndUpdate(\.eventDescription, v2Object.eventDescription?.decodeHTMLEntities())
		TestAndUpdate(\.location, v2Object.location)
		TestAndUpdate(\.official, v2Object.official ?? false)
		TestAndUpdate(\.startTimestamp, v2Object.startTime)
		TestAndUpdate(\.endTimestamp, v2Object.endTime)
		
		startTime = Date(timeIntervalSince1970: Double(v2Object.startTime) / 1000.0)
		endTime = Date(timeIntervalSince1970: Double(v2Object.endTime) / 1000.0)
		
		if let currentUser = CurrentUser.shared.getLoggedInUser(in: context) {
			if followedBy.contains(currentUser) {
				if !v2Object.following {
					followedBy.remove(currentUser)
				}
			}
			else {
				if v2Object.following {
					followedBy.insert(currentUser)
				}
			}
		}
	}
}

class EventsDataManager: NSObject {
	static let shared = EventsDataManager()
	private let coreData = LocalCoreData.shared
	var fetchedData: NSFetchedResultsController<Event>
	var viewDelegates: [NSObject & NSFetchedResultsControllerDelegate] = []
	
	// TRUE when we've got a network call running to update the stream, or the current filter.
	@objc dynamic var networkUpdateActive: Bool = false  

	override init() {
		let fetchRequest = NSFetchRequest<Event>(entityName: "Event")
		fetchRequest.sortDescriptors = [ NSSortDescriptor(key: "startTimestamp", ascending: true),
				 NSSortDescriptor(key: "endTimestamp", ascending: true),
				 NSSortDescriptor(key: "title", ascending: true)]
		fetchRequest.fetchBatchSize	= 50
		fetchedData = NSFetchedResultsController(fetchRequest: fetchRequest, managedObjectContext: coreData.mainThreadContext, 
				sectionNameKeyPath: nil, cacheName: nil)
		super.init()
		fetchedData.delegate = self
		do {
			try fetchedData.performFetch()
		}
		catch {
			CoreDataLog.error("Couldn't fetch Twitarr posts.", [ "error" : error ])
		}
	}
	
	func loadEvents() {
		let request = NetworkGovernor.buildTwittarV2Request(withPath:"/api/v2/event", query: nil)
		networkUpdateActive = true
		NetworkGovernor.shared.queue(request) { (data: Data?, response: URLResponse?) in
			self.networkUpdateActive = false
			if let response = response as? HTTPURLResponse, response.statusCode < 300,
					let data = data {
//				print (String(decoding:data!, as: UTF8.self))
				let decoder = JSONDecoder()
				do {
					let eventResponse = try decoder.decode(TwitarrV2EventResponse.self, from: data)
					self.parseEvents(eventResponse.events, isFullList: true)
				} catch 
				{
					NetworkLog.error("Failure parsing Schedule events.", ["Error" : error, "URL" : request.url as Any])
				} 
			}
		}
	}
	
	// pass TRUE for isFullList if events is a comprehensive list of all events; this causes deletion of existing events
	// not in the new list. Otherwise it only adds/updates events.
	func parseEvents(_ events: [TwitarrV2Event], isFullList: Bool) {
		let context = coreData.networkOperationContext
		context.perform {
			do {
				if isFullList {
					// Delete events not in the new event list
					let newEventIds = Set(events.map( { $0.id } ))
					self.fetchedData.fetchedObjects?.forEach { event in
						if !newEventIds.contains(event.id) {
							context.delete(event)
						}
					}
				}
			
				// Add/update
				for event in events {
					let coreDataEvent = self.fetchedData.fetchedObjects?.first(where: { $0.id == event.id }) ?? Event(context: context)
					coreDataEvent.buildFromV2(context: context, v2Object: event)
				}
				
				try context.save()
			}
			catch {
				CoreDataLog.error("Failure adding Schedule events to CD.", ["Error" : error])
			}
		}
	}
	
	func addDelegate(_ newDelegate: NSObject & NSFetchedResultsControllerDelegate) {
		if !viewDelegates.contains(where: { $0 === newDelegate } ) {
			viewDelegates.insert(newDelegate, at: 0)
		}
	}
	
	func removeDelegate(_ oldDelegate: NSObject & NSFetchedResultsControllerDelegate) {
		viewDelegates.removeAll(where: { $0 === oldDelegate } )
	}
}

extension EventsDataManager : NSFetchedResultsControllerDelegate {
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


struct TwitarrV2Event: Codable {
	let id: String
	let title: String
	let eventDescription: String?
	let location: String?
	let official: Bool?

	let startTime: Int64
	let endTime: Int64
	
	let following: Bool

	enum CodingKeys: String, CodingKey {
		case id
		case title
		case eventDescription = "description"
		case location
		case official
		case startTime = "start_time"
		case endTime = "end_time"
		case following
	}
}

// GET /api/v2/event
struct TwitarrV2EventResponse : Codable {
	let status: String
	let total_count: Int
	let events: [TwitarrV2Event]
}
