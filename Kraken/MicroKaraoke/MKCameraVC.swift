//
//  MKCameraVC.swift
//  Kraken
//
//  Created by Chall Fry on 1/23/24.
//  Copyright © 2024 Chall Fry. All rights reserved.
//

import Foundation
import AVFoundation
import CoreMotion
import MediaPlayer

class MKCameraViewController: UIViewController, AVAudioPlayerDelegate, AVCaptureFileOutputRecordingDelegate {
	@IBOutlet weak var cameraView: UIView!
	@IBOutlet weak var countdownLabel: UILabel!
	@IBOutlet weak var lyricRoundRect: UIView!
		@IBOutlet weak var lyricLabel: UILabel!
	@IBOutlet weak var guideLabel: UILabel!
	@IBOutlet weak var listenButton: UIButton!
	@IBOutlet weak var recordButton: UIButton!
	@IBOutlet weak var rotationDialogView: MKCameraRoundedRectView!
	
	// Props we need to run the camera
	var captureSession = AVCaptureSession()
	var cameraDevice: AVCaptureDevice?					// The currently active device
	var haveLockOnDevice: Bool = false					// TRUE if we have a lock on cameraDevice and can config it
	var cameraInput: AVCaptureDeviceInput?
	var cameraPreview: AVCaptureVideoPreviewLayer?
	var discoverer: AVCaptureDevice.DiscoverySession?
	
	// Props we need for the mic input
	var audioDevice: AVCaptureDevice?
	var audioInput: AVCaptureDeviceInput?
	
	// Props we need for the recording
	var videoOutput = AVCaptureMovieFileOutput()
	var recordingStoppedEarly = false
		
	var soundPlayer: AVAudioPlayer?
	var listenedOnce: Bool = false			// TRUE once the user listens to the cue track at least once.
	var countdownTimer: Timer?
	var secondsOnTimer: Int = 3
	var landscapeRecording = false

// MARK: -	
	override func viewDidLoad() {
        super.viewDidLoad()
        landscapeRecording = MicroKaraokeDataManager.shared.getCurrentOffer()?.portraitMode == false
		(UIApplication.shared.delegate as? AppDelegate)?.makeThisVCLandscape = landscapeRecording
		configureAVSession()
		
		// CoreMotion is our own device motion manager, a singleton for the whole app. We use it here to get device
		// orientation without allowing our UI to actually rotate.
		NotificationCenter.default.addObserver(self, selector: #selector(MKCameraViewController.deviceRotationNotification), 
				name: CoreMotion.OrientationChanged, object: nil)
	}

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		try? AVAudioSession.sharedInstance().setCategory(AVAudioSession.Category.playAndRecord, mode: .voiceChat, options: 
				[.mixWithOthers, .allowBluetoothA2DP])
		try? AVAudioSession.sharedInstance().setActive(true)
		CoreMotion.shared.start(forClient: "MicroKaraokeRecord", updatesPerSec: 2)
		cameraPreview?.frame = cameraView.bounds
		countdownLabel.isHidden = true
		
		UIApplication.shared.isIdleTimerDisabled = true
		recordButton.isEnabled = false

		lyricLabel.text = MicroKaraokeDataManager.shared.getCurrentOffer()?.lyrics
		rotationDialogView.isHidden = true
	}
	
	override func viewDidAppear(_ animated: Bool) {
    	super.viewDidAppear(animated)	
	}

	override func viewWillDisappear(_ animated: Bool) {
		(UIApplication.shared.delegate as? AppDelegate)?.makeThisVCLandscape = false
		super.viewWillDisappear(animated)
	}
	
	override func viewDidDisappear(_ animated: Bool) {
    	super.viewDidDisappear(animated)
		CoreMotion.shared.stop(client: "MicroKaraokeRecord")
		if haveLockOnDevice {
			cameraDevice?.unlockForConfiguration()
		}
		captureSession.stopRunning()
		UIApplication.shared.isIdleTimerDisabled = false
		try? AVAudioSession.sharedInstance().setActive(false)
	}
	
// MARK: - Navigation
	// This is the unwind segue for when the user taps Retry from the Review Clip view
	@IBAction func retryMKRecording(unwindSegue: UIStoryboardSegue) {
		setButtonStates()
	}
		
// MARK: - Rotation	
	// DEVICE rotation angle: 0 is portrait, then clockwise. The UI counter-rotates relative to the device, so when
	// the device is at 90 degrees, the UI is at 270 degrees.
	var deviceRotationAngle: Int = 0	

	override var shouldAutorotate: Bool {
		return true
	}
	
	override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
		if landscapeRecording {
			return [.landscapeRight]
		}
		else {
			return .portrait
		}
	}
	
	func preferredInterfaceOrientationForPresentation() -> UIInterfaceOrientation {
		if landscapeRecording {
			return .landscapeRight
		}
		else {
			return .portrait
		}
	}
	
	// This VC doesn't actually rotate, it technically stays in Portrait all the time. However, it 
	// rotates a bunch of its UI widgets via affine transforms when device rotation is detected. Also,
	// the notification this responds to is a custom app notification, not a system one.
	@objc func deviceRotationNotification(_ notification: Notification) {
		handleDeviceRotation()
	}
	
	func handleDeviceRotation() {		
		var dialogRotationAngle: Int = 0
		var isLandscape = false
		switch CoreMotion.shared.currentDeviceOrientation {
			case .portrait, .faceUp, .unknown: dialogRotationAngle = 0
			case .landscapeLeft: dialogRotationAngle = 90; isLandscape = true
			case .landscapeRight: dialogRotationAngle = -90; isLandscape = true
			case .portraitUpsideDown, .faceDown: dialogRotationAngle = 180
			default: dialogRotationAngle = 0
		}
		
		if landscapeRecording {
			if deviceRotationAngle == 0 {
				deviceRotationAngle = 270	// Initial state for landscape, where 'up' is when the phone is turned to the left.
			}
			dialogRotationAngle += deviceRotationAngle
		}
		
		if isLandscape && !landscapeRecording || !isLandscape && landscapeRecording {
			self.rotationDialogView.isHidden = false
			rotationDialogView.alpha = 0.0
			UIView.animate(withDuration: 0.5) {
				self.rotationDialogView.alpha = 1.0
			}
			let rotationDialogXform = CGAffineTransform(rotationAngle: CGFloat.pi * CGFloat(dialogRotationAngle) / 180.0)
			rotationDialogView.transform = rotationDialogXform
			stopRecording(false)
		}
		else {
			UIView.animate(withDuration: 0.5, animations: {	self.rotationDialogView.alpha = 0.0 }, 
					completion: { completed in 
					self.rotationDialogView.isHidden = true
					self.setButtonStates()
					})
		}
		
		if landscapeRecording {
			if CoreMotion.shared.currentDeviceOrientation == .landscapeLeft && deviceRotationAngle != 270 {
				let rootViewXform = CGAffineTransform(rotationAngle: CGFloat.pi * CGFloat(0) / 180.0)
				UIView.animate(withDuration: 0.5) { self.cameraView.transform = rootViewXform }
				cameraPreview?.connection?.videoOrientation = AVCaptureVideoOrientation.landscapeRight
				videoOutput.connections.forEach {
					if $0.isVideoOrientationSupported {
						$0.videoOrientation = .landscapeRight
					}
				}
				deviceRotationAngle = 270
			}
			else if CoreMotion.shared.currentDeviceOrientation == .landscapeRight && deviceRotationAngle != 90 {
				let rootViewXform = CGAffineTransform(rotationAngle: CGFloat.pi * CGFloat(180) / 180.0)
				UIView.animate(withDuration: 0.5) { self.cameraView.transform = rootViewXform }
				cameraPreview?.connection?.videoOrientation = AVCaptureVideoOrientation.landscapeLeft
				videoOutput.connections.forEach {
					if $0.isVideoOrientationSupported {
						$0.videoOrientation = .landscapeLeft
					}
				}
				deviceRotationAngle = 90
			}
		}
		setButtonStates()
		cameraPreview?.frame = cameraView.bounds
	}
	
	override func viewDidLayoutSubviews() {
		super.viewDidLayoutSubviews()
		if landscapeRecording && deviceRotationAngle == 0 {
			handleDeviceRotation()
		}
	}	
	
// MARK: - Buttons
	func setButtonStates() {
		if !rotationDialogView.isHidden {
			// Disable all until device rotated
			listenButton.isEnabled = false
			recordButton.isEnabled = false
			listenButton.setTitle("Listen", for: .normal)
			recordButton.setTitle("Record", for: .normal)
		}
		else if !countdownLabel.isHidden || videoOutput.isRecording {
			// Recording, or about to record. Disable listen, record button should be renamed 'stop'.
			listenButton.isEnabled = false
			recordButton.isEnabled = true
			listenButton.setTitle("Listen", for: .normal)
			recordButton.setTitle("Stop", for: .normal)
		}
		else if let _ = soundPlayer {
			// Listing to the voice clip. Listen button is renamed 'stop'. Cannot record while listening.
			listenButton.isEnabled = true
			recordButton.isEnabled = false
			listenButton.setTitle("Stop", for: .normal)
			recordButton.setTitle("Record", for: .normal)
		}
		else {
			// Initial state, except record enables once user has lietened to the clip once.
			listenButton.isEnabled = true
			recordButton.isEnabled = listenedOnce
			listenButton.setTitle("Listen", for: .normal)
			recordButton.setTitle("Record", for: .normal)
		}
	}

	@IBAction func listenButtonHit() {
		do {
			if let player = soundPlayer {
				player.stop()
				audioPlayerDidFinishPlaying(player, successfully: false)
				return
			}
			if let vocalSoundURL = MicroKaraokeDataManager.shared.currentListenFile {
				soundPlayer = try AVAudioPlayer(contentsOf: vocalSoundURL) 
				soundPlayer?.play()
				soundPlayer?.delegate = self
				setButtonStates()
			}
		} catch let error as NSError {
			print(error.description)
		}
	}
	
	@IBAction func recordButtonHit() {
		do {
			if countdownLabel.isHidden == false {
				stopRecording()
				return
			}
			if let _ = soundPlayer {
				stopRecording()
				return
			}
			secondsOnTimer = 4
			countdownLabel.text = "\(self.secondsOnTimer)"
			self.countdownLabel.isHidden = false
			setButtonStates()
			
//			guard let songclip = Bundle.main.url(forResource: "Still Alive/3/record", withExtension: "mp3") else { return }
			if let karaokeSoundURL = MicroKaraokeDataManager.shared.currentRecordFile {
//				let soundAsset = AVAsset(url: karaokeSoundURL)
//				let playerItem = AVPlayerItem(asset: soundAsset, automaticallyLoadedAssetKeys: [.tracks, .duration, .commonMetadata])
//				let promptPlayer = AVPlayer(playerItem: playerItem)
				let promptPlayer = try AVAudioPlayer(contentsOf: karaokeSoundURL)
				self.soundPlayer = promptPlayer
				promptPlayer.delegate = self
				promptPlayer.setVolume(0.2, fadeDuration: 0.0)
				promptPlayer.prepareToPlay()

				//  Testing shows this doesn't actually make a video that's quite as long as the limit.
				// videoOutput.maxRecordedDuration = CMTime(seconds: promptPlayer.duration, preferredTimescale: 44100)
				// videoOutput.maxRecordedDuration = soundAsset.duration + CMTime(value: 22050, timescale: 44100)
			}
		}
		catch {
			print (error)
		}

		var clickPlayer: AVAudioPlayer?
		if let clickFile = Bundle.main.url(forResource: "MetronomeClick", withExtension: "m4a") {
			clickPlayer = try? AVAudioPlayer(contentsOf: clickFile)
			clickPlayer?.prepareToPlay()
			clickPlayer?.play()
		}
			
		// Countdown using the rough tempo of the actual song.
		let countdownInterval = 60.0 / (Double(MicroKaraokeDataManager.shared.getCurrentOffer()?.bpm ?? 60))
		countdownTimer = Timer.scheduledTimer(withTimeInterval: countdownInterval, repeats: true) { timer in
			self.secondsOnTimer = self.secondsOnTimer - 1
			self.countdownLabel.text = "\(self.secondsOnTimer)"
			if self.secondsOnTimer <= 0 {
				self.countdownTimer?.invalidate()
				self.countdownTimer = nil
				self.countdownLabel.isHidden = true
				do {
					// Start recording
					try self.startRecording()
					
					// Play the soundclip
					self.soundPlayer?.play()
//					Timer.scheduledTimer(withTimeInterval: 14.0, repeats: false) { timer in 
//						self.stopRecording()
//					}
				} catch let error as NSError {
					print(error.description)
				}
			}
			else {
				clickPlayer?.play()
			}
		}
	}

	@IBAction func closeButtonTapped() {
		(UIApplication.shared.delegate as? AppDelegate)?.makeThisVCLandscape = false
		performSegue(withIdentifier: "cancelledMKRecording", sender: nil)
	}
	
	// Sets up the avSession, with initial settings. Should only run this once per view instantion, at viewDidLoad time. 
	func configureAVSession() {
		#if targetEnvironment(simulator)
		return
		#else

		captureSession.sessionPreset = .hd1280x720

		// Find our initial camera, and set up our array of camera devices
//		discoverer = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera], mediaType: .video, position: .unspecified)
		cameraDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
		haveLockOnDevice = false
		do {
			try cameraDevice?.lockForConfiguration()
			haveLockOnDevice = true
		
			guard let audioDevice = AVCaptureDevice.default(for: .audio) else {
				throw KrakenError("No default microphone found; can't record audio.")
			}
//			let discover = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInMicrophone], mediaType: .audio, position: .unspecified)
//			print("audio: \(discover.devices)")
			self.audioDevice = audioDevice
				
			captureSession.beginConfiguration()
			defer { captureSession.commitConfiguration() }
			// Add the Front Camera input
			if let input = try? AVCaptureDeviceInput(device: cameraDevice!), captureSession.canAddInput(input) { 
				captureSession.addInput(input)
				cameraInput = input
			}

			// Add audio input
			let audioInput = try AVCaptureDeviceInput(device: audioDevice)
			if captureSession.canAddInput(audioInput) {
				captureSession.addInput(audioInput)
				self.audioInput = audioInput
			} else {
				throw KrakenError("No default microphone found; can't record audio.")
			}

	// TODO: Setup max duration of file output

			if captureSession.canAddOutput(videoOutput) {
				captureSession.addOutput(videoOutput)
				
				videoOutput.connections.forEach {
					if $0.isVideoOrientationSupported {
						$0.videoOrientation = landscapeRecording ? .landscapeRight : .portrait
					}
					if $0.isVideoMirroringSupported {
						$0.isVideoMirrored = true
					}
				}
			}

			let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
			cameraPreview = previewLayer
			previewLayer.videoGravity = AVLayerVideoGravity.resizeAspectFill
			if landscapeRecording {
				previewLayer.connection?.videoOrientation = AVCaptureVideoOrientation.landscapeRight
			}
			else {
				previewLayer.connection?.videoOrientation = AVCaptureVideoOrientation.portrait
			}
			cameraView.layer.insertSublayer(previewLayer, at: 0)
			previewLayer.frame = cameraView.bounds
			
	//		print("Connections: \(captureSession.connections)")
			
		}
		catch {
			haveLockOnDevice = false
			print("Configure AV Session error: \(error)")
			closeButtonTapped()
		}
		
		// Running this from the main thread cause the thread perf checker to complain
		DispatchQueue.global(qos: .background).async {
			self.captureSession.startRunning()
		}
		#endif
	}
	
	func startRecording() throws {
		guard captureSession.isRunning else {
			return
		}
		recordingStoppedEarly = false
		let fileUrl = MicroKaraokeDataManager.shared.getVideoRecordingURL()
		try? FileManager.default.removeItem(at: fileUrl)
		
		//
		videoOutput.movieFragmentInterval = CMTime.invalid
		videoOutput.startRecording(to: fileUrl, recordingDelegate: self)
	}
	
	func stopRecording(_ recordingComplete: Bool = false) {
		recordingStoppedEarly = !recordingComplete
	    videoOutput.stopRecording()
		if !recordingComplete {
			soundPlayer?.stop()
			soundPlayer = nil
			countdownTimer?.invalidate()
			countdownTimer = nil
			countdownLabel.isHidden = true
		}
		setButtonStates()
	}
	
// MARK: AVAudioPlayerDelegate
	// Gets called when the audio reaches the end. Does not get called if stop is tapped.
	func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully: Bool) {
		if successfully {
			listenedOnce = true
			guideLabel.text = "2. Listen to the song again if you need to. When you're ready, tap Record and sing your heart out."
		}
		soundPlayer = nil
		setButtonStates()
		self.stopRecording(successfully)
	}
	
// MARK: AVCaptureFileOutputRecordingDelegate
	func fileOutput(_ output: AVCaptureFileOutput,  didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection],
    		error: Error?) {
		if !recordingStoppedEarly {
			//
			MicroKaraokeDataManager.shared.postProcessRecordedClip() { processedVideoFile in
				if let processedVideoFile = processedVideoFile {
					DispatchQueue.main.async {
						self.performSegue(withIdentifier: "playbackRecording", sender: processedVideoFile)
					}
				}
			}
		}
		setButtonStates()
	}
	
	override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
		if segue.identifier == "playbackRecording", let videoURL = sender as? URL, let destVC = segue.destination as? ReviewClipViewController {
			destVC.clipURL = videoURL
			destVC.rotateView180 = deviceRotationAngle == 90
		}
	}
}

@objc class MKCameraRoundedRectView: UIView {
	override func draw(_ rect: CGRect) {

		let rectPath = UIBezierPath(roundedRect: bounds, cornerRadius: 16)
		rectPath.close()
		let context = UIGraphicsGetCurrentContext()!
		context.setFillColor(UIColor(named: "Camera Preview Label BG")?.cgColor ?? UIColor.clear.cgColor)
		rectPath.fill()

		let borderPath = UIBezierPath(roundedRect: bounds.insetBy(dx: 1.5, dy: 1.5), cornerRadius: 16)
		let borderColor = UIColor(named: "Camera Preview Label FG")
		context.setStrokeColor(borderColor?.cgColor ?? UIColor.clear.cgColor)
		borderPath.lineWidth = 3.0
		borderPath.stroke()

	}
}

@objc class MKRotateDialogRRiew: UIView {
	override func draw(_ rect: CGRect) {

		let rectPath = UIBezierPath(roundedRect: bounds, cornerRadius: 16)
		rectPath.close()
		let context = UIGraphicsGetCurrentContext()!
		context.setFillColor(UIColor(named: "Camera Alert Label BG")?.cgColor ?? UIColor.clear.cgColor)
		rectPath.fill()

		let borderPath = UIBezierPath(roundedRect: bounds.insetBy(dx: 1.5, dy: 1.5), cornerRadius: 16)
		let borderColor = UIColor(named: "Camera Preview Label FG")
		context.setStrokeColor(borderColor?.cgColor ?? UIColor.clear.cgColor)
		borderPath.lineWidth = 3.0
		borderPath.stroke()

	}
}
