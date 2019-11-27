//
//  KaraokeDataManager.swift
//  Kraken
//
//  Created by Chall Fry on 11/23/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit
import Compression

class KaraokeArtist: NSObject {
	var artistName: String
	var numFavoriteSongs: Int = 0			// Songs are favorited, not artists. This is a rollup for conveniene.
	var allSongs: [KaraokeSong] = []
	var filterSongs: [KaraokeSong] = []

	init(artistName: String) {
		self.artistName = artistName
		numFavoriteSongs = 0
		super.init()
	}
}

class KaraokeSong: NSObject {
	var artistName: String
	var songTitle: String
	var whateverThisModifierIs: String?	// Seriously. The datafile contains a field with a single letter, often "M".
										// M doesn't stand for Mature Lyrics. Modified, perhaps?
	var isFavorite: Bool
	
	init(artistName: String, songTitle: String, whateverThisModifierIs: String?) {
		self.artistName = artistName
		self.songTitle = songTitle
		self.whateverThisModifierIs	= whateverThisModifierIs
		isFavorite = false
		super.init()
	}
}

// This is how we save songs to Core Data.
@objc(KaraokeFavoriteSong) public class KaraokeFavoriteSong: KrakenManagedObject {
    @NSManaged public var artistName: String
    @NSManaged public var songTitle: String
}

// Like most data managers, this is a singleton. Its job is to load the compressed song file into arrays
// of KaraokeSong and KaraokeArtist objects. I don't currently have a plan to have multiple VCs display views on
// this data, but it's a thing that could happen.
class KaraokeDataManager: NSObject {
	static let shared = KaraokeDataManager()
	private let backgroundQ = DispatchQueue(label:"Karaoke Songfile decompressor")

	enum FileLoadingError: String {
		case findFileError = "Error: Couldn't find compressed Karaoke Song file."
		case decodeError   = "Error: Decoding Karaoke Songs file failed."
	}

	var fileLoadError: FileLoadingError?
	var loadingComplete: Bool = false

	// These represent the full state of the song catalog.
	var artists: [String : KaraokeArtist] = [:]
	var artistArray: [String] = []							// All artists, sorted alphabetically
	var songsArray: [KaraokeSong] = []						// All songs, sorted alphabetically
	
	func loadSongFile( done: @escaping ()-> Void) {
		if loadingComplete {
			done()
		}
	
		backgroundQ.async {
//			let startTime = ProcessInfo.processInfo.systemUptime
		
			// Step 1: Get the file contents into memory
			guard let fileUrl = Bundle.main.url(forResource: "JoCoKaraokeSongCatalog", withExtension: "lzfse"),
					let encodedFileHandle = try? FileHandle(forReadingFrom: fileUrl) else { 
				self.fileLoadError = .findFileError
				return 
			}
			
			let encodedSourceData = encodedFileHandle.readDataToEndOfFile()
			
			// Step 2: Use Apple's Compression lib to decode the LZFSE file
			let fileStr: String = encodedSourceData.withUnsafeBytes { (encodedSourceBuffer: UnsafeRawBufferPointer) -> String in
				let decodedCapacity = 8000000
				let decodedDestinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: decodedCapacity)
				let unsafeBufferPointer = encodedSourceBuffer.bindMemory(to: UInt8.self)
				let encodedSourcePtr = unsafeBufferPointer.baseAddress!
				let decodedCharCount = compression_decode_buffer(decodedDestinationBuffer, decodedCapacity,
						encodedSourcePtr, encodedSourceData.count, nil,  COMPRESSION_LZFSE)
				if decodedCharCount == 0 {
					self.fileLoadError = .decodeError
					return ""
				}

				return String(cString: decodedDestinationBuffer)
			}
//			print ("Decode Time: \(ProcessInfo.processInfo.systemUptime - startTime)")
			
			// Step 3: Parse the file, creating local versions of the 'full state' vars.
			var threadSongs: [KaraokeSong] = []
			var threadArtists: [String : KaraokeArtist] = [:]
			var threadArtistArray: [String] = []
			let scanner = Scanner(string: fileStr)
			while !scanner.isAtEnd, let nextLine = scanner.KscanUpToCharactersFrom(CharacterSet.newlines) {
				let parts = nextLine.split(separator: "\t")
				if parts.count >= 2 {
					let artistName = String(parts[0])
					let modifier: String? = parts.count >= 3 ? String(parts[2]) : nil
					let newSong = KaraokeSong(artistName: String(artistName), songTitle: String(parts[1]), 
							whateverThisModifierIs: modifier)
					threadSongs.append(newSong)
					
					var artist = threadArtists[artistName]
					if artist == nil {
						artist = KaraokeArtist(artistName: artistName)
						threadArtists[artistName] = artist
					}
					artist?.allSongs.append(newSong)
					artist?.filterSongs.append(newSong)
				}
			}
			
			// Step 4: Set up favorites
			let context = LocalCoreData.shared.mainThreadContext
			context.performAndWait {
				do {
					let fetchRequest = NSFetchRequest<KaraokeFavoriteSong>(entityName: "KaraokeFavoriteSong")
					let cdFavoriteSongs = try context.fetch(fetchRequest)
					
					for favoriteSong in cdFavoriteSongs {
						if let artist = threadArtists[favoriteSong.artistName] {
							artist.numFavoriteSongs += 1
							if let song = artist.allSongs.first(where: { $0.songTitle == favoriteSong.songTitle }) {
								song.isFavorite = true
							}
						}
					}
				}	
				catch {
					CoreDataLog.error("Couldn't load Favorite Karaoke Songs from Core Data.", ["Error" : error])
				}
			}

			// Step 5: Sort the arrays
			threadArtistArray = threadArtists.keys.sorted { $0.caseInsensitiveCompare($1) == .orderedAscending }
			threadSongs = threadSongs.sorted { $0.songTitle.caseInsensitiveCompare($1.songTitle) == .orderedAscending }
//			print ("Total Time: \(ProcessInfo.processInfo.systemUptime - startTime)")
			
			// Step 5: Write data back, on the main thread.
			DispatchQueue.main.async {
				self.artists = threadArtists
				self.artistArray = threadArtistArray
				self.songsArray = threadSongs
				self.loadingComplete = true
				done()
			}
		}
	}
	
	func setFavoriteSongStatus(for songObject: KaraokeSong?, to newState: Bool) {
		if let song = songObject {
			song.isFavorite = newState
			if let artist = artists[song.artistName] {
				artist.numFavoriteSongs += newState ? 1 : -1
			}
			saveFavoriteSongs()
		}
	}	
	
	func saveFavoriteSongs() {
		let context = LocalCoreData.shared.networkOperationContext
		context.perform {
			do {
				let fetchRequest = NSFetchRequest<KaraokeFavoriteSong>(entityName: "KaraokeFavoriteSong")
				let cdFavoriteSongs = try context.fetch(fetchRequest)
				for song in cdFavoriteSongs {
					context.delete(song)
				}
				let favoriteSongs = self.songsArray.filter { $0.isFavorite == true }
				for fav in favoriteSongs {
					let newSong = KaraokeFavoriteSong(context: context)
					newSong.artistName = fav.artistName
					newSong.songTitle = fav.songTitle
				}
				try context.save()
			}
			catch {
				CoreDataLog.error("Couldn't save Favorite Karaoke Songs to Core Data.", ["Error" : error])
			}
		}
	}
		

}


// MARK: - Special Use Code
extension KaraokeDataManager {
	// DO NOT CALL THIS METHOD AS PART OF NORMAL APP EXECUTION!
	// This is a utility fn that's here to compress the Karaoke source file. To use, add the Karaoke TEXT file
	// to the app as a Resource file, add a call to this method somewhere, and run the app on the simulator. 
	// After this method runs, look at the console output and grab the file URL to the compressed file (which will point 
	// to somewhere inside /Library/Developer/CoreSimulator) and copy the new compressed file into the Git repo.
	func compressSongFile() {
		do {
			if let fileUrl = Bundle.main.url(forResource: "JoCoKaraokeSongCatalog", withExtension: "txt"),
					let fileContents = try? String(contentsOf: fileUrl, encoding: .utf8) {
				var sourceBuffer = Array(fileContents.utf8)
				let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: sourceBuffer.count)
				let compressedSize = compression_encode_buffer(destinationBuffer, sourceBuffer.count,
						&sourceBuffer, sourceBuffer.count, nil, COMPRESSION_LZFSE)
				print(compressedSize)
				
				let writeUrl = fileUrl.deletingPathExtension().appendingPathExtension("lzfse")
				let compressedData = Data(bytes: destinationBuffer, count: compressedSize)
				try compressedData.write(to: writeUrl)
				print (writeUrl)
			}
		}
		catch {
			print("Songlist compression failed, somehow.")
		}
	}
}
