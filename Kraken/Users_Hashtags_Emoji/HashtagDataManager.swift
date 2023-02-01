//
//  HashtagDataManager.swift
//  Kraken
//
//  Created by Chall Fry on 2/22/20.
//  Copyright © 2020 Chall Fry. All rights reserved.
//

import UIKit

@objc(Hashtag) public class Hashtag: KrakenManagedObject {
	@NSManaged public var name: String
}

class HashtagDataManager: NSObject {
	static let shared = HashtagDataManager()
	var lastError: ServerError?
	
	func addHashtags(_ newTags: Set<String>) {
		guard newTags.count > 0 else { return }
	
		LocalCoreData.shared.performNetworkParsing { context in
			context.pushOpErrorExplanation("Failed to parse Hashtags and add to Core Data.")
			
			let fetchRequest = NSFetchRequest<Hashtag>(entityName: "Hashtag")
			fetchRequest.predicate = NSPredicate(format: "name IN %@", newTags)
			fetchRequest.sortDescriptors = [ NSSortDescriptor(key: "name", ascending: true)]
			let cdHashtagObjects = try fetchRequest.execute()
			let cdHashtags = Set(cdHashtagObjects.map { $0.name })
			
			for tag in newTags {
				if !cdHashtags.contains(tag) {
					let newHashtag = Hashtag(context: context)
					newHashtag.name = tag
				}
			}
		}
	}
	
	fileprivate var recentAutocompleteSearches = [String]()
	var autocompleteCallDelayTimer: Timer?
	var autocompleteCallInProgress: Bool = false
	var delayedAutocompleteSearchString: String?

	func clearRecentAutocompleteSearches() {
		recentAutocompleteSearches.removeAll()
	}

	// UI level code can call this repeatedly, for every character the user types. This method waits .5 seconds
	// before calling the server, resets that timer every time this fn is called, checks the search string against
	// recent strings (and won't re-ask the server with a string it's already used), and limits to one call in flight 
	// at a time.
	// Only calls completion routine if we talked to server and (maybe) got new usernames
	func autocompleteHashtagLookup(for partialTag: String) {
		guard partialTag.count >= 3 else { return }

		// 1. Kill any timer that's going
		autocompleteCallDelayTimer?.invalidate()
		
		// 2. Don't call the server with the same string twice (in a short period of time)
		if !recentAutocompleteSearches.contains(partialTag) {
		
			// 3. Only have one call in flight--and one call on deck Newer on-deck calls just replace older ones.
			if autocompleteCallInProgress {
				delayedAutocompleteSearchString = partialTag
			}
			else {
				// 4. Wait half a second, see if the user types more. If not, talk to the server.
				autocompleteCallDelayTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { timer in
					self.loadHashtags(for: partialTag)
				}
			}
		}
	}

	private func loadHashtags(for prefix: String) {
		autocompleteCallInProgress = true
		
		let encodedPrefix = prefix.addingPathComponentPercentEncoding() ?? ""
		let request = NetworkGovernor.buildTwittarRequest(withEscapedPath:"/api/v2/hashtag/ac/\(encodedPrefix)", query: nil)
		NetworkGovernor.shared.queue(request) { (package: NetworkResponse) in
			self.autocompleteCallInProgress = false
			if let error = NetworkGovernor.shared.parseServerError(package) {
				self.lastError = error
			}
			else if let data = package.data {
				self.lastError = nil
			//	print (String(data: data, encoding: .utf8))
				do {
					let response = try Settings.v3Decoder.decode(HashtagAutocompleteResponse.self, from: data)
					self.addHashtags(Set<String>(response.values))

					DispatchQueue.main.async { 
						self.recentAutocompleteSearches.append(prefix)
					}
				}
				catch {
					NetworkLog.error("Failure parsing /api/v2/hashtag/ac/ response.", ["Error" : error, "url" : request.url as Any])
				}
			}

			// If there's a search that we delayed until this search completes, time to run it.
			if let nextStr = self.delayedAutocompleteSearchString {
				self.delayedAutocompleteSearchString = nil
				self.loadHashtags(for: nextStr)
			}
		}
	}
	
}

// GET /api/v2/hashtag/ac/:query
struct HashtagAutocompleteResponse: Codable {
	let values: [String]
}
