//
//  EmojiDataManager.swift
//  Kraken
//
//  Created by Chall Fry on 2/24/20.
//  Copyright © 2020 Chall Fry. All rights reserved.
//

import Foundation
import CoreData

@objc(Emoji) public class Emoji: KrakenManagedObject {
	@NSManaged public var name: String
	@NSManaged public var lastUseDate: Date
}

class EmojiDataManager: NSObject {
	static let shared = EmojiDataManager()
	var recentEmoji: [String] = []
	
	//
	func gatherEmoji(from postText: String) {
		let emojiInPost: [String] = postText.compactMap { 
			if $0.unicodeScalars.count == 1 {
				if let props = $0.unicodeScalars.first?.properties {
					return props.isEmojiPresentation || props.generalCategory == .otherSymbol ? String($0) : nil
				}
			}
			else if $0.unicodeScalars.count > 1 {
				return $0.unicodeScalars.contains { $0.properties.isJoinControl || $0.properties.isVariationSelector } ?
						String($0) : nil
			}
			return nil
		}
//		let emojiInPost = postText.unicodeScalars.compactMap { $0.properties.isEmojiPresentation ? $0.description : nil }

		let emojiSet = Set(emojiInPost)
		addEmoji(emojiSet)
	}
	
	// 
	func addEmoji(_ newEmojis: Set<String>) {
	
		LocalCoreData.shared.performNetworkParsing { context in
			context.pushOpErrorExplanation("Failed to add Emoji to Core Data.")
			
			let fetchRequest = NSFetchRequest<Emoji>(entityName: "Emoji")
			fetchRequest.predicate = NSPredicate(value: true)
			fetchRequest.sortDescriptors = [ NSSortDescriptor(key: "lastUseDate", ascending: false)]
			let cdEmojiObjects = try fetchRequest.execute()
					
			for newEmoji in newEmojis {
				if !cdEmojiObjects.contains(where: { newEmoji == $0.name }) {
					let newCDEmoji = Emoji(context: context)
					newCDEmoji.name = newEmoji
					newCDEmoji.lastUseDate = Date()
				}
			}
			
			LocalCoreData.shared.setAfterSaveBlock(for: context) { success in
				self.getRecentlyUsedEmoji()
			}
		}
	}
	
	func getRecentlyUsedEmoji() {
		let context = LocalCoreData.shared.mainThreadContext
		context.performAndWait {
			let fetchRequest = NSFetchRequest<Emoji>(entityName: "Emoji")
			fetchRequest.predicate = NSPredicate(value: true)
			fetchRequest.sortDescriptors = [ NSSortDescriptor(key: "lastUseDate", ascending: false)]
			fetchRequest.fetchLimit = 12
			do {
				let cdEmojiObjects = try fetchRequest.execute()
				self.recentEmoji = cdEmojiObjects.map { $0.name }
			}
			catch {
				CoreDataLog.error("Couldn't fetch Emoji.", [ "error" : error ])
			}
		}
	}		
}
