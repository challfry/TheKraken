//
//  DailyThemeUpdater.swift
//  Kraken
//
//  Created by Chall Fry on 2/18/22.
//  Copyright © 2022 Chall Fry. All rights reserved.
//

import Foundation
import CoreData

@objc(DailyTheme) public class DailyTheme: KrakenManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var title: String
    @NSManaged public var info: String
    @NSManaged public var image: String?
    @NSManaged public var cruiseDay: Int32

	override public func awakeFromInsert() {
		setPrimitiveValue(UUID(), forKey: "id")
		super.awakeFromInsert()
	}
	
	func buildFromV3(context: NSManagedObjectContext, dailyThemeData: TwitarrV3DailyThemeData) {
		TestAndUpdate(\.id, dailyThemeData.themeID)
		TestAndUpdate(\.title, dailyThemeData.title)
		TestAndUpdate(\.info, dailyThemeData.info)
		TestAndUpdate(\.image, dailyThemeData.image)
		TestAndUpdate(\.cruiseDay, dailyThemeData.cruiseDay)
	}
}

class DailyThemeUpdater: ServerUpdater {
	static let shared = DailyThemeUpdater()
	
	var lastError: ServerError?
	
	init() {
		// Update every hour.
		super.init(60 * 60)
		refreshOnLogin = true
	}
	
	override func updateMethod() {
		callDailyThemeEndpoint()
	}
		
	func callDailyThemeEndpoint() {
		var request = NetworkGovernor.buildTwittarRequest(withPath:"/api/v3/notification/dailythemes")
		NetworkGovernor.addUserCredential(to: &request)
		NetworkGovernor.shared.queue(request) { (package: NetworkResponse) in
			if let error = NetworkGovernor.shared.parseServerError(package) {
				self.lastError = error
				self.updateComplete(success: false)
			}
			else if let data = package.data {
				do {
					self.lastError = nil
					let response = try JSONDecoder().decode([TwitarrV3DailyThemeData].self, from: data)
					self.parseDailyThemeResponse(response)
					self.updateComplete(success: true)
				}
				catch {
					NetworkLog.error("Failure parsing Alerts response.", ["Error" : error, "url" : request.url as Any])
					self.updateComplete(success: false)
				}
			}
			else {
				// Network error
				self.updateComplete(success: false)
			}
		}
	}
	
	func parseDailyThemeResponse(_ response: [TwitarrV3DailyThemeData]) {
		LocalCoreData.shared.performNetworkParsing { context in
			let request = NSFetchRequest<DailyTheme>(entityName: "DailyTheme")
			request.predicate = NSPredicate(value: true)
			let cdResults = try context.fetch(request)
			response.forEach { dailyThemeData in
				let cdDailyTheme = cdResults.first(where: { $0.id == dailyThemeData.themeID }) ?? DailyTheme(context: context)
				cdDailyTheme.buildFromV3(context: context, dailyThemeData: dailyThemeData)
			}
			cdResults.filter( { cdDailyTheme in !response.contains(where: { $0.themeID == cdDailyTheme.id }) }).forEach { toDelete in
				context.delete(toDelete)
			}
		}
	}
}

// MARK: - V3 API Decoding

public struct TwitarrV3DailyThemeData: Codable {
    /// The theme's ID Probably only useful for admins in order to edit or delete themes.
    var themeID: UUID
	/// A short string describing the day's theme. e.g. "Cosplay Day", or "Pajamas Day", or "Science Day".
	var title: String
	/// A longer string describing the theme, possibly with a call to action for users to participate.
	var info: String
	/// An image that relates to the theme.
	var image: String?
	/// Day of cruise, counted from `Settings.shared.cruiseStartDate`. 0 is embarkation day. Values could be negative (e.g. Day -1 is "Anticipation Day")
	var cruiseDay: Int32				
}
