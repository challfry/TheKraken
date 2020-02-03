//
//  GamesDataManager.swift
//  Kraken
//
//  Created by Chall Fry on 1/24/20.
//  Copyright © 2020 Chall Fry. All rights reserved.
//

import UIKit
import Compression


@objc class GamesListGame: NSObject {
	var gameName: String
	var bggGameName: String?
	var gameDescription: String?
	var yearPublished: String?

	var minPlayers: Int?
	var maxPlayers: Int?

	var minPlayingTime: Int?
	var avgPlayingTime: Int?
	var maxPlayingTime: Int?

	var minAge: Int?
	var numRatings: Int?
	var avgRating: Float?
	var complexity: Float?			// BGG calls this 'weight'. 0 to 5
	
	@objc dynamic var isFavorite: Bool
	
	// Why have this object create itself from a near-identical JSON Codable struct? Because having your model and UI
	// tied to a particular struct in a file format can make life *really* painful, that's why. This way, we could 
	// build a v2.0 of the games file format, write one new init method here, and be more or less good to go with an
	// implementation that can use either file format.
	init(from: JsonGamesListGame) {
		gameName = from.gameName
		gameDescription = from.gameDescription
		bggGameName = from.bggGameName
		yearPublished = from.yearPublished
		minPlayers = from.minPlayers
		maxPlayers = from.maxPlayers
		minPlayingTime = from.minPlayingTime
		avgPlayingTime = from.avgPlayingTime
		maxPlayingTime = from.maxPlayingTime
		minAge = from.minAge
		numRatings = from.numRatings
		avgRating = from.avgRating
		complexity = from.complexity
		isFavorite = false
		
		super.init()
	}
}

// This is how we save favorites to Core Data.
@objc(GameListFavorite) public class GameListFavorite: KrakenManagedObject {
    @NSManaged public var gameName: String
}

@objc class GamesDataManager: NSObject {
	static let shared = GamesDataManager()
	private let backgroundQ = DispatchQueue(label:"Game List decompressor")

	enum FileLoadingError: String {
		case findFileError = "Error: Couldn't find compressed Game List file."
		case decodeError   = "Error: Decoding Game List file failed."
	}
	
	var fileLoadError: FileLoadingError?
	@objc dynamic var loadingComplete: Bool = false
	@objc dynamic var loadingStarted: Bool = false
	
	var gamesByName: [String : GamesListGame] = [:]
	var gameTitleArray: [String] = []							// All game titles, sorted alphabetically
	
	func loadGamesFile( done: @escaping ()-> Void) {
		if !loadingStarted {
			loadingStarted = true
			backgroundQ.async {
	//			let startTime = ProcessInfo.processInfo.systemUptime
			
				// Step 1: Get the file contents into memory
				guard let fileUrl = Bundle.main.url(forResource: "JoCoGamesCatalog", withExtension: "lzfse"),
						let encodedFileHandle = try? FileHandle(forReadingFrom: fileUrl) else { 
					self.fileLoadError = .findFileError
					return 
				}
				let encodedSourceData = encodedFileHandle.readDataToEndOfFile()
				
				// Step 2: Use Apple's Compression lib to decode the LZFSE file
				let fileData: Data = encodedSourceData.withUnsafeBytes { (encodedSourceBuffer: UnsafeRawBufferPointer) -> Data in
					let decodedCapacity = 8000000
					let decodedDestinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: decodedCapacity)
					let unsafeBufferPointer = encodedSourceBuffer.bindMemory(to: UInt8.self)
					let encodedSourcePtr = unsafeBufferPointer.baseAddress!
					let decodedCharCount = compression_decode_buffer(decodedDestinationBuffer, decodedCapacity,
							encodedSourcePtr, encodedSourceData.count, nil,  COMPRESSION_LZFSE)
					if decodedCharCount == 0 {
						self.fileLoadError = .decodeError
						return Data()
					}
					
					let rebound = UnsafeRawPointer(decodedDestinationBuffer).bindMemory(to: UInt8.self, capacity: decodedCapacity)
					return Data(bytes: rebound, count: decodedCharCount)
				}
	//			print ("Decode Time: \(ProcessInfo.processInfo.systemUptime - startTime)")
				
				// Step 3: Parse the file, creating local versions of the 'full state' vars.
				var threadGamesByName: [String : GamesListGame] = [:]
				var threadGameTitles: [String] = []
				let gameArray = try! JSONDecoder().decode([JsonGamesListGame].self, from: fileData)
				for game in gameArray {
					threadGamesByName[game.gameName] = GamesListGame(from: game)
					threadGameTitles.append(game.gameName)
				}
				
				// Step 4: Set up favorites
				let context = LocalCoreData.shared.mainThreadContext
				context.performAndWait {
					do {
						let fetchRequest = NSFetchRequest<GameListFavorite>(entityName: "GameListFavorite")
						let cdFavoriteGames = try context.fetch(fetchRequest)
						
						for favoriteGame in cdFavoriteGames {
							if let game = threadGamesByName[favoriteGame.gameName] {
								game.isFavorite = true
							}
						}
					}	
					catch {
						CoreDataLog.error("Couldn't load Favorite Games from Core Data.", ["Error" : error])
					}
				}

				// Step 5: Sort the arrays
				threadGameTitles = threadGameTitles.sorted { $0.caseInsensitiveCompare($1) == .orderedAscending }
	//			print ("Total Time: \(ProcessInfo.processInfo.systemUptime - startTime)")
				
				self.gamesByName = threadGamesByName
				self.gameTitleArray = threadGameTitles
				self.loadingComplete = true
			}
		}
		
		// Serialize the completion closure on the background queue, so it always runs after loading completes.
		// If multiple clients call loadGamesFile() while the load is in progress, all their completions get 
		// queued up after the load block.
		backgroundQ.async {
			DispatchQueue.main.async {
				done()
			}
		}
	}

	func setFavoriteGameStatus(for gameObject: GamesListGame?, to newState: Bool) {
		if let game = gameObject {
			game.isFavorite = newState
			saveFavoriteGames()
		}
	}	
	
	func saveFavoriteGames() {
		let context = LocalCoreData.shared.networkOperationContext
		context.perform {
			do {
				let fetchRequest = NSFetchRequest<GameListFavorite>(entityName: "GameListFavorite")
				let cdFavoriteGames = try context.fetch(fetchRequest)
				for game in cdFavoriteGames {
					context.delete(game)
				}
				let favoriteGames = self.gamesByName.filter { $0.1.isFavorite == true }
				for fav in favoriteGames {
					let newFavGame = GameListFavorite(context: context)
					newFavGame.gameName = fav.key
				}
				try context.save()
			}
			catch {
				CoreDataLog.error("Couldn't save Favorite Karaoke Songs to Core Data.", ["Error" : error])
			}
		}
	}
}
