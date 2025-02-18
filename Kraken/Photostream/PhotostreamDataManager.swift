//
//  PhotostreamDataManager.swift
//  Kraken
//
//  Created by Chall Fry on 4/20/24.
//  Copyright © 2024 Chall Fry. All rights reserved.
//

import UIKit
import CoreData

@objc(StreamPhoto) public class StreamPhoto: KrakenManagedObject {
    @NSManaged public var id: Int64
    @NSManaged public var imageFilename: String
    @NSManaged public var createdAt: Date					

    @NSManaged public var author: KrakenUser
    @NSManaged public var event: Event?
    @NSManaged public var location: String?
    
	override public func awakeFromInsert() {
		setPrimitiveValue(Date(), forKey: "createdAt")
	}

	func buildFromV3(context: NSManagedObjectContext, v3Object: PhotostreamImageData) throws {
		TestAndUpdate(\.id, v3Object.postID)
		TestAndUpdate(\.imageFilename, v3Object.image)
		TestAndUpdate(\.createdAt, v3Object.createdAt)
		TestAndUpdate(\.location, v3Object.location)
		
		// Set the author
		if self.isInserted || author.userID != v3Object.author.userID {
			let userPool: [UUID : KrakenUser ] = context.userInfo.object(forKey: "Users") as! [UUID : KrakenUser] 
			if let cdAuthor = userPool[v3Object.author.userID] {
				author = cdAuthor
			}
		}

		// Set the event, if any
		if let v3Event = v3Object.event {
			let request = NSFetchRequest<Event>(entityName: "Event")
			request.predicate = NSPredicate(format: "id == %@", argumentArray: [v3Event.eventID])
			let events = try context.fetch(request)
			let event = events.first ?? Event(context: context)
			try event.buildFromV3(context: context, v3Object: v3Event)
			if self.event?.id != event.id {
				self.event = event
			}
		}
		else {
			self.event = nil
		}
	}
}

@objc class PhotostreamDataManager: ServerUpdater, NSFetchedResultsControllerDelegate {
	static let shared = PhotostreamDataManager()
	@objc dynamic var lastError: Error?
	var photostreamLocationData: PhotostreamLocationData = PhotostreamLocationData(events: [], locations: ["On Boat"])
	@objc dynamic var photostreamLocations: [String] = ["On Boat"]
	@objc dynamic var photostreamEventNames: [String] = []
	var lastPhotostreamUpdateTime: Date = Date.distantPast
	var nextPhotoUploadTime: Date = Date.distantPast
	
	private var fetchedData: NSFetchedResultsController<StreamPhoto>

	init() {
		let fetchRequest = NSFetchRequest<StreamPhoto>(entityName: "StreamPhoto")
//		fetchRequest.predicate = NSPredicate(format: "isActive == true")
		fetchRequest.sortDescriptors = [ NSSortDescriptor(key: "id", ascending: false)]
		fetchRequest.fetchBatchSize = 30
		self.fetchedData = NSFetchedResultsController(fetchRequest: fetchRequest, managedObjectContext: LocalCoreData.shared.mainThreadContext, 
				sectionNameKeyPath: nil, cacheName: nil)
		super.init(60)

		DispatchQueue.main.async {
			self.fetchedData.delegate = self
			do {
				try self.fetchedData.performFetch()
			}
			catch {
				CoreDataLog.error("Couldn't fetch Photostream.", [ "error" : error ])
			}
		}
	}
	
	func clearLastError() {
		lastError = nil
	}
	
	// ServerUpdater calls this periodically
	override func updateMethod() {
		updatePhotostream(done: { self.updateComplete(success: true) })
	}
	
	func updatePhotostream(done: (() -> Void)? = nil) {
		if ValidSections.shared.disabledSections.contains(.photostream) {
			done?()
			return
		}
		
		if !CurrentUser.shared.isLoggedIn() {
			done?()
			return
		}
	
		var request = NetworkGovernor.buildTwittarRequest(withPath:"/api/v3/photostream", query: nil)
		NetworkGovernor.addUserCredential(to: &request)
		NetworkGovernor.shared.queue(request) { (package: NetworkResponse) in
			if let error = package.getAnyError() {
				self.lastError = KrakenError("Could not update photostream. \(error.localizedDescription)")
			}
			else if let data = package.data {
				do {
					self.lastError = nil
					let response = try Settings.v3Decoder.decode(PhotostreamListData.self, from: data)
					self.ingestPhotostream(from: response)
				}
				catch {
					NetworkLog.error("Failure parsing Photostream response.", ["Error" : error, "url" : request.url as Any])
				}
			}
			done?()
		}
	}
	
	// Unlike other ingestors, here we delete photostream photos once they've aged out (currently: not in the most recent 30 photos)
	// Photostream photos are meant to be ephemeral.
	func ingestPhotostream(from response: PhotostreamListData) {
		LocalCoreData.shared.performNetworkParsing { context in
			context.pushOpErrorExplanation("Failure adding photostream photos to Core Data.")
			
			// This populates "Users" in our context's userInfo to be a dict of [username : KrakenUser]
			let authors = response.photos.map { $0.author }
			UserManager.shared.update(users: authors, inContext: context)
			
			// Fetch Core Data photos
			let request = NSFetchRequest<StreamPhoto>(entityName: "StreamPhoto")
			let cdPhotos = try request.execute()
			
			// Delete photos not in response
			let deletePhotoIDs = Set(cdPhotos.map { $0.id }).subtracting(response.photos.map { Int64($0.postID) })
			deletePhotoIDs.forEach { photoID in
				if let deletePhoto = cdPhotos.first(where: { $0.id == photoID }) {
					ImageManager.shared.invalidateImage(withKey: deletePhoto.imageFilename)
					context.delete(deletePhoto)
				}
			}
			
			// Add/update
			try response.photos.forEach { v3Object in
				let cdPhoto = cdPhotos.first { $0.id == v3Object.postID } ?? StreamPhoto(context: context)
				try cdPhoto.buildFromV3(context: context, v3Object: v3Object)
			}
		}
	}
	
	// Unlike most other post methods, StreamPhotos may only be posted immediately, and don't use PostOperations.
	func postPhotoToStream(photo: Data, createdAt: Date, locationName: String, done: @escaping (Error?) -> ()) {
		let eventID = photostreamLocationData.events.first(where: { $0.title == locationName })?.eventID
		let locName = photostreamLocationData.locations.first(where: { $0 == locationName })
		let postStruct = PhotostreamUploadData(image: photo, createdAt: createdAt, eventID: eventID, locationName: locName)
		let httpContentData = try! Settings.v3Encoder.encode(postStruct)
		var request = NetworkGovernor.buildTwittarRequest(withPath: "/api/v3/photostream/upload", query: nil)				
		request.httpBody = httpContentData
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		NetworkGovernor.addUserCredential(to: &request)
		request.httpMethod = "POST"
 		
		NetworkGovernor.shared.queue(request) { (package: NetworkResponse) in
			if let _ = package.networkError {
				self.lastError = KrakenError("Couldn't contact server--image upload failed.")
			}
			else if let error = package.serverError {
				self.lastError = KrakenError("Image upload failed. \(error.getCompleteError())")
			}
			else {
				if let delayString = package.response?.value(forHTTPHeaderField: "Retry-After"), let delaySeconds = TimeInterval(delayString)  {
					self.nextPhotoUploadTime = Date() + delaySeconds
				}
				else {
					self.nextPhotoUploadTime = Date() + 300.0
				}
			}
			DispatchQueue.main.async {
				done(self.lastError)
			}
		}
	}
	
	func getPhotostreamLocations() {
		if lastPhotostreamUpdateTime > Date() - 60 {
			return
		}
		var request = NetworkGovernor.buildTwittarRequest(withPath:"/api/v3/photostream/placenames", query: nil)
		NetworkGovernor.addUserCredential(to: &request)
		NetworkGovernor.shared.queue(request) { (package: NetworkResponse) in
			if let _ = package.networkError {
				self.lastError = KrakenError("Couldn't contact server. Image upload may be unavailable.")
			}
			else if let error = package.serverError {
				self.lastError = KrakenError(
						"Server returned a \(error.httpStatus == nil ? String(error.httpStatus!) : "error") result. Image upload may be unavailable.")
			}
			else if let data = package.data {
				do {
					self.lastError = nil
					let response = try Settings.v3Decoder.decode(PhotostreamLocationData.self, from: data)
					self.photostreamLocationData = response
					self.photostreamEventNames = response.events.map { $0.title }
					self.photostreamLocations = response.locations
					self.lastPhotostreamUpdateTime = Date()
				}
				catch {
					NetworkLog.error("Failure parsing Announcements response.", ["Error" : error, "url" : request.url as Any])
				}
			}
		}
	}
}

/// Returns info about a single Photo from the Photostream.
///
/// Returned by: `GET /api/v3/photostream`
struct PhotostreamImageData: Codable {
	/// The ID of the photostream record (NOT the id of the image)..
	var postID: Int64
	/// The time the image was taken--not necessarily the time the image was uploaded..
	var createdAt: Date
	/// The post's author.
	var author: TwitarrV3UserHeader
	/// The filename of the image.
	var image: String
	/// The schedule event this image was tagged with, if any. Stream photos will be tagged with either an event or a location.
	var event: TwitarrV3EventData?
	/// The boat location this image was tagged with, if any. Value will be a raw string from  `PhotoStreamBoatLocation` or nil.  Stream photos will be tagged with either an event or a location.
	var location: String?
}

struct PhotostreamUploadData: Codable {
	/// The image data.
	var image: Data
	/// The time the image was taken--not necessarily the time the image was uploaded..
	var createdAt: Date
	/// The Schedule Event the photo was taken at, if any. ID must refer to an event that is currently happening--that is, an event that `/api/v3/photostream/placenames` returns.
	/// Either the eventID or locationName field must be non-nil.
	var eventID: UUID?
	/// Where the picture was taken. Valid values come from `/api/v3/photostream/placenames` and are transient. Names include titles of events currently happening..
	var locationName: String?
}

/// Returns paginated data on photos in the photo stream. Non-Mods should only have access to the most recent photos, with no pagination.
///
/// Returned by: `GET /api/v3/photostream`
struct PhotostreamListData : Codable {
	var photos: [PhotostreamImageData]
	var paginator: TwitarrV3Paginator
}

struct PhotostreamLocationData: Codable {
	var events: [TwitarrV3EventData]
	var locations: [String]
}

