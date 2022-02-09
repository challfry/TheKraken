//
//  CategoriesDataManager.swift
//  Kraken
//
//  Created by Chall Fry on 1/31/21.
//  Copyright © 2021 Chall Fry. All rights reserved.
//

import UIKit

@objc(ForumCategory) public class ForumCategory: KrakenManagedObject {
	@NSManaged public var id: UUID
	@NSManaged public var title: String
	@NSManaged public var purpose: String
	@NSManaged public var isAdmin: Bool
	@NSManaged public var numThreads: Int32
	@NSManaged public var forums: [ForumThread]?
	
	override public func awakeFromInsert() {
		setPrimitiveValue(UUID(), forKey: "id")
	}

	func buildFromV3(context: NSManagedObjectContext, v3Object: TwitarrV3CategoryData) {
		TestAndUpdate(\.id, v3Object.categoryID)
		TestAndUpdate(\.title, v3Object.title)
		TestAndUpdate(\.purpose, v3Object.purpose)
		TestAndUpdate(\.isAdmin, v3Object.isRestricted)
		TestAndUpdate(\.numThreads, v3Object.numThreads)
	}
}

@objc class CategoriesDataManager: NSObject {
	static let shared = CategoriesDataManager()
	private let coreData = LocalCoreData.shared

	// Used by UI to show loading cell and error cell.
	@objc dynamic var lastError : ServerError?
	@objc dynamic var isPerformingLoad: Bool = false
	
	func checkRefresh() {
		loadForumCategories()
	}
	
	func loadForumCategories() {
		isPerformingLoad = true
		var request = NetworkGovernor.buildTwittarRequest(withPath:"/api/v3/forum/categories", query: nil)
		NetworkGovernor.addUserCredential(to: &request)
		NetworkGovernor.shared.queue(request) { (package: NetworkResponse) in
			if let error = NetworkGovernor.shared.parseServerError(package) {
				self.lastError = error
			}
			else if let data = package.data {
				self.lastError = nil
				let decoder = JSONDecoder()
				do {
					let response = try decoder.decode([TwitarrV3CategoryData].self, from: data)
					self.ingestForumCategories(from: response)
				}
				catch {
					NetworkLog.error("Failure parsing Forums response.", ["Error" : error, "url" : request.url as Any])
				}
			}
			self.isPerformingLoad = false
		}
	}
	
	func ingestForumCategories(from v3Categories: [TwitarrV3CategoryData]) {
		LocalCoreData.shared.performNetworkParsing { context in
			context.pushOpErrorExplanation("Failed to parse Forum categories and add to Core Data.")
			
			// Fetch categories from CD that match the ids in the given categories
			let serverCats = v3Categories.map { $0.categoryID }
			let request = NSFetchRequest<ForumCategory>(entityName: "ForumCategory")
			request.predicate = NSPredicate(format: "id IN %@", serverCats)
			let cdCats = try request.execute()
			let cdCatsDict = Dictionary(cdCats.map { ($0.id, $0) }, uniquingKeysWith: { (first,_) in first })

			for category in v3Categories {
				let cdCat = cdCatsDict[category.categoryID] ?? ForumCategory(context: context)
				cdCat.buildFromV3(context: context, v3Object: category)
			}
		}
	}
}

// MARK: - V3 API Decoding

// GET /api/v3/forum/categories
struct TwitarrV3CategoryData: Codable {
    /// The ID of the category.
    var categoryID: UUID
    /// The title of the category.
    var title: String
    /// The purpose string for the category.
    var purpose: String
    /// If TRUE, the user cannot create/modify threads in this forum. Should be sorted to top of category list.
    var isRestricted: Bool
    /// The number of threads in this category
    var numThreads: Int32
    ///The threads in the category. Only populated for /categories/ID.
    var forumThreads: [TwitarrV3ForumListData]?
}
