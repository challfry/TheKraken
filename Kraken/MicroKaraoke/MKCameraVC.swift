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
	
	override func viewDidLoad() {
        super.viewDidLoad()
		try? configureAVSession()
		
		// CoreMotion is our own device motion manager, a singleton for the whole app. We use it here to get device
		// orientation without allowing our UI to actually rotate.
		NotificationCenter.default.addObserver(self, selector: #selector(CameraViewController.deviceRotationNotification), 
				name: CoreMotion.OrientationChanged, object: nil)
						      	        
	}

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		try? AVAudioSession.sharedInstance().setCategory(AVAudioSession.Category.playAndRecord, options: [.defaultToSpeaker, .mixWithOthers])
		try? AVAudioSession.sharedInstance().setActive(true)
		CoreMotion.shared.start(forClient: "MicroKaraokeRecord", updatesPerSec: 2)
		cameraPreview?.frame = cameraView.bounds
		countdownLabel.isHidden = true
		
		UIApplication.shared.isIdleTimerDisabled = true
		recordButton.isEnabled = false
//		rotateCameraViewsForDeviceRotation(with: nil)

		lyricLabel.text = MicroKaraokeDataManager.shared.getCurrentOffer()?.lyrics
	}
	
	override func viewDidAppear(_ animated: Bool) {
    	super.viewDidAppear(animated)		
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
	
	override var shouldAutorotate: Bool {
		return false
	}
	
	override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
		return .portrait
	}
	
	func preferredInterfaceOrientationForPresentation() -> UIInterfaceOrientation {
		return UIInterfaceOrientation.portrait
	}
	
	// This VC doesn't actually rotate, it technically stays in Portrait all the time. However, it 
	// rotates a bunch of its UI widgets via affine transforms when device rotation is detected. Also,
	// the notification this responds to is a custom app notification, not a system one.
	@objc func deviceRotationNotification(_ notification: Notification) {
		NSLog("rotation")
	}

	@IBAction func listenButtonHit() {
		do {
			if let player = soundPlayer {
				player.stop()
				audioPlayerDidFinishPlaying(player, successfully: false)
				return
			}
//			guard let songclip = Bundle.main.url(forResource: "Shake It Off/3/listen", withExtension: "mp3") else { return }
//			guard let songclip = Bundle.main.url(forResource: "Still Alive/3/listen", withExtension: "mp3") else { return }
			if let vocalSoundURL = MicroKaraokeDataManager.shared.currentListenFile {
				soundPlayer = try AVAudioPlayer(contentsOf: vocalSoundURL) 
				soundPlayer?.play()
				soundPlayer?.delegate = self
				listenButton.setTitle("Stop", for: .normal)
				recordButton.isEnabled = false
			}
		} catch let error as NSError {
			print(error.description)
		}
	}
	
	@IBAction func recordButtonHit() {
		do {
			if countdownLabel.isHidden == false {
				countdownTimer?.invalidate()
				countdownTimer = nil
				countdownLabel.isHidden = true
				listenButton.isEnabled = true
				recordButton.setTitle("Record", for: .normal)
				return
			}
			if let player = soundPlayer {
				player.stop()
				audioPlayerDidFinishPlaying(player, successfully: false)
				return
			}
			listenButton.isEnabled = false
			recordButton.setTitle("Stop", for: .normal)
			secondsOnTimer = 3
			countdownLabel.text = "\(self.secondsOnTimer)"
			self.countdownLabel.isHidden = false
			
//			guard let songclip = Bundle.main.url(forResource: "Still Alive/3/record", withExtension: "mp3") else { return }
			if let karaokeSoundURL = MicroKaraokeDataManager.shared.currentRecordFile {
				let promptPlayer = try AVAudioPlayer(contentsOf: karaokeSoundURL)
				soundPlayer = promptPlayer
				promptPlayer.prepareToPlay() 
				promptPlayer.delegate = self
				promptPlayer.setVolume(0.05, fadeDuration: 0.0)
			}

			//  Testing shows this doesn't actually make a video that's quite as long as the limit.
			// videoOutput.maxRecordedDuration = CMTime(seconds: promptPlayer.duration, preferredTimescale: 44100)
		}
		catch {
			print (error)
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
//					Timer.scheduledTimer(withTimeInterval: 4.0, repeats: false) { timer in 
//						self.stopRecording()
//					}
				} catch let error as NSError {
					print(error.description)
				}
			}
		}
	}

	@IBAction func closeButtonTapped() {
		performSegue(withIdentifier: "cancelledMKRecording", sender: nil)
	}
	
	
	// Sets up the avSession, with initial settings. Should only run this once per view instantion, at viewDidLoad time. 
	func configureAVSession() throws {
		#if targetEnvironment(simulator)
		return
		#else
		
		captureSession.sessionPreset = .high

		// Find our initial camera, and set up our array of camera devices
//		discoverer = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera], mediaType: .video, position: .unspecified)
// TODO: must guard
		cameraDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
		haveLockOnDevice = false
		do {
			try cameraDevice?.lockForConfiguration()
			haveLockOnDevice = true
		}
		catch {
			haveLockOnDevice = false
		}
		
		guard let audioDevice = AVCaptureDevice.default(for: .audio) else {
			throw KrakenError("No default microphone found; can't record audio.")
		}
//let discover = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInMicrophone], mediaType: .audio, position: .unspecified)
//print("audio: \(discover.devices)")
		self.audioDevice = audioDevice
			
		captureSession.beginConfiguration()
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
		}

		cameraPreview = AVCaptureVideoPreviewLayer(session: captureSession)
		cameraPreview!.videoGravity = AVLayerVideoGravity.resizeAspectFill
		cameraPreview!.connection?.videoOrientation = AVCaptureVideoOrientation.portrait
		cameraView.layer.insertSublayer(cameraPreview!, at: 0)
		captureSession.commitConfiguration()
		
//		print("Connections: \(captureSession.connections)")
		
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
		videoOutput.startRecording(to: fileUrl, recordingDelegate: self)
	}
	
	func stopRecording() {
	    videoOutput.stopRecording()
	}

	
// MARK: AVAudioPlayerDelegate
	// Gets called when the audio reaches the end. Does not get called if stop is tapped.
	func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully: Bool) {
		if successfully {
			listenedOnce = true
			guideLabel.text = "2. Listen to the song again if you need to. When you're ready, tap Record and sing your heart out."
		}
		else {
			recordingStoppedEarly = true
		}
		soundPlayer = nil
		listenButton.isEnabled = true
		recordButton.isEnabled = listenedOnce
		listenButton.setTitle("Listen", for: .normal)
		recordButton.setTitle("Record", for: .normal)
		stopRecording()
	}
	
// MARK: AVCaptureFileOutputRecordingDelegate
	func fileOutput(_ output: AVCaptureFileOutput,  didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection],
    		error: Error?) {
		if !recordingStoppedEarly {
			performSegue(withIdentifier: "playbackRecording", sender: outputFileURL)
		}
//		let activityViewController = UIActivityViewController(activityItems: [outputFileURL], applicationActivities: nil)
//		present(activityViewController, animated: true, completion: {})
	}
	
	override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
		if segue.identifier == "playbackRecording", let videoURL = sender as? URL, let destVC = segue.destination as? ReviewClipViewController {
			destVC.clipURL = videoURL
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
