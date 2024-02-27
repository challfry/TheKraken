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
import Accelerate

@objc(MicroKaraokeSong) public class MicroKaraokeSong: KrakenManagedObject {
    @NSManaged public var id: Int64
    @NSManaged public var songName: String
    @NSManaged public var artistName: String
    @NSManaged public var completionTime: Date?
    @NSManaged public var userContributed: Bool
    @NSManaged public var modApproved: Bool

    // Sets reasonable default values for properties that could conceivably not change during buildFromV2 methods.
	public override func awakeFromInsert() {
		super.awakeFromInsert()
	}
	
    // Only call this within a CoreData perform block.
	func buildFromV3(context: NSManagedObjectContext, v3Object: MicroKaraokeCompletedSong) {
		TestAndUpdate(\.id, Int64(v3Object.songID))
		TestAndUpdate(\.songName, v3Object.songName)
		TestAndUpdate(\.artistName, v3Object.artistName)
		TestAndUpdate(\.completionTime, v3Object.completionTime)
		TestAndUpdate(\.userContributed, v3Object.userContributed)
		TestAndUpdate(\.modApproved, v3Object.modApproved)
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
	private var currentOfferUser: KrakenUser?				// User who was offered the currentOffer
	public var currentListenFile: URL?						// LOCAL copy of the audio clip with vocals
	public var currentRecordFile: URL?						// LOCAL copy of the audio clip with no vocals
	private var offerDoneClosure: (() -> Void)?
	private var uploadDoneClosure: (() -> Void)?
	private var doneDownloadingSong: ((AVPlayerItem?, URL?, String?) -> Void)?

// MARK: -	
	// Gets the file URL that user-recorded videos get saved to. Should only be one video at a time, so they all use the same path.
	func getVideoRecordingURL() -> URL {
		let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
		let fileUrl = paths[0].appendingPathComponent("output.mp4")
		return fileUrl
	}
	
	func getProcessedVideoRecordingURL() -> URL {
		let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
		let fileUrl = paths[0].appendingPathComponent("processedVideo.mp4")
		return fileUrl
	}
	
	// Note that expired offers MAY still be accepted by the server, if the server hasn't farmed out the slot to someone else yet.
	// So, the initial check when we start the flow checks for expiration, and other calls don't.
	func getCurrentOffer(validateNotExpired: Bool = false) -> MicroKaraokeOfferPacket? {
		// Make sure the user hasn't changed
		guard let currentUser = CurrentUser.shared.loggedInUser, let offerUser = currentOfferUser,
				offerUser.userID == currentUser.userID else {
			currentOffer = nil
			currentOfferUser = nil
			return nil		
		}
		// Make sure we have everything we need downloaded
		guard let offer = currentOffer, offer.offerExpirationTime > Date(), currentListenFile != nil, currentRecordFile != nil,
				!offerDownloadInProgress else {
			return nil
		}	
		if validateNotExpired {
			guard offer.offerExpirationTime > Date() else {
				return nil
			}
		}
		return offer
	}
	
	// Asks the server for a reservation to record a song clip.
	func downloadOffer(done: @escaping() -> Void) {
		// If we have a non-expired, non-fulfilled offer downloaded, we're done.
		if (getCurrentOffer(validateNotExpired: true) != nil) {
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
		currentOfferUser = nil
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
					self.currentOfferUser = CurrentUser.shared.loggedInUser
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
					let origFileURL = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
							.appendingPathComponent("recordOrig.mp3")
					let recordFileURL = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
							.appendingPathComponent("record.m4a")
					try data.write(to: origFileURL)
					try self.panBackingAudioClip(inputFileURL: origFileURL, outputFileURL: recordFileURL)
					self.currentRecordFile = recordFileURL
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
	
	// Makes the backing audio right-channel only, so that the audio only plays out the bottom speakers, far from the microphone.
	func panBackingAudioClip(inputFileURL: URL, outputFileURL: URL) throws {
//		let audioBuffers = try getPCMBufferForAsset(file: inputFileURL, format: stereoFormat, deinterleave: false)
		let asset = AVURLAsset(url: inputFileURL)
		let assetAudioTrack = asset.tracks(withMediaType: .audio).first!
		let reader = try AVAssetReader(asset: asset)
		let trackOutput = AVAssetReaderTrackOutput(track: assetAudioTrack, outputSettings:  [ AVFormatIDKey : kAudioFormatLinearPCM ])
		reader.add(trackOutput)
		reader.startReading()

		let dur = asset.duration
		var samplesWritten = 0
		let audioBuffer = UnsafeMutableBufferPointer<LPCMStereoFrame>.allocate(capacity: Int(dur.value))
		while let buffer = trackOutput.copyNextSampleBuffer() {
			try buffer.dataBuffer?.withUnsafeMutableBytes { bytes in
				let _ = bytes.withMemoryRebound(to: LPCMStereoFrame.self) { frameValues in
					memcpy(audioBuffer.baseAddress! + samplesWritten, frameValues.baseAddress, bytes.count)
				}
				samplesWritten += buffer.numSamples
			}
		}
		
		for index in 0..<audioBuffer.count {
			// Works best for portrait?
			if getCurrentOffer()?.portraitMode == true {
				audioBuffer[index].left = (audioBuffer[index].left + audioBuffer[index].right) / 2.0
				audioBuffer[index].right = 0.0
			}
			else {
				audioBuffer[index].right = (audioBuffer[index].left + audioBuffer[index].right) / 2.0
				audioBuffer[index].left = 0.0
			}
		}
		
		var sourceFormat = AudioStreamBasicDescription(mSampleRate: 44100, mFormatID: kAudioFormatLinearPCM, mFormatFlags: kAudioFormatFlagIsFloat, 
				mBytesPerPacket: 8, mFramesPerPacket: 1, mBytesPerFrame: 8, mChannelsPerFrame: 2, mBitsPerChannel: 32, mReserved: 0)
		var fileFormat = AudioStreamBasicDescription(mSampleRate: 44100, mFormatID: kAudioFormatMPEG4AAC, mFormatFlags: 0,
				mBytesPerPacket: 0, mFramesPerPacket: 0, mBytesPerFrame: 0, mChannelsPerFrame: 2, mBitsPerChannel: 0, mReserved: 0)
	
		var outputFileOpt: ExtAudioFileRef?
		var err = ExtAudioFileCreateWithURL(outputFileURL as CFURL, kAudioFileM4AType, &fileFormat, nil, 
				AudioFileFlags.eraseFile.rawValue, &outputFileOpt)
		guard let outputFile = outputFileOpt, err == 0 else  {
			lastNetworkError = "While post-processing video, got a \(err) error from ExtAudioFileCreateWithURL()."
			return
		}
		err = ExtAudioFileSetProperty(outputFile, kExtAudioFileProperty_ClientDataFormat, 
				UInt32(MemoryLayout.size(ofValue: sourceFormat)), &sourceFormat)
		guard err == 0 else  {
			lastNetworkError = "While post-processing video, got a \(err) error from ExtAudioFileSetProperty()."
			return
		}
		let bufList = AudioBufferList.allocate(maximumBuffers: 1)
		bufList[0] = AudioBuffer(mNumberChannels: 2, mDataByteSize: UInt32(audioBuffer.count * 8), mData: 
				audioBuffer.baseAddress)
//		bufList[1] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(audioBuffers.frameLength), mData: 
//				audioBuffers.floatChannelData![1])
		err = ExtAudioFileWrite(outputFile, UInt32(audioBuffer.count), bufList.unsafePointer)
		guard err == 0 else  {
			lastNetworkError = "While post-processing video, got a \(err) error from ExtAudioFileWrite()."
			return
		}
		err = ExtAudioFileDispose(outputFile)
		guard err == 0 else  {
			lastNetworkError = "While post-processing video, got a \(err) error from ExtAudioFileDispose()."
			return
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

		let fileUrl = getProcessedVideoRecordingURL()
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
			self.currentOfferUser = nil
			self.currentListenFile = nil
			self.currentRecordFile = nil
			self.videoUploadInProgress = false
		}
	}
	
// MARK: - List of Completed Songs
	
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
	
	// Songs is always considered to be a comprehensive list of songs on the server; songs on in this list are deleted locally.
	func ingestCompletedVideos(from songs: [MicroKaraokeCompletedSong]) {
		LocalCoreData.shared.performNetworkParsing { context in
			context.pushOpErrorExplanation("Failed to parse Micro Karaoke songs and add to Core Data.")
						
			// Fetch songs from CD that match the ids in the given songs
			let request = NSFetchRequest<MicroKaraokeSong>(entityName: "MicroKaraokeSong")
//			request.predicate = NSPredicate(format: "id IN %@", allSongIDs)
			request.predicate = NSPredicate(value: true)
			let cdSongs = try request.execute()
			let cdSongsDict = Dictionary(cdSongs.map { ($0.id, $0) }, uniquingKeysWith: { (first,_) in first })

			for song in songs {
				let cdSong = cdSongsDict[Int64(song.songID)] ?? MicroKaraokeSong(context: context)
				cdSong.buildFromV3(context: context, v3Object: song)
			}
			
			// Delete songs in db that aren't in results.
			let serverSongIDs = Set(songs.map( { $0.songID } ))
			cdSongs.forEach { cdSong in
				if !serverSongIDs.contains(Int(cdSong.id)) {
					context.delete(cdSong)
				}
			}
		}
	}
	
	// Only for moderator users
	func modApproveSong(song: Int64, done: ((String?) -> Void)?) {
		var request = NetworkGovernor.buildTwittarRequest(withPath: "/api/v3/mod/microkaraoke/approve/\(song)")
		NetworkGovernor.addUserCredential(to: &request)
		request.httpMethod = "POST"
		NetworkGovernor.shared.queue(request) { (package: NetworkResponse) in
			var errorString: String?
			if let error = package.getAnyError() {
				errorString = error.getErrorString() 
			}
			else {
				self.getCompletedVideos()
			}
			done?(errorString)
		}
	}
	
// MARK: - Completed Song Download
	// Done fn is: (movieFile: AVPlayerItem?, movieExportURL: URL?, errorString: String?)
	func callDoneDownloadingFn(_ movieFile: AVPlayerItem?, _ movieExportURL: URL?, _ errorString: String?) {
		DispatchQueue.main.async {
			self.doneDownloadingSong?(movieFile, movieExportURL, errorString)
			self.doneDownloadingSong = nil
			self.downloadingVideoForSongID = nil
		}
	}
	
	func downloadCompletedSong(songID: Int64, done: @escaping(AVPlayerItem?, URL?, String?) -> Void) {
		// If we're currently in the process of downloading an song, let it complete.
		guard downloadingVideoForSongID == nil else {
			return
		}
		doneDownloadingSong = done
		downloadingVideoForSongID = String(songID)
		var request = NetworkGovernor.buildTwittarRequest(withPath: "/api/v3/microkaraoke/song/\(songID)", query: [])
		NetworkGovernor.addUserCredential(to: &request)
		NetworkGovernor.shared.queue(request) { (package: NetworkResponse) in
			if let error = package.getAnyError() {
				self.callDoneDownloadingFn(nil, nil, error.getErrorString())
			}
			else if let data = package.data {
				do {
					let manifest = try Settings.v3Decoder.decode(MicroKaraokeSongManifest.self, from: data)
					self.downloadVideo(in: manifest, at: 0)
				} catch 
				{
					NetworkLog.error("Failure parsing Micro Karaoke song.", ["Error" : error, "URL" : request.url as Any])
					self.callDoneDownloadingFn(nil, nil, error.localizedDescription)
				} 
			}
			else {
				self.callDoneDownloadingFn(nil, nil, "Couldn't load data from server.")
			}
		}
	}
	
	// Calls itself 'recursively' for each video clip in the song. But, since it uses an async callback, it's not
	// real recursion.
	func downloadVideo(in manifest: MicroKaraokeSongManifest, at index: Int) {
		guard index < manifest.snippetVideoURLs.count else {
			self.callDoneDownloadingFn(nil, nil, "Encountered bad song clip index.")
			return
		}
		let videoURL = manifest.snippetVideoURLs[index]
		songDownloadProgress = Float(index) / Float(manifest.snippetVideoURLs.count)
		
		guard var localPath = try? FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
				.appendingPathComponent("finishedSongParts_\(manifest.songID)") else {
			self.callDoneDownloadingFn(nil, nil, "Could not access local temp directory.")
			return		
		}
		try? FileManager.default.createDirectory(at: localPath, withIntermediateDirectories: true)
		localPath.appendPathComponent("\(index).mp4")
		if FileManager.default.fileExists(atPath: localPath.path) {
			print("Already have video clip \(index)")
			if index + 1 >= manifest.snippetVideoURLs.count {
				self.downloadSongAudio(in: manifest)
			}
			else {
				self.downloadVideo(in: manifest, at: index + 1)
			}
			return
		}

		var request = NetworkGovernor.buildTwittarRequest(withURL: videoURL)
		NetworkGovernor.addUserCredential(to: &request)
		NetworkGovernor.shared.queue(request) { (package: NetworkResponse) in
			if let error = package.getAnyError() {
				self.callDoneDownloadingFn(nil, nil, error.getErrorString())
			}
			else if let data = package.data {
				do {
					try data.write(to: localPath)
					if index + 1 >= manifest.snippetVideoURLs.count {
						self.downloadSongAudio(in: manifest)
					}
					else {
						self.downloadVideo(in: manifest, at: index + 1)
					}
				}
				catch {
					self.lastNetworkError = error.localizedDescription
					self.callDoneDownloadingFn(nil, nil, error.localizedDescription)
				}
			} else {
				self.callDoneDownloadingFn(nil, nil, "Couldn't load video file from server.")
			}
		}
	}
	
	func downloadSongAudio(in manifest: MicroKaraokeSongManifest) {
		guard var localPath = try? FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
				.appendingPathComponent("finishedSongParts_\(manifest.songID)") else {
			self.callDoneDownloadingFn(nil, nil, "Could not access local temp directory.")
			return
		}
		songDownloadProgress = 1.0
		localPath.appendPathComponent("karaokeaudio.mp3")
		if FileManager.default.fileExists(atPath: localPath.path) {
			print("Already have karaoke audio song file.")
			assembleCompletedVideo(from: manifest)
			return
		}
		let request = NetworkGovernor.buildTwittarRequest(withURL: manifest.karaokeMusicTrack)
		NetworkGovernor.shared.queue(request) { (package: NetworkResponse) in
			if let error = package.getAnyError() {
				self.callDoneDownloadingFn(nil, nil, error.getErrorString())
			}
			else if let data = package.data {
				do {
					try data.write(to: localPath)
					self.assembleCompletedVideo(from: manifest)
				}
				catch {
					self.callDoneDownloadingFn(nil, nil, error.localizedDescription)
				}
			} else {
				self.callDoneDownloadingFn(nil, nil, "Couldn't load sound file from server.")
			}
			self.offerDownloadInProgress = false
		}
	}
	
	let compositionLandscapeSize: CGSize = CGSize(width: 1280, height: 720)
	let compositionPortraitSize: CGSize = CGSize(width: 720, height: 1280)
	let compositonAudioRate: CMTimeScale = 44100
	var showFinalVideoWhenDone = true
	
	// Once we have all the parts, assemble the video
	func assembleCompletedVideo(from manifest: MicroKaraokeSongManifest) {
		do {
			let comp = AVMutableComposition()
			let assetDir = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
					.appendingPathComponent("finishedSongParts_\(manifest.songID)")
			
			var insertTimePoint = CMTime(seconds: 0, preferredTimescale: compositonAudioRate)
			let videoTrack = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
			let audioTrack = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!
			let audioTrack2 = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!
			
			// Prep the composition for use
//			comp.naturalSize = manifest.portraitMode ? CGSize(width: 1080, height: 1920) : CGSize(width: 1920, height: 1080)
			comp.naturalSize = manifest.portraitMode ? compositionPortraitSize : compositionLandscapeSize
			var instructions = [AVMutableVideoCompositionInstruction]()
			
			for index in 0..<manifest.snippetVideoURLs.count {
//			for index in 0..<1 {
				print("adding clip \(index) to video")
				let pathExtension = manifest.snippetVideoURLs[index].pathExtension
				let videoAsset = AVURLAsset(url: assetDir.appendingPathComponent("\(index).\(pathExtension)"))
				let duration = CMTime(seconds: manifest.snippetDurations[index], preferredTimescale: compositonAudioRate) 
				let timeRange = CMTimeRange(start: .zero, duration: duration)
				if let videoAssetVideo = videoAsset.tracks(withMediaType: .video).first {
					try videoTrack.insertTimeRange(timeRange, of: videoAssetVideo, at: insertTimePoint)
					
					// naturalSize appears to not include the transform. So, get the larger axis, scale to that, and trust
					// that applying preferredTransform will set things right
					let scaleFactor = max(comp.naturalSize.width, comp.naturalSize.height) /
							max(videoAssetVideo.naturalSize.height, videoAssetVideo.naturalSize.width)					
					let transform = videoAssetVideo.preferredTransform.scaledBy(x: scaleFactor, y: scaleFactor )
					
					let transformLayerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
					transformLayerInstruction.setTransform(transform, at: insertTimePoint)
					let videoCompositorInstructions = AVMutableVideoCompositionInstruction()
					videoCompositorInstructions.timeRange = CMTimeRange(start: insertTimePoint, duration: duration)
					videoCompositorInstructions.layerInstructions = [transformLayerInstruction]
					instructions.append(videoCompositorInstructions)
				}
				if let karaokeSinging = videoAsset.tracks(withMediaType: .audio).first {
					try audioTrack.insertTimeRange(timeRange, of: karaokeSinging, at: insertTimePoint)
				}				
				insertTimePoint = insertTimePoint + duration
			}
			
			let audioAsset = AVURLAsset(url: assetDir.appendingPathComponent("karaokeaudio.mp3"))
			if let backingAudio = audioAsset.tracks(withMediaType: .audio).first {
				// 100ms is my dead reckoning of the audio delay factor for the recorded clips
				let offset = CMTime(seconds: 0.000, preferredTimescale: 44100)
//				let offset = CMTime(seconds: 0.250, preferredTimescale: compositonAudioRate)
				let timeRange = CMTimeRange(start: .zero, duration: insertTimePoint - offset)
				try audioTrack2.insertTimeRange(timeRange, of: backingAudio, at: offset)
			}

			// Video Compositor is intended to be used to describe how to combine multiple video sources into
			// output frames, but we're just using it to describe the rotation matrix to apply to each clip in the video.
			let videoCompositor = AVMutableVideoComposition()
			videoCompositor.instructions = instructions
			videoCompositor.renderSize = comp.naturalSize
			videoCompositor.frameDuration = CMTimeMake(value: 1, timescale: 30)
			
			let audioMix = AVMutableAudioMix()
			let volumeParam = AVMutableAudioMixInputParameters(track: audioTrack2)
			volumeParam.setVolume(1.0, at: CMTime.zero)
			audioMix.inputParameters.append(volumeParam)
			let vp2 = AVMutableAudioMixInputParameters(track: audioTrack)
			vp2.setVolume(1.0, at: CMTime.zero)
			audioMix.inputParameters.append(vp2)
			
			let playerItem = AVPlayerItem(asset: comp)
			playerItem.audioMix = audioMix
			playerItem.videoComposition = videoCompositor
	
			// If TRUE, we play the video for hte user as normal. If false, we open the share sheet. 
			if showFinalVideoWhenDone {
				DispatchQueue.main.async {
					self.doneDownloadingSong?(playerItem, nil, nil)
					self.doneDownloadingSong = nil
					self.downloadingVideoForSongID = nil
				}
			}
			else {
				// This block is used to export the finished video to a single mov file
				let finishedVideo = assetDir.appendingPathComponent("Song_\(manifest.songID).mov")
				try? FileManager.default.removeItem(at: finishedVideo)
				let export = AVAssetExportSession(asset: comp, presetName: AVAssetExportPresetHighestQuality)!
				export.audioMix = audioMix
				export.outputURL = finishedVideo
				export.videoComposition = videoCompositor
				export.outputFileType = AVFileType.mov
				export.exportAsynchronously {
					switch export.status {
						case .completed:
							print("woot")
							DispatchQueue.main.async {
								self.doneDownloadingSong?(nil, finishedVideo, nil)
								self.doneDownloadingSong = nil
								self.downloadingVideoForSongID = nil
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
			callDoneDownloadingFn(nil, nil, error.localizedDescription)
		}
	}
	
// MARK: - Processing Video Clip for Upload
	let monoFormat = AVAudioFormat(standardFormatWithSampleRate: 44100.0, channels: 1)!
	let stereoFormat = AVAudioFormat(standardFormatWithSampleRate: 44100.0, channels: 2)!
	let kernelLength = 16

	func postProcessRecordedClip(done: @escaping (URL?) -> Void) {
		do {
			guard let currentListenFile = currentListenFile else {
				throw KrakenError("Missing required file for video post-processing.")
			}
			let voiceSamples = try getPCMBufferForAsset(file: getVideoRecordingURL(), format: monoFormat)
			let backingSamples = try getPCMBufferForAsset(file: currentListenFile, format: stereoFormat)
			
			let (outputBuffer, sampleDelay) = applyAudioFilters(voiceSamples: voiceSamples, backingSamples: backingSamples)

			// 
			try writeProcessedAudioFile(sourceBuf: outputBuffer)
			try composeUploadVideo(delay: sampleDelay, done: done)
		}
		catch {
			lastNetworkError = error.localizedDescription
		}
	}
	
	func getPCMBufferForAsset(file: URL, format: AVAudioFormat, deinterleave: Bool = true) throws -> AVAudioPCMBuffer {
		let asset = AVURLAsset(url: file)
		let assetAudioTrack = asset.tracks(withMediaType: .audio).first!
//		let assetAudioTrack = try await asset.loadTracks(withMediaType: .audio).first!
		let reader = try AVAssetReader(asset: asset)
		let trackOutput = AVAssetReaderTrackOutput(track: assetAudioTrack, outputSettings:  [ AVFormatIDKey : kAudioFormatLinearPCM ])
		reader.add(trackOutput)
		reader.startReading()

		// MAKE A PCM BUFFER
		let dur = asset.duration
		let samples = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: UInt32(dur.value * 44100 / Int64(dur.timescale)))!
		samples.frameLength = samples.frameCapacity
		var samplesWritten = 0
		while let buffer = trackOutput.copyNextSampleBuffer() {
			try buffer.dataBuffer?.withUnsafeMutableBytes { bytes in
				if format.channelCount == 1 {
					let _ = bytes.withMemoryRebound(to: Float.self) { floatValues in
						memcpy(samples.floatChannelData![0] + samplesWritten, floatValues.baseAddress, bytes.count)
					}
					samplesWritten += buffer.numSamples
				}
				else if !deinterleave {
					let _ = bytes.withMemoryRebound(to: LPCMStereoFrame.self) { frameValues in
						memcpy(samples.floatChannelData![0] + samplesWritten * 2, frameValues.baseAddress, bytes.count)
					}
					samplesWritten += buffer.numSamples
				}
				else {
					bytes.withMemoryRebound(to: LPCMStereoFrame.self) { stereoValues in
						for index in 0..<stereoValues.count {
							samples.floatChannelData![0][samplesWritten] = stereoValues[index].left
							samples.floatChannelData![1][samplesWritten] = stereoValues[index].right
							samplesWritten += 1
						}
					}
				}
			}
		}
		return samples
	}

	// Return value is the processed audio buffer plus the delay, in audio samples between backing and voice, where
	// voice[delay] ~== backing[0]
	func applyAudioFilters(voiceSamples: AVAudioPCMBuffer, backingSamples: AVAudioPCMBuffer) -> (AVAudioPCMBuffer, Int) {
		let voice = UnsafeBufferPointer<Float>(start: voiceSamples.floatChannelData![0], count: Int(voiceSamples.frameLength))
		let backingKernel = UnsafeBufferPointer<Float>(start: backingSamples.floatChannelData![0], count: Int(backingSamples.frameLength) - 20000)
		let backing = UnsafeBufferPointer<Float>(start: backingSamples.floatChannelData![0], count: Int(backingSamples.frameLength))

		// root mean square to estimate gain
		let voiceRMS = rootMeanSquare(buf: voice)
		let backingRMS = rootMeanSquare(buf: backing)
		let gain = backingRMS / voiceRMS
		
		// Level match the voice track to match the backing volume
		let v2 = UnsafeMutableBufferPointer<Float>(start: voiceSamples.floatChannelData![0], count: Int(voiceSamples.frameLength))
		for index in 0..<v2.count {
			v2[index] = v2[index] * gain
		}

		// Correlate
		let result = vDSP.correlate(voice, withKernel: backingKernel)
		var maxVal: Float = 0.0
		var maxIndex = 0
		for index in 0..<result.count {
			if result[index] > maxVal {
				maxVal = result[index]
				maxIndex = index
			}
		}

// TEST modify maxIndex
maxIndex = Int(voiceSamples.frameLength - backingSamples.frameLength)
maxIndex = max(maxIndex, 0)
		
		if maxIndex < kernelLength { maxIndex = kernelLength }
		let minOutputSize = Int(min(voiceSamples.frameLength - UInt32(maxIndex), backingSamples.frameLength))
		var outputArray = [Float]()
		
		for index in 0..<kernelLength {
			outputArray.append(voice[maxIndex + index])
		}
		var squelch: Float = 0.0
		var localVoiceRMS: Float = voiceRMS
		var localBackingRMS: Float = backingRMS
		var diff: Float = 0.0
		var diffRing = Array(repeating: Float(0.0), count: kernelLength * 2)
		for sampleIndex in kernelLength..<(minOutputSize - kernelLength) {
			
			// RMS
			localVoiceRMS += voice[sampleIndex + maxIndex + kernelLength] - voice[sampleIndex + maxIndex - kernelLength]
			localBackingRMS += backing[sampleIndex + kernelLength] - backing[sampleIndex - kernelLength]
//			var localGain = (localVoiceRMS / localBackingRMS).clamped(to: 0.2...5)
			let localGain: Float = 1.0
			let newValue = abs(abs(voice[sampleIndex + maxIndex + kernelLength]) - abs(backing[sampleIndex + kernelLength]) *
					 localGain)
			let ring = sampleIndex % 32
			diff += newValue - diffRing[ring]
			diffRing[ring] = newValue
//			let localGain = backingRMS / voiceRMS
			
			squelch += abs(diff) > backingRMS * 20 ? 0.005 : -0.005
			squelch = min(squelch, 1.0)
			squelch = max(squelch, 0.0)
//			if sampleIndex % 1000 == 0 {
//				print("diff: \(diff) squelch: \(squelch)")
//			}
//			outputArray.append(voice[sampleIndex + maxIndex] * squelch)
			outputArray.append(voice[sampleIndex + maxIndex])
			
			// Add a bit of reverb; this is a poor reverb, but easy to do
			if sampleIndex > 44 {
//				outputArray[outputArray.count - 1] += outputArray[outputArray.count - 44] * 0.5
			}
			
			// This line instead adds in some backing track
//			outputArray.append(voice[sampleIndex + maxIndex] * squelch + backing[sampleIndex] * 0.3)
//			outputArray[outputArray.count - 1] += backing[sampleIndex] * 0.3			
		}
		for index in 0..<kernelLength {
			outputArray.append(voice[maxIndex + index])
		}
//		print("voiceLen: \(voiceSamples.frameLength) backingLen: \(backingSamples.frameLength) output: \(outputArray.count) delay: \(maxIndex) min: \(minOutputSize)")

		// Copy to output AVAudioPCMBuffer
		let outputBuffer = AVAudioPCMBuffer(pcmFormat: monoFormat, frameCapacity: UInt32(backing.count))!
		outputBuffer.frameLength = outputBuffer.frameCapacity
		for index in 0..<minOutputSize {
			outputBuffer.floatChannelData![0][index] = outputArray[index] // + backing[index] * 0.5
		}
		
		return (outputBuffer, maxIndex)
	}
	
	func rootMeanSquare(buf: UnsafeBufferPointer<Float>, gain: Float = 1.0) -> Float {
		var value: Float = 0.0
		for sample in buf {
			let gainSample = gain * sample
			value += gainSample * gainSample
		}
		let mean = value / Float(buf.count)
		let result = sqrt(mean)
		print("RMS: \(result)")
		return result
	}

	func writeProcessedAudioFile(sourceBuf: AVAudioPCMBuffer) throws {
		let outputURL = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
							.appendingPathComponent("processedAudio.wav")
		
		var sourceFormat = AudioStreamBasicDescription(mSampleRate: 44100, mFormatID: kAudioFormatLinearPCM, mFormatFlags: kAudioFormatFlagIsFloat, 
				mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4, mChannelsPerFrame: 1, mBitsPerChannel: 32, mReserved: 0)
		var fileFormat = AudioStreamBasicDescription(mSampleRate: 44100, mFormatID: kAudioFormatLinearPCM, 
				mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
				mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4, mChannelsPerFrame: 1, mBitsPerChannel: 32, mReserved: 0)
		
	
		var outputFileOpt: ExtAudioFileRef?
		var err = ExtAudioFileCreateWithURL(outputURL as CFURL, kAudioFileWAVEType, &fileFormat, nil, 
				AudioFileFlags.eraseFile.rawValue, &outputFileOpt)
		guard let outputFile = outputFileOpt, err == 0 else  {
			lastNetworkError = "While post-processing video, got a \(err) error from ExtAudioFileCreateWithURL()."
			return
		}
		err = ExtAudioFileSetProperty(outputFile, kExtAudioFileProperty_ClientDataFormat, 
				UInt32(MemoryLayout.size(ofValue: sourceFormat)), &sourceFormat)
		guard err == 0 else  {
			lastNetworkError = "While post-processing video, got a \(err) error from ExtAudioFileSetProperty()."
			return
		}
		var bufList = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(mNumberChannels: 1, 
				mDataByteSize: sourceBuf.frameLength * UInt32(MemoryLayout<Float>.size), mData: sourceBuf.floatChannelData![0]))
		
		err = ExtAudioFileWrite(outputFile, sourceBuf.frameLength, &bufList)
		guard err == 0 else  {
			lastNetworkError = "While post-processing video, got a \(err) error from ExtAudioFileWrite()."
			return
		}
		err = ExtAudioFileDispose(outputFile)
		guard err == 0 else  {
			lastNetworkError = "While post-processing video, got a \(err) error from ExtAudioFileDispose()."
			return
		}
	}
	
	func composeUploadVideo(delay: Int, done: @escaping (URL?) -> Void) throws {
		let audioURL = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
							.appendingPathComponent("processedAudio.wav")
		let videoAsset = AVURLAsset(url: getVideoRecordingURL())
		let audioAsset = AVURLAsset(url: audioURL)
		let duration = audioAsset.duration 	// All durations for this export match this duration
		
		let comp = AVMutableComposition()
		comp.naturalSize = getCurrentOffer()?.portraitMode == true ? compositionPortraitSize : compositionLandscapeSize
		var instructions = [AVMutableVideoCompositionInstruction]()

		let videoTrack = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
		if let videoAssetVideo = videoAsset.tracks(withMediaType: .video).first {
			let timeRange = CMTimeRange(start: CMTime(value: CMTimeValue(delay), timescale: 44100), duration: duration)
			try videoTrack.insertTimeRange(timeRange, of: videoAssetVideo, at: .zero)
			let scaleFactor = max(comp.naturalSize.width, comp.naturalSize.height) /
					max(videoAssetVideo.naturalSize.height, videoAssetVideo.naturalSize.width)					
			let transform = videoAssetVideo.preferredTransform.scaledBy(x: scaleFactor, y: scaleFactor )
			let transformLayerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
			transformLayerInstruction.setTransform(transform, at: .zero)
			let videoCompositorInstruction = AVMutableVideoCompositionInstruction()
			videoCompositorInstruction.timeRange = CMTimeRange(start: .zero, duration: duration)
			videoCompositorInstruction.layerInstructions = [transformLayerInstruction]
			instructions.append(videoCompositorInstruction)
		}

		let audioTrack = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!
		if let audioAssetAudio = audioAsset.tracks(withMediaType: .audio).first {
			let timeRange = CMTimeRange(start: .zero, duration: duration)
			try audioTrack.insertTimeRange(timeRange, of: audioAssetAudio, at: .zero)
		}

		// Video Compositor is intended to be used to describe how to combine multiple video sources into
		// output frames, but we're just using it to describe the rotation matrix to apply to each clip in the video.
		let videoCompositor = AVMutableVideoComposition()
		videoCompositor.instructions = instructions
		videoCompositor.renderSize = comp.naturalSize
		videoCompositor.frameDuration = CMTimeMake(value: 1, timescale: 30)

		// Export the video
		let finishedVideo = getProcessedVideoRecordingURL()
		try? FileManager.default.removeItem(at: finishedVideo)
		let export = AVAssetExportSession(asset: comp, presetName: AVAssetExportPreset1280x720)!
		export.outputURL = finishedVideo
		export.outputFileType = AVFileType.mp4
		export.videoComposition = videoCompositor
		export.exportAsynchronously {
			switch export.status {
				case .completed:
					done(finishedVideo)
				case .failed:
					self.lastNetworkError = ("Failed: \(export.error as Any)")
				default:
					break
			}
		}
	}
}

// Struct describing a frame of stereo Linear PCM audio
fileprivate struct LPCMStereoFrame {
	var left: Float
	var right: Float
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
	/// Always TRUE unless the user is a mod, in which case will be FALSE for songs that have all the necessary clips recorded but require mod approval to publish.
	var modApproved: Bool
	/// When the song's clips were last modified. Usually the time the final snippet gets uploaded (although 'final' means '30th out of 30'
	/// and not 'the one at the end of the song'). However, clips can get deleted via moderation, causing the server to re-issue an offer
	/// for the deleted clip, which may change the completion time. NIL if song isn't complete
	var completionTime: Date?
	/// TRUE if the current user contributed to the song
	var userContributed: Bool
}

public struct MicroKaraokeSongManifest: Codable {
	/// Each song the server works on collecting (via piecing together multiple song clips from users) gets an ID
	var songID: Int
	/// TRUE if all the clips for this song must be recorded in portrait mode. FALSE if they all need to be landscape.
	var portraitMode: Bool
	/// The video snippets that make up the song. Some snippets may be 'filler', such as for a song's instrumental section.
	var snippetVideoURLs: [URL]
	/// How long each snippet should be, in seconds.
	var snippetDurations: [Double]
	/// The karaoke audio for the song
	var karaokeMusicTrack: URL
}
