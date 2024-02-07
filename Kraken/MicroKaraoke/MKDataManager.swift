//
//  MKDataManager.swift
//  Kraken
//
//  Created by Chall Fry on 2/3/24.
//  Copyright © 2024 Chall Fry. All rights reserved.
//

import Foundation
import AVFoundation
import CoreData
import UIKit

@objc(MicroKaraokeSong) public class MicroKaraokeSong: KrakenManagedObject {
    @NSManaged public var id: Int64
    @NSManaged public var songName: String
    @NSManaged public var artistName: String
    @NSManaged public var lastUpdateTime: Date?

    // Sets reasonable default values for properties that could conceivably not change during buildFromV2 methods.
	public override func awakeFromInsert() {
		super.awakeFromInsert()
	}
	
    // Only call this within a CoreData perform block. ForumListData doesn't include data about posts.
    // Requires: Users for creators of all forums.
	func buildFromV3(context: NSManagedObjectContext, v3Object: MicroKaraokeCompletedSong) {
		TestAndUpdate(\.id, Int64(v3Object.songID))
		TestAndUpdate(\.songName, v3Object.songName)
		TestAndUpdate(\.artistName, v3Object.artistName)
		TestAndUpdate(\.lastUpdateTime, v3Object.completionTime)
	}
}


@objc class MicroKaraokeDataManager: NSObject {
	static let shared = MicroKaraokeDataManager()
	
	@objc dynamic var offerDownloadInProgress = false
	@objc dynamic var videoUploadInProgress = false
	@objc dynamic var lastNetworkError: String?
	@objc dynamic var downloadingVideoForSongID: String?
	@objc dynamic var songDownloadProgress: Float = 0.0
	
	private var currentOffer: MicroKaraokeOfferPacket?
	public var currentListenFile: URL?						// LOCAL copy of the audio clip with vocals
	public var currentRecordFile: URL?						// LOCAL copy of the audio clip with no vocals
	private var offerDoneClosure: (() -> Void)?
	private var uploadDoneClosure: (() -> Void)?
	
	// Gets the file URL that user-recorded videos get saved to. Should only be one video at a time, so they all use the same path.
	func getVideoRecordingURL() -> URL {
		let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
		let fileUrl = paths[0].appendingPathComponent("output.mp4")
		return fileUrl
	}
	
	func getCurrentOffer() -> MicroKaraokeOfferPacket? {
		// Make sure we have everything we need downloaded
		guard let offer = currentOffer, offer.offerExpirationTime > Date(), currentListenFile != nil, currentRecordFile != nil,
				!offerDownloadInProgress else {
			return nil
		}		
		return offer
	}
	
	// Asks the server for a reservation to record a song clip.
	func downloadOffer(done: @escaping() -> Void) {
		// If we have a non-expired, non-fulfilled offer downloaded, we're done.
		if (getCurrentOffer() != nil) {
			done()
			return
		}
		// If we're currently in the process of downloading an offer, let it complete.
		if offerDownloadInProgress {
			return
		}
		offerDoneClosure = done
		var request = NetworkGovernor.buildTwittarRequest(withPath: "/api/v3/microkaraoke/offer", query: [])
		request.httpMethod = "POST"
		NetworkGovernor.addUserCredential(to: &request)
		offerDownloadInProgress = true
		currentOffer = nil
		currentListenFile = nil
		currentRecordFile = nil
		lastNetworkError = nil
		NetworkGovernor.shared.queue(request) { (package: NetworkResponse) in
			if let error = package.networkError {
				self.lastNetworkError = error.getErrorString() 
				self.offerDownloadInProgress = false
			}
			else if let error = package.serverError {
				self.lastNetworkError = error.getCompleteError() 
				self.offerDownloadInProgress = false
			}
			else if let data = package.data {
				print (String(decoding:data, as: UTF8.self))
				do {
					var packet = try Settings.v3Decoder.decode(MicroKaraokeOfferPacket.self, from: data)
					packet.lyrics = packet.lyrics.trimmingCharacters(in: .whitespacesAndNewlines)
					self.currentOffer = packet
					self.downloadListenClip(for: packet)
				} catch 
				{
					self.offerDownloadInProgress = false
					NetworkLog.error("Failure parsing Micro Karaoke offer.", ["Error" : error, "URL" : request.url as Any])
				} 
			}
			else {
				self.lastNetworkError = "Couldn't load data from server."
				self.offerDownloadInProgress = false
			}
		}
	}
	
	func downloadListenClip(for offer: MicroKaraokeOfferPacket) {
		let request = NetworkGovernor.buildTwittarRequest(withURL: offer.originalSnippetSoundURL)
		NetworkGovernor.shared.queue(request) { (package: NetworkResponse) in
			if let error = package.serverError {
				self.lastNetworkError = error.getCompleteError()
				self.offerDownloadInProgress = false
			}
			else if let data = package.data {
				do {
					let localPath = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
							.appendingPathComponent("listen.mp3")
					try data.write(to: localPath)
					self.currentListenFile = localPath
					self.downloadRecordClip(for: offer)
				}
				catch {
					self.lastNetworkError = error.localizedDescription
					self.offerDownloadInProgress = false
				}
			} else {
				self.lastNetworkError = "Couldn't load sound file from server."
				self.offerDownloadInProgress = false
			}
		}
	}
	
	func downloadRecordClip(for offer: MicroKaraokeOfferPacket) {
		let request = NetworkGovernor.buildTwittarRequest(withURL: offer.karaokeSnippetSoundURL)
		NetworkGovernor.shared.queue(request) { (package: NetworkResponse) in
			if let error = package.serverError {
				self.lastNetworkError = error.getCompleteError()
			}
			else if let data = package.data {
				do {
					let localPath = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
							.appendingPathComponent("record.mp3")
					try data.write(to: localPath)
					self.currentRecordFile = localPath
					self.lastNetworkError = nil
					self.offerDoneClosure?()
					self.offerDoneClosure = nil
				}
				catch {
					self.lastNetworkError = error.localizedDescription
				}
			} else {
				self.lastNetworkError = "Couldn't load sound file from server."
			}
			self.offerDownloadInProgress = false
		}
	}
	
	func uploadVideoClip(done: @escaping() -> Void) {
		// Note that an exired offer *might* still be okay! The user is no longer 'reserving' the slot in the sense
		// that another user could take the reservation, but if the user uploads video to an expired reservation it 
		// still fullfills it.
		guard let offer = currentOffer else {
			lastNetworkError = "We don't have a song slot reservation for this."
			return
		}
		uploadDoneClosure = done

		let fileUrl = MicroKaraokeDataManager.shared.getVideoRecordingURL()
		guard let videoData = try? Data(contentsOf: fileUrl) else {
			lastNetworkError = "Could not prep video file for upload."
			return
		}
		let uploadData = MicroKaraokeRecordingData(offerID: offer.offerID, videoData: videoData)
		var request = NetworkGovernor.buildTwittarRequest(withPath: "/api/v3/microkaraoke/recording", query: [])
		request.httpMethod = "POST"
		request.httpBody = try! Settings.v3Encoder.encode(uploadData)
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		NetworkGovernor.addUserCredential(to: &request)

		videoUploadInProgress = true
		lastNetworkError = nil
		NetworkGovernor.shared.queue(request) { (package: NetworkResponse) in
			if let error = package.networkError {
				self.lastNetworkError = error.getErrorString() 
			}
			else if let error = package.serverError {
				self.lastNetworkError = error.getCompleteError() 
			}
			else {
				done()
				self.uploadDoneClosure = nil
			}
			// Success or failure, the upload is 'done'. If it failed we should re-check the reservation, so we clear it here.
			self.currentOffer = nil
			self.currentListenFile = nil
			self.currentRecordFile = nil
			self.videoUploadInProgress = false
		}
	}
	
	func getCompletedVideos() {
		var request = NetworkGovernor.buildTwittarRequest(withPath: "/api/v3/microkaraoke/songlist")
		NetworkGovernor.addUserCredential(to: &request)
		NetworkGovernor.shared.queue(request) { (package: NetworkResponse) in
			if let error = package.networkError {
				self.lastNetworkError = error.getErrorString() 
			}
			if let error = package.serverError {
				self.lastNetworkError = error.getCompleteError()
			}
			else if let data = package.data {
				do {
					let packet = try Settings.v3Decoder.decode([MicroKaraokeCompletedSong].self, from: data)
					self.ingestCompletedVideos(from: packet)
				}
				catch {
					self.lastNetworkError = error.localizedDescription
				}
			}
		}
	}
	
	func ingestCompletedVideos(from songs: [MicroKaraokeCompletedSong]) {
		LocalCoreData.shared.performNetworkParsing { context in
			context.pushOpErrorExplanation("Failed to parse Micro Karaoke songs and add to Core Data.")
						
			// Fetch songs from CD that match the ids in the given songs
			let allSongIDs = songs.map { $0.songID }
			let request = NSFetchRequest<MicroKaraokeSong>(entityName: "MicroKaraokeSong")
			request.predicate = NSPredicate(format: "id IN %@", allSongIDs)
			let cdSongs = try request.execute()
			let cdSongsDict = Dictionary(cdSongs.map { ($0.id, $0) }, uniquingKeysWith: { (first,_) in first })

			for song in songs {
				let cdSong = cdSongsDict[Int64(song.songID)] ?? MicroKaraokeSong(context: context)
				cdSong.buildFromV3(context: context, v3Object: song)
			}
			
			// Delete songs in db that aren't in results.
		}
	}
	
// MARK: - Completed Song Download
	var lastSongDownloadError: String? = nil
	var doneDownloadingSong: ((AVPlayerItem) -> Void)?
	func downloadCompletedSong(songID: Int64, done: @escaping(AVPlayerItem) -> Void) {
		// If we're currently in the process of downloading an song, let it complete.
		guard downloadingVideoForSongID == nil else {
			return
		}
		doneDownloadingSong = done
		downloadingVideoForSongID = String(songID)
		lastSongDownloadError = nil
		var request = NetworkGovernor.buildTwittarRequest(withPath: "/api/v3/microkaraoke/song/\(songID)", query: [])
		NetworkGovernor.addUserCredential(to: &request)
		NetworkGovernor.shared.queue(request) { (package: NetworkResponse) in
			if let error = package.networkError {
				self.lastSongDownloadError = error.getErrorString() 
			}
			else if let error = package.serverError {
				self.lastSongDownloadError = error.getCompleteError() 
			}
			else if let data = package.data {
				do {
					let manifest = try Settings.v3Decoder.decode(MicroKaraokeSongManifest.self, from: data)
					self.downloadVideo(in: manifest, at: 0)
				} catch 
				{
					NetworkLog.error("Failure parsing Micro Karaoke song.", ["Error" : error, "URL" : request.url as Any])
				} 
			}
			else {
				self.lastSongDownloadError = "Couldn't load data from server."
			}
			if self.lastSongDownloadError != nil {
				self.downloadingVideoForSongID = nil
			}
		}
	}
	
	// Calls itself 'recursively' for each video clip in the song. But, since it uses an async callback, it's not
	// real recursion.
	func downloadVideo(in manifest: MicroKaraokeSongManifest, at index: Int) {
		guard index < manifest.snippetVideoURLs.count, let videoURL = URL(string: manifest.snippetVideoURLs[index]) else {
			return
		}
		songDownloadProgress = Float(index) / Float(manifest.snippetVideoURLs.count)
		
		guard var localPath = try? FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
				.appendingPathComponent("finishedSongParts_\(manifest.songID)") else {
			return		
		}
		try? FileManager.default.createDirectory(at: localPath, withIntermediateDirectories: true)
		localPath.appendPathComponent("\(index).mp4")
		if FileManager.default.fileExists(atPath: localPath.path) {
			print("Already have video clip \(index)")
			if index + 1 >= manifest.snippetVideoURLs.count {
				self.downloadSongAudioClip(in: manifest, at: 0)
			}
			else {
				self.downloadVideo(in: manifest, at: index + 1)
			}
			return
		}

		var request = NetworkGovernor.buildTwittarRequest(withURL: videoURL)
		NetworkGovernor.addUserCredential(to: &request)
		NetworkGovernor.shared.queue(request) { (package: NetworkResponse) in
			if let error = package.networkError {
				self.lastSongDownloadError = error.getErrorString()
			}
			else if let error = package.serverError {
				self.lastSongDownloadError = error.getCompleteError()
			}
			else if let data = package.data {
				do {
					try data.write(to: localPath)
					if index + 1 >= manifest.snippetVideoURLs.count {
						self.downloadSongAudioClip(in: manifest, at: 0)
					}
					else {
						self.downloadVideo(in: manifest, at: index + 1)
					}
				}
				catch {
					self.lastNetworkError = error.localizedDescription
				}
			} else {
				self.lastSongDownloadError = "Couldn't load vido file from server."
			}
			if self.lastSongDownloadError != nil {
				self.downloadingVideoForSongID = nil
			}
		}
	}
	
	func downloadSongAudioClip(in manifest: MicroKaraokeSongManifest, at index: Int)  {
		guard index < manifest.snippetAudioURLs.count, let audioURL = URL(string: manifest.snippetAudioURLs[index]) else {
			return
		}
//		songDownloadProgress = Float(index) / Float(manifest.snippetVideoURLs.count)
		let request = NetworkGovernor.buildTwittarRequest(withURL: audioURL)
		NetworkGovernor.shared.queue(request) { (package: NetworkResponse) in
			if let error = package.networkError {
				self.lastSongDownloadError = error.getErrorString()
			}
			else if let error = package.serverError {
				self.lastSongDownloadError = error.getCompleteError()
			}
			else if let data = package.data {
				do {
					var localPath = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
							.appendingPathComponent("finishedSongParts_\(manifest.songID)")
					try FileManager.default.createDirectory(at: localPath, withIntermediateDirectories: true)
					localPath.appendPathComponent("\(index).mp3")
					try data.write(to: localPath)
					if index + 1 >= manifest.snippetAudioURLs.count {
						self.assembleCompletedVideo(from: manifest)
					}
					else {
						self.downloadSongAudioClip(in: manifest, at: index + 1)
					}
				}
				catch {
					self.lastNetworkError = error.localizedDescription
				}
			} else {
				self.lastSongDownloadError = "Couldn't load sound file from server."
			}
			self.offerDownloadInProgress = false
		}
	}

	func assembleCompletedVideo(from manifest: MicroKaraokeSongManifest) {
		do {
			let comp = AVMutableComposition()
			let assetDir = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
					.appendingPathComponent("finishedSongParts_\(manifest.songID)")
			
			var insertTimePoint = CMTime(seconds: 0, preferredTimescale: 44100)
			let videoTrack = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
			let audioTrack = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!
			let audioTrack2 = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!

			for index in 0..<manifest.snippetVideoURLs.count {
//			for index in 0..<1 {
				print("adding clip \(index) to video")
				let pathExtension = URL(string: manifest.snippetVideoURLs[index])!.pathExtension
				let videoAsset = AVURLAsset(url: assetDir.appendingPathComponent("\(index).\(pathExtension)"))
				let audioAsset = AVURLAsset(url: assetDir.appendingPathComponent("\(index).mp3"))
				let timeRange = CMTimeRange(start: .zero, duration: audioAsset.duration)
				try videoTrack.insertTimeRange(timeRange, of: videoAsset.tracks(withMediaType: .video)[0], at: insertTimePoint)
				if let karaokeSinging = videoAsset.tracks(withMediaType: .audio).first {
					try audioTrack.insertTimeRange(timeRange, of: karaokeSinging, at: insertTimePoint)
				}
				if let backingAudio = audioAsset.tracks(withMediaType: .audio).first {
					try audioTrack2.insertTimeRange(timeRange, of: backingAudio, at: insertTimePoint)
				}

				insertTimePoint = insertTimePoint + audioAsset.duration
			}
			
			let audioMix = AVMutableAudioMix()
			let volumeParam = AVMutableAudioMixInputParameters(track: audioTrack2)
			volumeParam.setVolume(0.5, at: CMTime.zero)
			audioMix.inputParameters.append(volumeParam)
			let vp2 = AVMutableAudioMixInputParameters(track: audioTrack)
			vp2.setVolume(10.0, at: CMTime.zero)
			audioMix.inputParameters.append(vp2)
			
			let playerItem = AVPlayerItem(asset: comp)
			playerItem.audioMix = audioMix
			
			DispatchQueue.main.async {
				self.doneDownloadingSong?(playerItem)
				self.doneDownloadingSong = nil
				self.downloadingVideoForSongID = nil
			}

if false {
			let finishedVideo = assetDir.appendingPathComponent("Song_\(manifest.songID).mov")
			try? FileManager.default.removeItem(at: finishedVideo)
			let export = AVAssetExportSession(asset: comp, presetName: AVAssetExportPresetLowQuality)!
			export.audioMix = audioMix
			export.outputURL = finishedVideo
			export.outputFileType = AVFileType.mov
			export.exportAsynchronously {
				switch export.status {
					case .completed:
						print("woot")
						DispatchQueue.main.async {
//							self.doneDownloadingSong?(finishedVideo)
						}
					case .failed:
						print("Failed: \(export.error as Any)")
					default:
						break
				}
			}
}
		}
		catch {
			print("Error thrown: \(error)")
		}
	}
}

// MARK: - V3 API Structs

public struct MicroKaraokeOfferPacket: Codable {
	///	The ID of this offer. Offers are good for 30 minutes (or until fulfilled with a snippet upload), and a user may only
	/// have 1 open offer at a time. If a user re-requests while the offser is open, they should get the same offer response.
	/// This prevents users shopping for the lyric they want to sing.
	var offerID: UUID
	/// Each song the server works on collecting (via piecing together multiple song clips from users) gets an ID
	var songID: Int
	/// The song title, as it'd appear in karaoke metadata
	var songName: String
	/// The artist, as they'd appear in karaoke metadata
	var artistName: String
	/// Song tempo. May not be exact; used for the timing of the countdown prompt before recording starts.
	var bpm: Int
	/// TRUE if all the clips for this song must be recorded in portrait mode. FALSE if they all need to be landscape.
	var portraitMode: Bool
	/// Which song snippet is being offered (songs are divided into 30-50 snippets when configured for use on Swiftarr)
	var snippetIndex: Int
	/// The lyrics the user is supposed to sing. Generally 1-2 lines. NOT the entire lyrics for the song.
	var lyrics: String
	/// An URL that points to a .mp3 file containing ~6 seconds of the original song
	/// This clip will have the artist singing the lyrics of 1-2 lines of the song, for the user to listen to before recording.
	var originalSnippetSoundURL: URL
	/// This is a karaoke backing snippet to play while recording. It will be the same part of the song as `originalSnippetSoundURL`
	/// but MAY NOT quite be the same duration (karaoke versions of songs are sometimes faster or slower tempo then their originals).
	/// As a karaoke track, this snippet won't have main vocals, but it also could have slightly diffeent instruments/sounds.
	var karaokeSnippetSoundURL: URL
	/// The time that this offer expires. If no upload has happened by this time, the user will need to request a new snippet offer,
	/// which will likely be for a different part of the song, or even a different song altogether.
	var offerExpirationTime: Date
}

public struct MicroKaraokeRecordingData: Codable {
	/// The offer from the server that this upload is fulfilling. Basically the reservation the server gives the client for a song clip.
	var offerID: UUID
	/// The uploaded video; usually a .mp4
	var videoData: Data
}

public struct MicroKaraokeCompletedSong: Codable {
	/// Each song the server works on collecting (via piecing together multiple song clips from users) gets an ID
	var songID: Int
	// The song title, as it'd appear in karaoke metadata
	var songName: String
	/// The artist, as they'd appear in karaoke metadata
	var artistName: String
	/// When the song's clips were last modified. Usually the time the final snippet gets uploaded (although 'final' means '30th out of 30'
	/// and not 'the one at the end of the song'). However, clips can get deleted via moderation, causing the server to re-issue an offer
	/// for the deleted clip, which may change the completion time. NIL if song isn't complete
	var completionTime: Date?
}

public struct MicroKaraokeSongManifest: Codable {
	/// Each song the server works on collecting (via piecing together multiple song clips from users) gets an ID
	var songID: Int
	/// TRUE if all the clips for this song must be recorded in portrait mode. FALSE if they all need to be landscape.
	var portraitMode: Bool
	/// The video snippets that make up the song. Some snippets may be 'filler', such as for a song's instrumental section.
	var snippetVideoURLs: [String]
	/// The karaoke audio for the song
	var snippetAudioURLs: [String]
}
