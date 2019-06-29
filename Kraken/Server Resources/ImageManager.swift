//
//  ImageManager.swift
//  Kraken
//
//  Created by Chall Fry on 3/28/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import Foundation
import UIKit
import CoreData

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
	private var fileCacheDir: URL?
	private var memoryState: DispatchSource.MemoryPressureEvent = .normal
	private var countLimit = 0
	private var fetchURLPath: String
	private var cacheName: String

	init(dirName: String, fetchURL: String, limit: Int) {
		cacheName = dirName
		if let tempDirURL = NSURL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(dirName) {
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
		
		countLimit = limit
		fetchURLPath = fetchURL
		
		// Set up memory pressure handler
		let source = DispatchSource.makeMemoryPressureSource(eventMask: .all, queue: DispatchQueue.main)
		let handler: DispatchSourceProtocol.DispatchSourceHandler = { [weak self] in
			guard !source.isCancelled, let self = self else { return }

			self.memoryState = source.data
			if source.data == .critical {
				ImageLog.info("Memory pressure critical", ["CacheCount" : self.imageCache.count, "name" : self.cacheName])
				self.imageCache.removeAll()
				self.imageCacheLRU.removeAll()
			}
			else if source.data == .warning {
				ImageLog.info("Memory pressure at warning level", ["CacheCount" : self.imageCache.count, "name" : self.cacheName])
			
				// For warnings, should probably just dump a percentage of the cached data
		//		self.imageCache.removeAll()
		//		self.imageCacheLRU.removeAll()
			}
			else if source.data == .normal {
				ImageLog.info("Memory pressure at normal level", ["name" : self.cacheName])
			}
			
		}
		source.setEventHandler(handler: handler)
		source.setRegistrationHandler(handler: handler)
		source.resume()
		
	}

	func cacheImage(fromData: Data, withKey cacheKey: String) -> UIImage? {
		// If this image is already in the cache, just return it. It should be the same as the data passed in.
		if let cachedImage = imageCache[cacheKey] {
			touchCacheEntry(forKey: cacheKey)
			return cachedImage
		}
		
		guard let imageData = UIImage(data:fromData) else {
			return nil
		}
		
		// Add new item to RAM cache.
		imageCache[cacheKey] = imageData
		imageCacheLRU.append(cacheKey)
		
		// And, save the compressed image data to disk
		if let fileURL = fileCacheDir?.appendingPathComponent(cacheKey),
				!FileManager.default.fileExists(atPath: fileURL.absoluteString) {
			do {
				try fromData.write(to:fileURL, options:.atomic)
				allCachedFilenames.insert(cacheKey)
			}
			catch {
				ImageLog.error("Couldn't save image to file.", ["Error" : error, "cacheKey" : cacheKey])
			}
		}
		
		return imageData
	}
	
	// Returns the image immediately if it's in the RAM cache. Otherwise, returns nil.
	func image(forKey key: String) -> UIImage? {
		let image = imageCache[key]
		if image != nil {
			touchCacheEntry(forKey: key)
		}
		
		return image
	}
	
	// Fetches an image, returning the image in a completion block. The image data could be:
	// 		- in the cache already, in which case the done block is called immediately,
	//		- in local file storage; the compressed image data is read in async, rendered, and returned,
	//	 	- on the server; fetched via HTTP call. Obviously, only works when online with the Twitarr server.
	// 
	// Done block always gets called on the main thread.
	func image(forKey key: String, done: @escaping (UIImage?) -> Void) {
	
		// 1. Local RAM cache
		if let image = imageCache[key] {
			touchCacheEntry(forKey: key)
			done(image)
			return
		}
		
		// 2. File cache
		if allCachedFilenames.contains(key), let fileURL = fileCacheDir?.appendingPathComponent(key) {
			if let image = UIImage(contentsOfFile:fileURL.path) {
				imageCache[key] = image
				imageCacheLRU.append(key)
				DispatchQueue.main.async { done(image) }
				return
			}
			else {
				// Delete the file; it doesn't seem to produce an image
				try? FileManager.default.removeItem(at: fileURL)
				allCachedFilenames.remove(key)
			}
		}
		
		// 3. Ask the server.
		let request = NetworkGovernor.buildTwittarV2Request(withPath:"\(fetchURLPath)\(key)")
		NetworkGovernor.shared.queue(request) { (data: Data?, response: URLResponse?) in
			if let response = response as? HTTPURLResponse {
				if response.statusCode < 300, let data = data, let image = self.cacheImage(fromData:data, withKey:key) {
					DispatchQueue.main.async { done(image) }
				} else 
				{
					// Load failed for some reason
				}
			}
		}
		
	}
	
	private func touchCacheEntry(forKey: String) {
		if let lruIndex = imageCacheLRU.firstIndex(of: forKey) {
			imageCacheLRU.remove(at:lruIndex)
			imageCacheLRU.append(forKey)
		}
	}

}

class ImageManager : NSObject {
	static let shared = ImageManager()
	
	enum ImageSizeEnum {
		case small				// Small thumbnail
		case medium				// Long edge <=800px? 
		case full
	}
	
	var smallImageCache = ImageCache(dirName: "smallImageCache", fetchURL: "/api/v2/photo/small_thumb/", limit: 1000)
	var medImageCache = ImageCache(dirName: "mediumImageCache", fetchURL: "/api/v2/photo/medium_thumb/", limit: 1000)
	var largeImageCache = ImageCache(dirName: "largeImageCache", fetchURL: "/api/v2/photo/full/", limit: 1000)

	var userImageCache = ImageCache(dirName: "userImageCache", fetchURL: "/api/v2/user/photo/", limit: 2000)
	
	// The API contract for this method is: The done block COULD BE CALLED MULTIPLE TIMES. This could happen
	// if the requested size isn't in the cache, but a smaller size is. The smaller size is returned immediately,
	// while the larger size gets fetched async. 
	// Also, the returned image could be smaller or larger than the requested size class.
	// If the done block is called with nil, that indicates fetching completed with some sort of failure.
	func image(withSize: ImageSizeEnum, forKey: String, done: @escaping (UIImage?) -> Void) {
		switch withSize {
			case .small: smallImageCache.image(forKey: forKey, done: done)
			case .medium: medImageCache.image(forKey: forKey, done: done)
			case .full: largeImageCache.image(forKey: forKey, done: done)
		}
	}
	
	// Must be inside a context.perform
	func update(photoDetails: [String : TwitarrV2PhotoDetails], inContext context: NSManagedObjectContext) {
		do {
			var photoIds = Set(photoDetails.keys)
			let request = LocalCoreData.shared.persistentContainer.managedObjectModel.fetchRequestFromTemplate(withName: "PhotosWithIds", 
					substitutionVariables: [ "ids" : photoIds ]) as! NSFetchRequest<PhotoDetails>
			let results = try request.execute()
			var resultDict = Dictionary(uniqueKeysWithValues: zip(results.map { $0.id } , results))
			
			// I don't think PhotoDetails objects can ever change; therefore there's no updating that needs to be done.
			photoIds.subtract(resultDict.keys)
						
			// Anything still in photoIds needs to be added
			for photoId in photoIds {
				let newPhotoDetails = PhotoDetails(context: context)
				newPhotoDetails.buildFromV2(context: context, v2Object: photoDetails[photoId]!)
				resultDict[photoId] = newPhotoDetails
			}
			
			// Results should now have all the users that were passed in.
			context.userInfo.setObject(resultDict, forKey: "PhotoDetails" as NSString)
		}
		catch {
			ImageLog.error("Failed to fetch photoDetail ids while updating with new ids.", ["Error" : error])
		}
	}

}

@objc(PhotoDetails) public class PhotoDetails : KrakenManagedObject {
	@NSManaged var id: String
	@NSManaged var animated: Bool
	@NSManaged private var thumbWidth: Int32
	@NSManaged private var thumbHeight: Int32
	@NSManaged private var mediumWidth: Int32
	@NSManaged private var mediumHeight: Int32
	@NSManaged private var fullWidth: Int32
	@NSManaged private var fullHeight: Int32
	
	var thumbSize: CGSize? {
		get {
			return thumbWidth > 0 && thumbHeight > 0 ? CGSize(width: Int(thumbWidth), height: Int(thumbHeight)) : nil
		}
		set {
			thumbWidth = Int32(newValue?.width ?? 0)
			thumbHeight = Int32(newValue?.height ?? 0)
		}
	}

	var mediumSize: CGSize? {
		get {
			return mediumWidth > 0 && mediumHeight > 0 ? CGSize(width: Int(mediumWidth), height: Int(mediumHeight)) : nil
		}
		set {
			mediumWidth = Int32(newValue?.width ?? 0)
			mediumHeight = Int32(newValue?.height ?? 0)
		}
	}

	var fullSize: CGSize? {
		get {
			return fullWidth > 0 && fullHeight > 0 ? CGSize(width: Int(fullWidth), height: Int(fullHeight)) : nil
		}
		set {
			fullWidth = Int32(newValue?.width ?? 0)
			fullHeight = Int32(newValue?.height ?? 0)
		}
	}

	func buildFromV2(context: NSManagedObjectContext, v2Object: TwitarrV2PhotoDetails) {
		TestAndUpdate(\.id, v2Object.id)
		TestAndUpdate(\.animated, v2Object.animated)
		TestAndUpdate(\.thumbSize, v2Object.thumbSize)
		TestAndUpdate(\.mediumSize, v2Object.mediumSize)
		TestAndUpdate(\.fullSize, v2Object.fullSize)
	}
}

// MARK: - V2 API Decoding

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
				default: ImageLog.debug("Found unknown photo size tag")
				}
			}
		} 
		catch {
			ImageLog.error("Error thrown when parsing TwitarrV2Photo.", ["Error" : error])
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
