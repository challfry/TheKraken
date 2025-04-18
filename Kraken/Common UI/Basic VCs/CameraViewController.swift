//
//  CameraViewController.swift
//  Kraken
//
//  Created by Chall Fry on 8/1/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit
import AVFoundation
import CoreMotion
import MediaPlayer

#if !targetEnvironment(macCatalyst) 
	import ARKit

	struct FaceInfo {
		var faceAnchor: ARFaceAnchor
		var faceRootNode: SCNNode				// The root of the face node tree
	}

#else
	
	@objc(ARSCNView) class ARSCNView: UIView {
		func snapshot() -> UIImage { return UIImage() }
	}
#endif

class CameraViewController: UIViewController {
	@IBOutlet var 	cameraView: UIView!
	@IBOutlet var 		cameraAspectConstraint: NSLayoutConstraint?
	var 				pirateView: ARSCNView?
	@IBOutlet var 	closeButton: UIButton!
	@IBOutlet var 	pirateButton: UIButton!
	@IBOutlet var 	randomizeHatsButton: UIButton!
	@IBOutlet var 	flashButton: UIButton!
	@IBOutlet var 	cameraRotateButton: UIButton!
	
	var verticalSlider: VerticalSlider?
	@IBOutlet var 	leftShutter: UIButton!
	@IBOutlet var 	rightShutter: UIButton!
	
	@IBOutlet var 	capturedPhotoContainerView: UIView!			// Could be UIVisualEffectView
	@IBOutlet var 		capturedPhotoView: UIImageView!
	@IBOutlet var 		capturedPhotoViewHeightConstraint: NSLayoutConstraint!
	@IBOutlet var 		retryButton: UIButton!
	@IBOutlet var 		useButton: UIButton!
	
	@IBOutlet var 	shareButtonParent: UIView!
	@IBOutlet var 		shareButton: UIButton!
	
	// Props we need to run the camera
	var captureSession = AVCaptureSession()
	var cameraDevice: AVCaptureDevice?					// The currently active device
	var haveLockOnDevice: Bool = false					// TRUE if we have a lock on cameraDevice and can config it
	var cameraInput: AVCaptureDeviceInput?
	var cameraPreview: AVCaptureVideoPreviewLayer?
	var photoOutput = AVCapturePhotoOutput()
	var discoverer: AVCaptureDevice.DiscoverySession?
	
	// For using the volume buttons as a shutter.
	var audioSession: AVAudioSession?
	var savedAudioVolume: Float = 0.0
	
	// Props to run AR Mode (Pirate Selfie mode)
#if !targetEnvironment(macCatalyst) 
	var faceAnchors: [FaceInfo] = []
	var allHats: [SCNReferenceNode] = []
	var availableHats: [SCNReferenceNode] = []
	var parrotAssigned = false
	var eyepatch: SCNReferenceNode?
	var parrot: SCNReferenceNode?
#endif

	// Configuration for Segues to use
	var selfieMode: Bool = false						// Set to TRUE to initially use front camera
	var pirateMode: Bool = false
	
	// RESULTS HERE, pull one of these from the unwind segue
	var capturedPhoto: PhotoDataType?

	
// MARK: Methods

    override func viewDidLoad() {
        super.viewDidLoad()
        
		configureAVSession()
		setupGestureRecognizer()
		
		// CoreMotion is our own device motion manager, a singleton for the whole app. We use it here to get device
		// orientation without allowing our UI to actually rotate.
		NotificationCenter.default.addObserver(self, selector: #selector(CameraViewController.deviceRotationNotification), 
				name: CoreMotion.OrientationChanged, object: nil)
				
		// Fix-up Interface Builder values that might get set wrong while editing the VC.
		cameraView.isHidden = false
		capturedPhotoContainerView.isHidden = true

#if !targetEnvironment(macCatalyst) 

		// Check for AR, disable pirate mode if it's not available
		if ARFaceTrackingConfiguration.isSupported {
			let localPirateView = ARSCNView(frame: cameraView.frame, options: nil)
			pirateView = localPirateView
			localPirateView.translatesAutoresizingMaskIntoConstraints = false
			if let parentView = cameraView.superview {
				parentView.insertSubview(localPirateView, aboveSubview: cameraView)
			}
			let anchors = [
					localPirateView.leadingAnchor.constraint(equalTo: cameraView.leadingAnchor),
					localPirateView.trailingAnchor.constraint(equalTo: cameraView.trailingAnchor),
					localPirateView.topAnchor.constraint(equalTo: cameraView.topAnchor),
					localPirateView.bottomAnchor.constraint(equalTo: cameraView.bottomAnchor) ]
			NSLayoutConstraint.activate(anchors)
		
			localPirateView.isHidden = true
			localPirateView.delegate = self
//			localPirateView.session.delegate = self
			localPirateView.automaticallyUpdatesLighting	= true
			
		}
#endif
		
		// Set up an audio session that'll inform us of volume changes
		do {
	        let session = AVAudioSession.sharedInstance()
	        audioSession = session
    	    savedAudioVolume = session.outputVolume 
        	try session.setActive(true)
        	audioSession?.addObserver(self, forKeyPath: "outputVolume", options: [], context: nil)
        }
        catch {
        	CameraLog.debug("Couldn't set up audio session.")
        	audioSession = nil
        }
      	
      	// Create a custom volume display, with a zero-sized frame
        let volView = MPVolumeView(frame: .zero)
        volView.clipsToBounds = true
        view.addSubview(volView)
        
	}
	
	deinit {
		audioSession?.removeObserver(self, forKeyPath: "outputVolume")
	}
	
	override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
		guard keyPath == "outputVolume", let session = audioSession, savedAudioVolume != session.outputVolume else { return }
		savedAudioVolume = session.outputVolume
		beginTakingPicture()
	}
    
	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		CoreMotion.shared.start(forClient: "CameraWidgets", updatesPerSec: 2)
		capturedPhotoContainerView.isHidden = true
		  
		if pirateMode {
			pirateButtonTapped()
		}

		if let inputDevice = cameraDevice {
			if verticalSlider == nil {
				verticalSlider = VerticalSlider(for: inputDevice, frame: CGRect(x: 0, y: 200, width: 40, height: 400))
				self.view.addSubview(verticalSlider!)
			}
			else {
				verticalSlider?.input = inputDevice
			}
		}
		
		UIApplication.shared.isIdleTimerDisabled = true
		updateButtonStates()
		rotateCameraViewsForDeviceRotation(with: nil)
	}
	
	override func viewDidAppear(_ animated: Bool) {
    	super.viewDidAppear(animated)		
		cameraPreview?.frame = cameraView.bounds
	}
	
	override func viewDidDisappear(_ animated: Bool) {
    	super.viewDidDisappear(animated)
		CoreMotion.shared.stop(client: "CameraWidgets")
		if haveLockOnDevice {
			cameraDevice?.unlockForConfiguration()
		}
		UIApplication.shared.isIdleTimerDisabled = false
		
		try? audioSession?.setActive(false)
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
	
	override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
		super.viewWillTransition(to: size, with: coordinator)
		rotateCameraViewsForDeviceRotation(with: coordinator)
	}
		
	func rotateCameraViewsForDeviceRotation(with coordinator: UIViewControllerTransitionCoordinator?) {
		// Change the constraint on the camera view to maintain a 3:4 aspect ratio oriented to match the actual
		// camera aspect.
		if let constraint = cameraAspectConstraint {
			cameraView.removeConstraint(constraint)
			if cameraView.window?.windowScene?.interfaceOrientation.isLandscape == true {
				cameraAspectConstraint = NSLayoutConstraint(item: cameraView as Any, attribute: .width, relatedBy: .equal, 
						toItem: cameraView, attribute: .height, multiplier: 4.0 / 3.0, constant: 0)
			}
			else {
				cameraAspectConstraint = NSLayoutConstraint(item: cameraView as Any, attribute: .width, relatedBy: .equal, 
						toItem: cameraView, attribute: .height, multiplier: 3.0 / 4.0, constant: 0)
			}
			cameraAspectConstraint?.priority = UILayoutPriority(500)
			cameraAspectConstraint?.isActive = true
		}
		
		var newOrientation: AVCaptureVideoOrientation
		switch cameraView.window?.windowScene?.interfaceOrientation {
		case .portrait: newOrientation = .portrait
		case .landscapeLeft: newOrientation = .landscapeLeft
		case .landscapeRight: newOrientation = .landscapeRight
		case .portraitUpsideDown: newOrientation = .portraitUpsideDown
		default: newOrientation = .portrait
		}
		cameraPreview?.connection?.videoOrientation = newOrientation

		// From https://developer.apple.com/library/archive/qa/qa1890/_index.html
		coordinator?.animate(alongsideTransition: { context in
//	        let deltaTransform = coordinator.targetTransform
//    	    let deltaAngle = atan2f(Float(deltaTransform.b), Float(deltaTransform.a))
//			self.currentRotation -= deltaAngle
//			self.rotatorView.layer.setValue(self.currentRotation, forKeyPath: "transform.rotation.z")
		}, completion: { context in 
			self.cameraPreview?.frame = self.cameraView.bounds
		})
	}
		
	// This VC doesn't actually rotate, it technically stays in Portrait all the time. However, it 
	// rotates a bunch of its UI widgets via affine transforms when device rotation is detected. Also,
	// the notification this responds to is a custom app notification, not a system one.
	@objc func deviceRotationNotification(_ notification: Notification) {
		rotateUIElements(animated: true)
	}
	
	func rotateUIElements(animated: Bool) {
//		print ("New orientation: \(CoreMotion.shared.currentDeviceOrientation.rawValue)")

		// On iPad we allow view rotations, so don't do button rotations.
		guard UIDevice.current.userInterfaceIdiom == .phone else { return }
		 
		var rotationAngle: CGFloat = 0.0
		var isLandscape = false
		switch CoreMotion.shared.currentDeviceOrientation {
			case .portrait, .faceUp, .unknown: rotationAngle = 0.0
			case .landscapeLeft: rotationAngle = 90.0; isLandscape = true
			case .landscapeRight: rotationAngle = -90.0; isLandscape = true
			case .portraitUpsideDown, .faceDown: rotationAngle = 180.0
			default: rotationAngle = 0.0
		}
		let xform = CGAffineTransform(rotationAngle: CGFloat.pi * rotationAngle / 180.0)
		let rotationBlock = {
			self.cameraRotateButton.transform = xform
			self.flashButton.transform = xform
			self.pirateButton.transform = xform
			self.retryButton.transform = xform
			self.useButton.transform = xform
			
			let viewWidth = self.capturedPhotoContainerView.bounds.size.width
			var imageAspectRatio: CGFloat = 3.0 / 4.0
			if let image = self.capturedPhotoView.image {
				imageAspectRatio = image.size.width / image.size.height
			}
			
			// When the device is landscape we rotate the photo view just like everything else. However, this
			// view also needs to be resized 
//			let scaleFactor = isLandscape ? imageAspectRatio : 1.0
//			self.capturedPhotoView.transform = xform.scaledBy(x: scaleFactor, y: scaleFactor)
			self.capturedPhotoView.transform = xform
			self.capturedPhotoViewHeightConstraint.constant = isLandscape ? viewWidth : viewWidth / imageAspectRatio
		}
		
		if animated {
			UIView.animate(withDuration: 0.3, animations: rotationBlock)
		}
		else {
			rotationBlock()
		}
	}
	
	// Updates the pirate, flash, camera switch, and shutter state based on what state we're in
	func updateButtonStates() {
		// Check for AR, disable pirate mode if it's not available
#if !targetEnvironment(macCatalyst) 
		let canEnablePirateView = ARFaceTrackingConfiguration.isSupported && 
				cameraInput?.device.position == AVCaptureDevice.Position.front
#else 
		let canEnablePirateView = false
#endif
		let canEnableFlash = cameraDevice?.isFlashAvailable ?? false
		var canEnableCameraRotate = false
		if let disc = discoverer {
			canEnableCameraRotate = Set(disc.devices.map { $0.position }).isSuperset(of: [.front, .back])
		}
		
		if !capturedPhotoContainerView.isHidden {
			// We've taken a photo and are showing it to the user
			pirateButton.isEnabled = false
			randomizeHatsButton.isHidden = true
			flashButton.isEnabled = false
			cameraRotateButton.isEnabled = false
			leftShutter.isEnabled = false
			rightShutter.isEnabled = false
		}
		else if pirateView?.isHidden == false {
			pirateButton.isEnabled = true
			pirateButton.isSelected = true
			flashButton.isEnabled = false
			cameraRotateButton.isEnabled = false
			leftShutter.isEnabled = true
			rightShutter.isEnabled = true
			randomizeHatsButton.isHidden = false
		}
		else {
			pirateButton.isHidden = !canEnablePirateView
			pirateButton.isEnabled = canEnablePirateView
			randomizeHatsButton.isHidden = true
			pirateButton.isSelected = false
			flashButton.isEnabled = canEnableFlash
			cameraRotateButton.isEnabled = canEnableCameraRotate
			leftShutter.isEnabled = true
			rightShutter.isEnabled = true
		}
	}
	
	// Sets up the avSession, with initial settings. Should only run this once per view instantion, at viewDidLoad time. 
	func configureAVSession() {
		#if targetEnvironment(simulator)
		return
		#else
		
		captureSession.sessionPreset = .photo

		// Find our initial camera, and set up our array of camera devices
		discoverer = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera], mediaType: .video, 
				position: .unspecified)
		cameraDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
		if selfieMode || pirateMode || cameraDevice == nil {
			cameraDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
		}
		haveLockOnDevice = false
		do {
			try cameraDevice?.lockForConfiguration()
			haveLockOnDevice = true
		}
		catch {
			haveLockOnDevice = false
		}
	
		captureSession.beginConfiguration()
		if let input = try? AVCaptureDeviceInput(device: cameraDevice!), captureSession.canAddInput(input) { 
			captureSession.addInput(input)
			cameraInput = input
		}

		captureSession.addOutput(photoOutput)

		cameraPreview = AVCaptureVideoPreviewLayer(session: captureSession)
//		cameraPreview!.videoGravity = AVLayerVideoGravity.resizeAspect
		cameraPreview!.videoGravity = AVLayerVideoGravity.resizeAspectFill
		cameraPreview!.connection?.videoOrientation = AVCaptureVideoOrientation.portrait
		cameraView.layer.insertSublayer(cameraPreview!, at: 0)
		captureSession.commitConfiguration()

		
		DispatchQueue.global(qos: .background).async {
			self.captureSession.startRunning()
		}
	//	captureSession.startRunning()
		#endif
	}
		
// MARK: Actions
	
	@IBAction func closeButtonTapped() {
		pirateView?.session.pause()
		dismiss(animated: true, completion: nil)
	}
	
	@IBAction func pirateButtonTapped() {
#if !targetEnvironment(macCatalyst) 
		if !pirateButton.isSelected, let pirateView = pirateView {
			captureSession.stopRunning()
			pirateView.isHidden = false
			cameraView.isHidden = true

			let configuration = ARFaceTrackingConfiguration()
    	    configuration.isLightEstimationEnabled = true
			if #available(iOS 13.0, *) {
				let maxFaces = ARFaceTrackingConfiguration.supportedNumberOfTrackedFaces
				configuration.maximumNumberOfTrackedFaces = maxFaces
//				if ARConfiguration.supportsFrameSemantics(.personSegmentationWithDepth) {
//					configuration.frameSemantics.insert(.personSegmentationWithDepth)
//				}
			}
        	pirateView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
	
			// Load in assets if we don't have them yet.
			if allHats.count == 0 {
				if let url = Bundle.main.url(forResource:"BicornHat", withExtension:"dae", subdirectory: "Hats.scnassets/BicornHat"),
						let localHat = SCNReferenceNode(url: url) {
					allHats.append(localHat)
				}
				if let url = Bundle.main.url(forResource:"FeatherHat", withExtension:"dae", subdirectory: "Hats.scnassets/FeatherHat"),
						let localHat = SCNReferenceNode(url: url) {
					allHats.append(localHat)
				}
				if let url = Bundle.main.url(forResource:"LeatherHat", withExtension:"dae", subdirectory: "Hats.scnassets/LeatherHat"),
						let localHat = SCNReferenceNode(url: url) {
					allHats.append(localHat)
				}
				availableHats = allHats.shuffled()
				
				// Load all the hats in a background thread
				DispatchQueue.global().async {
					self.allHats.forEach { $0.load() }
				}
			}
			
			if eyepatch == nil {
				if let url = Bundle.main.url(forResource:"Eyepatch", withExtension:"scn", subdirectory: "Hats.scnassets/Eyepatch"),
						let localEyepatch = SCNReferenceNode(url: url) {
					DispatchQueue.global().async {
						localEyepatch.load()
						self.eyepatch = localEyepatch
					}
				}
			}
			
			if parrot == nil {
				if let url = Bundle.main.url(forResource:"StandIdlex", withExtension:"dae", subdirectory: "Hats.scnassets/Parrot"),
						let localParrot = SCNReferenceNode(url: url) {
					DispatchQueue.global().async {
						localParrot.load()
						self.parrot = localParrot
					}
				}
			}
		}
		else {
			pirateView?.session.pause()
			pirateView?.isHidden = true
			cameraView.isHidden = false
			DispatchQueue.global(qos: .background).async {
				self.captureSession.startRunning()
			}
		}
		
		updateButtonStates()
#endif
	}
	
	@IBAction func randomizeHatsTapped() {
#if !targetEnvironment(macCatalyst) 
		faceAnchors.forEach { 
			if let baseNode =  $0.faceRootNode.childNodes.first {
				baseNode.removeFromParentNode() 
			}
		}
		availableHats = allHats.shuffled()
		parrotAssigned = false
		for faceIndex in 0..<faceAnchors.count { assignHat(toFaceAtIndex: faceIndex) }
#endif
	}
	
#if !targetEnvironment(macCatalyst) 
	func assignHat(toFaceAtIndex: Int) {
		guard faceAnchors.count > 0 else { return }
		let validFaceIndex = toFaceAtIndex >= faceAnchors.count ? faceAnchors.count - 1 : toFaceAtIndex
		let face = faceAnchors[validFaceIndex]
		let faceBaseNode = SCNNode()
		face.faceRootNode.addChildNode(faceBaseNode)
		
		// Assign a random hat to this face. Hats are randomized in availableHats, so just pick the next hat.
		if availableHats.count > 0 {
			let randomHat = availableHats[validFaceIndex % availableHats.count]
			faceBaseNode.addChildNode(randomHat.clone())
		}
		
		// 50% of the time, put an eyepatch on the face
		if Bool.random(), let eyepatch = eyepatch {
			faceBaseNode.addChildNode(eyepatch.clone())
		}
		
		if !parrotAssigned, Int.random(in: 1...6) == 1, let localParrot = parrot {
//		if let localParrot = parrot {
			faceBaseNode.addChildNode(localParrot.clone())
			parrotAssigned = true
		}
		
		// Add a face occulusion mask.
		if let dev = pirateView?.device, let faceGeometry = ARSCNFaceGeometry(device: dev,fillMesh: true) {
			faceGeometry.firstMaterial!.colorBufferWriteMask = []
			let occlusionNode = SCNNode(geometry: faceGeometry)
			occlusionNode.renderingOrder = -1
			faceBaseNode.addChildNode(occlusionNode)
		}
	}
#endif
	
	
	@IBAction func flashButtonTapped() {
		flashButton.isSelected =  !flashButton.isSelected
	}
	
	@IBAction func cameraSwitchButtonTapped() {
		// If we were in ARKit, stop ARKit and re-enable the capture session.
#if !targetEnvironment(macCatalyst) 
		if pirateButton.isSelected {
			pirateView?.session.pause()
			pirateView?.isHidden = true
			captureSession.startRunning()
		}
#endif
	
		captureSession.beginConfiguration()
		
		var newPosition = AVCaptureDevice.Position.front
		if cameraInput?.device.position == newPosition {
			newPosition = AVCaptureDevice.Position.back
		}
		let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: newPosition)
		if let oldInput = cameraInput {
			captureSession.removeInput(oldInput)
		}
		if let input = try? AVCaptureDeviceInput(device: videoDevice!), captureSession.canAddInput(input) { 
			captureSession.addInput(input)
			cameraInput = input
		}

		captureSession.commitConfiguration()
		if let inputDevice = cameraDevice {
			verticalSlider?.input = inputDevice
		}
		
		updateButtonStates()
	}
	
	// Connected to 8 different Control Events; looking for when either button gets highlighted.
	@IBAction func cameraShutterHighlighted(sender: UIButton, forEvent event: UIEvent) {
		leftShutter.isHighlighted = sender.isHighlighted
		rightShutter.isHighlighted = sender.isHighlighted
	}
	
	@IBAction func cameraShutterButtonPressed(sender: UIButton, forEvent event: UIEvent) {
		beginTakingPicture()
	}
	
	// Starts the process of taking a picture. If we're in AVCapturePhoto mode, calls capturePhoto(). If 
	// we're in ARKit mode, takes a snapshot.
	func beginTakingPicture() {
		leftShutter.isHighlighted = false
		rightShutter.isHighlighted = false
		leftShutter.isEnabled = false
		rightShutter.isEnabled = false
		
	#if targetEnvironment(simulator)
		return
	#else
		// Is this an AVSession picture, or a ARKit snapshot?
		if let pirateView = pirateView, !pirateView.isHidden {
			// Unfortunately, snapshot returns a low-res image. 
			var photoImage = pirateView.snapshot()
			
			// Rotate if necessary
			if UIDevice.current.userInterfaceIdiom == .phone {
				switch CoreMotion.shared.currentDeviceOrientation {
					case .portrait, .faceUp, .unknown: break
					case .landscapeLeft: photoImage = UIImage(cgImage: photoImage.cgImage!, scale: 1.0, orientation: .left)
					case .landscapeRight: photoImage = UIImage(cgImage: photoImage.cgImage!, scale: 1.0, orientation: .right)
					case .portraitUpsideDown, .faceDown: photoImage = UIImage(cgImage: photoImage.cgImage!, scale: 1.0, orientation: .down)
					default: break
				}
			}
			
			capturedPhotoView.image = photoImage
			capturedPhoto = PhotoDataType.image(photoImage)
			capturedPhotoContainerView.isHidden = false
			updateButtonStates()
			rotateUIElements(animated: false)		
		}
		else {
			// Set the orientation of the photo output to match our current UI orientation. 'up' in the photo
			// then matches the current UI orientation. However, this just sets the "Orientation" EXIF tag.
			if let photoOutputConnection = photoOutput.connection(with: AVMediaType.video) {
				switch CoreMotion.shared.currentDeviceOrientation {
					case .portrait, .faceUp, .unknown: photoOutputConnection.videoOrientation = .portrait
					case .landscapeLeft: photoOutputConnection.videoOrientation = .landscapeRight
					case .landscapeRight: photoOutputConnection.videoOrientation = .landscapeLeft
					case .portraitUpsideDown, .faceDown: photoOutputConnection.videoOrientation = .portraitUpsideDown
					default: photoOutputConnection.videoOrientation = .portrait
				}
				
				if photoOutputConnection.isVideoMirroringSupported {
					photoOutputConnection.isVideoMirrored = cameraInput?.device.position == AVCaptureDevice.Position.front
				}
			}

			// THIS LINE IS WHERE WE SELECT THE COMPRESSED PHOTO FORMAT: currently "jpg". 
			let settings =  AVCapturePhotoSettings(format: [AVVideoCodecKey : AVVideoCodecType.jpeg])
			settings.flashMode = flashButton.isSelected ? .auto : .off
			photoOutput.capturePhoto(with: settings, delegate: self)
		}
	#endif
	}
	
	@IBAction func photoAccepted(sender: UIButton, forEvent event: UIEvent) {
		pirateView?.session.pause()
		performSegue(withIdentifier: "dismissCamera", sender: capturedPhoto)
		updateButtonStates()
	}

	@IBAction func photoRejected(sender: UIButton, forEvent event: UIEvent) {
		capturedPhotoContainerView.isHidden = true
		capturedPhoto = nil
		updateButtonStates()
	}
	
	@IBAction func sharePhotoTapped() {
		guard let photoPacket = capturedPhoto else { return }
		photoPacket.getUIImage { photoImageResult in
			if let photoImage = photoImageResult {
				let activityViewController = UIActivityViewController(activityItems: [photoImage], applicationActivities: nil)
				self.present(activityViewController, animated: true, completion: {})
				if let popper = activityViewController.popoverPresentationController {
					popper.sourceView = self.shareButtonParent
					popper.sourceRect = self.shareButton.frame
				}
			}
		}
	}
	
	var zoomGestureRecognizer: UIPanGestureRecognizer?
}

//MARK: - AVCapturePhotoCaptureDelegate
extension CameraViewController : AVCapturePhotoCaptureDelegate {
	func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
		CameraLog.debug("In didFinishProcessingPhoto.", ["metadata" : photo.metadata])
				
		capturedPhoto = PhotoDataType.camera(photo)

		// After a bunch of testing, it appears that fileDataRepresentation() uses the rotation requested 
		// by setting photoOutputConnection.videoOrientation just before calling capturePhoto, while
		// cgImageRepresentation() does not.
		if let photoData = photo.fileDataRepresentation(), let photoImage = UIImage(data: photoData) {
			capturedPhotoView.image = photoImage
		}
		
		capturedPhotoContainerView.isHidden = false
		updateButtonStates()
		rotateUIElements(animated: false)
	}
}

//MARK: - ARSCNViewDelegate

// Discovered faces get a baseNode attached to the face's SCNNode, and then a random hat, perhaps an eyepatch,
// and face occlusion geometry attached to the baseNode.
#if !targetEnvironment(macCatalyst) 
extension CameraViewController: ARSCNViewDelegate {
	func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
		guard let face = anchor as? ARFaceAnchor else  { return }
		let newFace = FaceInfo(faceAnchor: face, faceRootNode: node)
		faceAnchors.append(newFace)
		assignHat(toFaceAtIndex: 10000)	// That is, the last face in the list.
	}
	
	func renderer(_ renderer: SCNSceneRenderer, didRemove node: SCNNode, for anchor: ARAnchor) {
		CameraLog.debug("Node Removed")
	}
}

//MARK: - ARSessionDelegate
extension CameraViewController: ARSessionDelegate {
    func session(_ session: ARSession, didFailWithError error: Error) {
    	print ("SESSIONERROR: \(error)")
    }
}
#endif

//MARK: - UIGestureRecognizerDelegate
extension CameraViewController: UIGestureRecognizerDelegate {

	func setupGestureRecognizer() {	
		let tapper = UIPanGestureRecognizer(target: self, action: #selector(CameraViewController.zoomer))
		tapper.delegate = self
		tapper.name = "CameraViewController Pan to Zoom"
		self.view.addGestureRecognizer(tapper)
		zoomGestureRecognizer = tapper
	}

	func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
		// need to call super if it's not our recognizer
		if gestureRecognizer != zoomGestureRecognizer {
			return false
		}
		return true
	}

	@objc func zoomer(_ sender: UIPanGestureRecognizer) {
		if sender.state == .began {
			verticalSlider?.setupBaselineForMove()
		}
		
		if sender.state == .changed {
			let pixelChange = sender.translation(in: self.view).y
			verticalSlider?.pixelChangeFromBase(pixelChange)
		}
		else if sender.state == .ended {
		} 
		
		if sender.state == .ended || sender.state == .cancelled || sender.state == .failed {
			verticalSlider?.finishedMoving()
		}
	}
	
}

//MARK: -

// VerticalSlider is a custom UI widget that sets the zoom level on the camera by swiping up and down
// over the camera preview (anywhere in the preview). The slider shows as a white thumb on the left
// side of the screen, along with a zoom factor.
class VerticalSlider: UIView {
	var input: AVCaptureDevice
	var baseline: CGFloat = 1.0				// 0 is top, 1.0 is bottom of slider
	var currentValue: CGFloat = 1.0
	var showZoomThumb = false
	
	init(for input: AVCaptureDevice, frame: CGRect) {
		self.input = input
		super.init(frame: frame)
		
		self.backgroundColor = UIColor.clear
		self.isOpaque = false
	}
		
	required init?(coder aDecoder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}
	
	func setupBaselineForMove() {
		baseline = currentValue
		showZoomThumb = true
		setNeedsDisplay()
	}
	
	func finishedMoving() {
		showZoomThumb = false
		setNeedsDisplay()
	}
	
	func pixelChangeFromBase(_ pixelChange: CGFloat) {
		var newPercentage = baseline + pixelChange / bounds.height
		if newPercentage > 1.0 { newPercentage = 1.0 }
		if newPercentage < 0.0 { newPercentage = 0.0 }
		currentValue = newPercentage
		
		var usableMax = input.maxAvailableVideoZoomFactor
		if usableMax > 10.0 { usableMax = 10.0 }
		
		newPercentage = 1.0 - newPercentage
		let zoomCurve = newPercentage * newPercentage
		input.videoZoomFactor = zoomCurve * (usableMax -  input.minAvailableVideoZoomFactor) + 
				input.minAvailableVideoZoomFactor
		setNeedsDisplay()
	}
	
	override func draw(_ rect: CGRect) {	
		let thumbY = self.bounds.origin.y + (self.bounds.height - 25) * currentValue

 		if showZoomThumb {
			let context = UIGraphicsGetCurrentContext()!
			context.setFillColor(UIColor.black.cgColor)
			context.fill(CGRect(x: 0, y: thumbY, width: 50, height: 25))

			let formatter = NumberFormatter()
			formatter.maximumFractionDigits = 1
			formatter.minimumFractionDigits = 1
			let floatNum: Float = Float(input.videoZoomFactor)
			let str = formatter.string(from: NSNumber(value: floatNum))!
			let textAttrs: [NSAttributedString.Key : Any] = [ .font : UIFont.systemFont(ofSize: 20.0) as Any,
					.foregroundColor : UIColor.white ]
			let attributed = NSAttributedString(string: str, attributes: textAttrs)
			attributed.draw(at: CGPoint(x: 0, y: thumbY))
		}
	}
	
	func thumbPercentage() -> CGFloat {
		var usableMax = input.maxAvailableVideoZoomFactor
		if usableMax > 10.0 { usableMax = 10.0 }
		return 1.0 - (input.videoZoomFactor - input.minAvailableVideoZoomFactor) /
				(usableMax - input.minAvailableVideoZoomFactor)
	}
}

// Lots of Swift code gets littered with these dumb extensions that ony map enum values.
// I kind of hate them, but I hate these sort of enum mismatches *more*.
// (in particular, this extension is built for use in exactly 1 spot in this file, it globally extends the enum, and
// anyone else that needs the exact same enum transformation will never find this, and write their own in another file).
extension UIImage.Orientation {
    init(_ cgOrientation: CGImagePropertyOrientation?) {
        if let cg = cgOrientation {
			switch cg {
			case .up: self = .up
			case .upMirrored: self = .upMirrored
			case .down: self = .down
			case .downMirrored: self = .downMirrored
			case .left: self = .left
			case .leftMirrored: self = .leftMirrored
			case .right: self = .right
			case .rightMirrored: self = .rightMirrored
			default: self = .right
			}
		}
		else {
			self = .right
		}
    }
}
