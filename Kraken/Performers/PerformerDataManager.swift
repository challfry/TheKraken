//
//  PerformersDataManager.swift
//  Kraken
//
//  Created by Chall Fry on 8/30/24.
//  Copyright © 2024 Chall Fry. All rights reserved.
//

import Foundation
import UIKit
import CoreData

@objc(Performer) public class Performer: KrakenManagedObject {
	@NSManaged public var id: UUID
    @NSManaged public var name: String
    @NSManaged public var imageFilename: String?
	@NSManaged public var isOfficialPerformer: Bool
	@NSManaged public var sortOrder: String

	@NSManaged public var pronouns: String?
	@NSManaged public var bio: String?
	@NSManaged public var organization: String?
	@NSManaged public var title: String?
	@NSManaged public var website: String?
	@NSManaged public var facebookURL: String?
	@NSManaged public var xURL: String?
	@NSManaged public var instagramURL: String?
	@NSManaged public var youtubeURL: String?
	@NSManaged public var yearsAttended: String?
	@NSManaged public var lastFullFetchTime: Date

	@NSManaged public var events: Set<Event>
	
	public override func awakeFromInsert() {
		super.awakeFromInsert()
		id = UUID()
		lastFullFetchTime = Date.distantPast
	}
	
	func buildFromV3Header(context: NSManagedObjectContext, v3Object: TwitarrV3PerformerHeaderData) {
		let filename = v3Object.photo == "" ? nil: v3Object.photo
		TestAndUpdate(\.id, v3Object.id)
		TestAndUpdate(\.imageFilename, filename)
		TestAndUpdate(\.name, v3Object.name)
		TestAndUpdate(\.isOfficialPerformer, v3Object.isOfficialPerformer)
		
		var sort = v3Object.name
		if let lastName = v3Object.name.split(separator: " ").last {
			sort = String(lastName).uppercased()
		}
		TestAndUpdate(\.sortOrder, sort.uppercased())
	}
	
	func buildFromV3(context: NSManagedObjectContext, v3Object: TwitarrV3PerformerData) throws {
		buildFromV3Header(context: context, v3Object: v3Object.header)
		TestAndUpdate(\.pronouns, v3Object.pronouns)
		TestAndUpdate(\.bio, v3Object.bio)
		TestAndUpdate(\.organization, v3Object.organization)
		TestAndUpdate(\.title, v3Object.title)
		TestAndUpdate(\.website, v3Object.website)
		TestAndUpdate(\.facebookURL, v3Object.facebookURL)
		TestAndUpdate(\.xURL, v3Object.xURL)
		TestAndUpdate(\.instagramURL, v3Object.instagramURL)
		TestAndUpdate(\.youtubeURL, v3Object.youtubeURL)
		let yearsString = v3Object.yearsAttended.map { String($0) }.joined(separator: ", ")
		TestAndUpdate(\.yearsAttended, yearsString)
				
		lastFullFetchTime = Date()
	}
}

@objc class PerformerDataManager: NSObject, NSFetchedResultsControllerDelegate {
	static let shared = PerformerDataManager()
	@objc dynamic var lastError: Error?

	enum PerformerArrayContents {
		case somePerformers				// Not a comprehensive list; don't delete performers not in array
		case allOfficialPerformers		// Array is comprehensive list of all offical perfomers
		case allShadowPerformers		// Array is comprehensive list of all shadow performers 
	}
	
	func updatePerformers(official: Bool) {
		if ValidSections.shared.disabledSections.contains(.performers) {
			return
		}
		let query = URLQueryItem(name: "limit", value: "200")
		let path = official ? "/api/v3/performer/official" : "/api/v3/performer/shadow"
		var request = NetworkGovernor.buildTwittarRequest(withPath: path, query: [query])
		NetworkGovernor.addUserCredential(to: &request)
		NetworkGovernor.shared.queue(request) { (package: NetworkResponse) in
			if let error = package.getAnyError() {
				self.lastError = KrakenError("Could not update performer list. \(error.localizedDescription)")
			}
			else if let data = package.data {
				do {
					self.lastError = nil
					let response = try Settings.v3Decoder.decode(TwitarrV3PerformerResponseData.self, from: data)
					var arrayContents: PerformerArrayContents
					switch (response.paginator.total <= response.paginator.limit, official) {
						case (false, _): arrayContents = .somePerformers
						case (true, false): arrayContents = .allShadowPerformers
						case (true, true): arrayContents = .allOfficialPerformers
					}
					self.ingestPerformers(from: response.performers, arrayContents: arrayContents)
				}
				catch {
					NetworkLog.error("Failure parsing Performers response.", ["Error" : error, "url" : request.url as Any])
				}
			}
		}
	}
	
	func ingestPerformers(from performers: [TwitarrV3PerformerHeaderData], arrayContents: PerformerArrayContents) {
		LocalCoreData.shared.performNetworkParsing { context in
			context.pushOpErrorExplanation("Failure adding performer data.")
			
			// Fetch Core Data performers
			let request = NSFetchRequest<Performer>(entityName: "Performer")
			switch arrayContents {
				case .somePerformers: request.predicate = NSPredicate(format: "id IN %@", performers.map { $0.id })
				case .allOfficialPerformers: request.predicate = NSPredicate(format: "isOfficialPerformer == true")
				case .allShadowPerformers: request.predicate = NSPredicate(format: "isOfficialPerformer == false")
			}
			let cdPerformers = try request.execute()
			
			// Delete performers not in response if we got all of them
			if [.allOfficialPerformers, .allShadowPerformers].contains(arrayContents) {
				let deletePerformers = Set(cdPerformers.map { $0.id }).subtracting(performers.map { $0.id })
				deletePerformers.forEach { performerID in
					if let deletePerformer = cdPerformers.first(where: { $0.id == performerID }) {
						if let image = deletePerformer.imageFilename {
							ImageManager.shared.invalidateImage(withKey: image)
						}
						context.delete(deletePerformer)
					}
				}
			}
			
			// Add/update
			performers.forEach { v3Object in
				let cdPerformer = cdPerformers.first { $0.id == v3Object.id } ?? Performer(context: context)
				cdPerformer.buildFromV3Header(context: context, v3Object: v3Object)
			}
		}
	}
	
	func updatePerformer(id: UUID) -> Performer? {
		if ValidSections.shared.disabledSections.contains(.performers) {
			return nil
		}
		// Fetch Core Data performer, if one exists
		let fetchRequest = NSFetchRequest<Performer>(entityName: "Performer")
		fetchRequest.predicate = NSPredicate(format: "id == %@", id as CVarArg)
		let performers = try! LocalCoreData.shared.mainThreadContext.fetch(fetchRequest)
		let cdPerformer = performers.first
		if let foundPerformer = cdPerformer, foundPerformer.lastFullFetchTime > Date() - 3600.0 {
			// Only update a performer once per hour; they shouldn't change much
			return foundPerformer
		}	

		let path = "/api/v3/performer/\(id)"
		var request = NetworkGovernor.buildTwittarRequest(withPath: path, query: nil)
		NetworkGovernor.addUserCredential(to: &request)
		NetworkGovernor.shared.queue(request) { (package: NetworkResponse) in
			if let error = package.getAnyError() {
				self.lastError = KrakenError("Could not update performer. \(error.localizedDescription)")
				// It's possible we should delete the performer here if we get a 404.
			}
			else if let data = package.data {
				do {
					self.lastError = nil
					let response = try Settings.v3Decoder.decode(TwitarrV3PerformerData.self, from: data)
					EventsDataManager.shared.parseV3Events(response.events, isFullList: false)
					self.ingestPerformer(from: response)
				}
				catch {
					NetworkLog.error("Failure parsing Performers response.", ["Error" : error, "url" : request.url as Any])
				}
			}
		}
		return cdPerformer
	}
	
	func ingestPerformer(from response: TwitarrV3PerformerData) {
		LocalCoreData.shared.performNetworkParsing { context in
			context.pushOpErrorExplanation("Failure adding performer data.")
			
			// Fetch Core Data performer, if one exists
			let fetch = NSFetchRequest<Performer>(entityName: "Performer")
			fetch.predicate = NSPredicate(format: "id == %@", response.header.id as CVarArg)
			let cdPerformer = try fetch.execute().first ?? Performer(context: context)

			// Add/update
			try cdPerformer.buildFromV3(context: context, v3Object: response)
		}
	}
	
}

/// Returns info about a single Performer. This header information is similar to the UserHeader structure, containing just enough
/// info to build a title card for a performer. 
/// 
/// This structure is also used to break the recusion cycle where a PerformerData contains a list of Events, and the 
/// Events contain lists of the Performers that will be there. In this case, the Event has an array of PerformerHeaderData instead of PerformerData.
///
/// Incorporated into `PerformerData`
/// Incorporated into `EventData`
public struct TwitarrV3PerformerHeaderData: Content, Hashable {
	/// Database ID of hte performer. Used to get full performer info via `/api/v3/performer/<id>`
	var id: UUID
	/// Name of the performer
	var name: String
	/// Photo ID, accessible through `/api/v3/image/[full|thumb]/<photo>` methods in the `ImageController`.
	var photo: String?
	/// TRUE if the performer is on JoCo's list of featured guests. FALSE if this is a shadow event organizer.
	var isOfficialPerformer: Bool
}

/// Wraps up a list of performers with pagination info.
/// 
/// Returned by:`GET /api/v3/performer/official`
/// Returned by:`GET /api/v3/performer/shadow`
public struct TwitarrV3PerformerResponseData: Content {
	/// The requested performers
	var performers: [TwitarrV3PerformerHeaderData]
	/// Pagination info.
	var paginator: TwitarrV3Paginator
}

/// Returns info about a single perfomer. Most fields are optional, and the array fields may be empty, although they shouldn't be under normal conditions.
/// 
/// Returned by: `GET /api/v3/performer/self`
/// Returned by: `GET /api/v3/performer/:performer_id`
public struct TwitarrV3PerformerData: Content {
	/// ID, name, photo -- used to create a title card
	var header: TwitarrV3PerformerHeaderData
	/// For Shadow Event Organizers, the Performer links to their User, but don't use the user's pronoun field when referring to them as a Performer.
	var pronouns: String?
	/// Bio may contain Markdown.
	var bio: String?
	/// Bandname, NGO, university, Podcast name, etc. Should only be filled if the org is relevant to the performer's event.
	var organization: String?
	/// Should only be non-nil if it's a title that's relevant to the performer's event. Hopefully won't contain 'Mr./Mrs."
	var title: String?
	/// Should be a fully-qualified URL.
	var website: String?
	/// Should be a fully-qualified URL.
	var facebookURL: String?
	/// Should be a fully-qualified URL.
	var xURL: String?
	/// Should be a fully-qualified URL.
	var instagramURL: String?
	/// Should be a fully-qualified URL.
	var youtubeURL: String?
	/// Full 4-digit years, ascending order-- like this: [2011, 2012, 2022]
	var yearsAttended: [Int]
	/// The events this performer is going to be performing at.
	var events: [TwitarrV3EventData]
	/// The user who  created this Performer. Only applies to Shadow Event organizers, and is only returned if the requester is a Moderator or higher.
	/// Although we track the User who created a Performer model for their shadow event for moderation purposes, the User behind the Performer 
	/// shouldn't be shown to everyone.
	var user: TwitarrV3UserHeader?
}
