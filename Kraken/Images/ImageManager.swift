//
//  ImageManager.swift
//  Kraken
//
//  Created by Chall Fry on 3/28/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import Foundation
import UIKit

// Why not just use NSCache? 
// I have a personal dislike for NSCache's complete lack of transparency and debuggability.
// If I want to inspect the cache to see what's in it -- haha! You can't! Never mind doing something
// *crazy* like logging cache hit/miss stats before/after a partial memory purge. 
// Without those sorts of features, setting cache limits is just throwing darts at a dartboard.
class ImageCache {
	var imageCache = [String: UIImage]()
	var imageCacheLRU = [String]()				// 0 gets thrown away first; N-1 is the most recently used
	var allCachedFilenames = Set<String>()
	
	private let imageCacheQ = DispatchQueue(label:"ImageCache mutation serializer")
	var fileCacheDir: URL?

	init(fileCacheDirectory: String) {
		if let tempDirURL = NSURL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(fileCacheDirectory) {
			do {
				try FileManager.default.createDirectory(at: tempDirURL, withIntermediateDirectories: true, attributes: nil)
				fileCacheDir = tempDirURL
				
				// May have to spin this off on a Q if it's taking too long.
				if let tempDirString = fileCacheDir?.absoluteString {
					let cachedFilenames = try FileManager.default.contentsOfDirectory(atPath: tempDirString)
					allCachedFilenames.formUnion(cachedFilenames)
				}
			} catch {
			}
		}
	}

	func cacheImage(fromData: Data, withKey: String) {
		
	}
	
	// Returns the image immediately if it's in the RAM cache. Otherwise, returns nil.
	func image(forKey: String) -> UIImage? {
		let image = imageCache[forKey]
		if image != nil {
			if let lruIndex = imageCacheLRU.firstIndex(of: forKey) {
				imageCacheLRU.remove(at:lruIndex)
				imageCacheLRU.append(forKey)
			}
		}
		
		return image
	}
	
	// Fetches an image, returning the image in a completion block. The image data could be:
	// 		- in the cache already, in which case the done block is called immediately,
	//		- in local file storage; the compressed image data is read in async, rendered, and returned,
	//	 	- on the server; fetched via HTTP call. Obviously, only works when online with the Twitarr server.
	// 
	func image(forKey: String, done: (UIImage?) -> Void) {
		
	}

}

class ImageManager : NSObject {
	static let shared = ImageManager()
	
	enum ImageSizeEnum {
		case small				// Small thumbnail
		case medium				// Long edge <=800px? 
		case full
	}
	
	var smallImageCache = ImageCache(fileCacheDirectory: "smallImageCache")
	var medImageCache = ImageCache(fileCacheDirectory: "mediumImageCache")
	var largeImageCache = ImageCache(fileCacheDirectory: "largeImageCache")
	
	// The API contract for this method is: The done block COULD BE CALLED MULTIPLE TIMES. This could happen
	// if the requested size isn't in the cache, but a smaller size is. The smaller size is returned immediately,
	// while the larger size gets fetched async. 
	// Also, the returned image could be smaller or larger than the requested size class.
	// If the done block is called with nil, that indicates fetching completed with some sort of failure.
	func image(withSize: ImageSizeEnum, forKey: String, done: (UIImage?) -> Void) {
		
	}
}


struct TwitarrV2PhotoDetails: Codable {
	let id: String
	let animated: Bool
	var thumbSize: CGSize?
	var mediumSize: CGSize?
	var fullSize: CGSize?
	
	private struct RawResponse: Codable {
		let id: String
		let animated: Bool
		let sizes: [String: String]
	}
	
	init(from decoder: Decoder) throws {
		do {
			let rawDecode = try RawResponse(from: decoder)
			id = rawDecode.id
			animated = rawDecode.animated
			
			for (sizeTag, photoSize) in rawDecode.sizes {
				switch sizeTag {
				case "small_thumb": thumbSize = TwitarrV2PhotoDetails.ScanSizeFrom(photoSize)
				case "medium_thumb": mediumSize = TwitarrV2PhotoDetails.ScanSizeFrom(photoSize)
				case "full": fullSize = TwitarrV2PhotoDetails.ScanSizeFrom(photoSize)
				default: print("Found unknown photo size tag")
				}
			}
		} 
		catch {
			print (error)
			id = ""
			animated = false
		}
	}
	
	func encode(to encoder: Encoder) throws {
		var sizes = [String: String]()
		if let small = thumbSize {
			let sizeString = "\(small.width)x\(small.height)"
			sizes.updateValue(sizeString, forKey:"small_thumb")
		}
		if let med = mediumSize {
			let sizeString = "\(med.width)x\(med.height)"
			sizes.updateValue(sizeString, forKey:"medium_thumb")
		}
		if let full = fullSize {
			let sizeString = "\(full.width)x\(full.height)"
			sizes.updateValue(sizeString, forKey:"full")
		}
		let raw = RawResponse(id: id, animated: animated, sizes: sizes)
		
		var container = encoder.singleValueContainer()
		try container.encode(raw)
	}
	
	static private func ScanSizeFrom(_ value: String) -> CGSize? {
		let scan = Scanner(string: value)
		var result = CGSize(width: 0, height: 0)
		var rawValue: Int = 0
		
		var scanSuccess = scan.scanInt(&rawValue)
		result.width = CGFloat(rawValue)
		scanSuccess = scanSuccess && scan.scanString("x", into:nil)
		scanSuccess = scanSuccess && scan.scanInt(&rawValue)
		result.height = CGFloat(rawValue)
		
		return scanSuccess ? result : nil
	}

}
