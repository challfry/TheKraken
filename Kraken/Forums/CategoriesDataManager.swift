//
//  CategoriesDataManager.swift
//  Kraken
//
//  Created by Chall Fry on 1/31/21.
//  Copyright © 2021 Chall Fry. All rights reserved.
//

import UIKit
import CoreData

@objc(ForumCategory) public class ForumCategory: KrakenManagedObject {
	@NSManaged public var id: UUID
	@NSManaged public var title: String
	@NSManaged public var purpose: String
	@NSManaged public var visibleWhenLoggedOut: Bool
	@NSManaged public var isEventCategory: Bool
	@NSManaged public var sortIndex: Int32
	@NSManaged public var numThreads: Int32
	@NSManaged public var forums: [ForumThread]?

	@NSManaged public var userCatPivots: Set<ForumCategoryPivot>
	
	override public func awakeFromInsert() {
		setPrimitiveValue(UUID(), forKey: "id")
		setPrimitiveValue(0, forKey: "sortIndex")
	}

	// Only set index if no user is logged in
	func buildFromV3(context: NSManagedObjectContext, v3Object: TwitarrV3CategoryData, index: Int32? = nil) {
		TestAndUpdate(\.id, v3Object.categoryID)
		TestAndUpdate(\.title, v3Object.title)
		TestAndUpdate(\.purpose, v3Object.purpose)
		TestAndUpdate(\.numThreads, v3Object.numThreads)
		TestAndUpdate(\.isEventCategory, v3Object.isEventCategory)
		TestAndUpdate(\.visibleWhenLoggedOut, index != nil)
		if let index = index {
			TestAndUpdate(\.sortIndex, index)
		}
	}
}

// This pivot indicates that this user can see this Category.
@objc(ForumCategoryPivot) public class ForumCategoryPivot: KrakenManagedObject {
	@NSManaged public var category: ForumCategory
	@NSManaged public var user: KrakenUser
	@NSManaged public var sortIndex: Int32
	@NSManaged public var isRestricted: Bool			// if true, this user cannot create threads, but can post in existing threads.
	
	func buildFromV3(context: NSManagedObjectContext, v3Object: TwitarrV3CategoryData, category: ForumCategory, user: KrakenUser,  index: Int32) {
		TestAndUpdate(\.user, user)
		TestAndUpdate(\.category, category)
		TestAndUpdate(\.sortIndex, index)
		TestAndUpdate(\.isRestricted, v3Object.isRestricted)
	}
}

@objc class CategoriesDataManager: NSObject {
	static let shared = CategoriesDataManager()
	private let coreData = LocalCoreData.shared

	// Used by UI to show loading cell and error cell.
	@objc dynamic var lastError : ServerError?
	@objc dynamic var isPerformingLoad: Bool = false
	
	func checkRefresh() {
		// Could add a debouncer here, but none yet.
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
				do {
					let response = try Settings.v3Decoder.decode([TwitarrV3CategoryData].self, from: data)
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
			
			// Fetch categories from CD 
			let request = NSFetchRequest<ForumCategory>(entityName: "ForumCategory")
			request.predicate = NSPredicate(value: true)
			let cdCats = try request.execute()
			let cdCatsDict = Dictionary(cdCats.map { ($0.id, $0) }, uniquingKeysWith: { (first,_) in first })

			// Fetch categoryPivots from CD 
			if let user = CurrentUser.shared.getLoggedInUser(in: context) {
				let request = ForumCategoryPivot.fetchRequest()
				request.predicate = NSPredicate(format: "user == %@", user)
				var cdCatPivots = try request.execute() as! [ForumCategoryPivot]

				var index: Int32 = 0
				for v3Category in v3Categories {
					let cdCat = cdCatsDict[v3Category.categoryID] ?? ForumCategory(context: context)
					cdCat.buildFromV3(context: context, v3Object: v3Category)

					let pivot = cdCatPivots.first { $0.category.id == v3Category.categoryID } ?? ForumCategoryPivot(context: context)
					pivot.buildFromV3(context: context, v3Object: v3Category, category: cdCat, user: user, index: index)
					cdCatPivots.removeAll { $0.objectID == pivot.objectID }
					index += 1
				}
				// The pivots left over are no longer viewable to this user.
				for notVisiblePivot in cdCatPivots {
					context.delete(notVisiblePivot)
				}
				
			}
			else {
				var index: Int32 = 0
				for category in v3Categories {
					let cdCat = cdCatsDict[category.categoryID] ?? ForumCategory(context: context)
					cdCat.buildFromV3(context: context, v3Object: category, index: index)
					index += 1
				}
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
	/// if TRUE, this category is for Event Forums, and is prepopulated with forum threads for each Schedule Event.
	var isEventCategory: Bool
    /// The number of threads in this category
    var numThreads: Int32
    ///The threads in the category. Only populated for /categories/ID.
    var forumThreads: [TwitarrV3ForumListData]?
}

