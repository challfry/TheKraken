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

class CameraViewController: UIViewController {
	@IBOutlet var cameraView: UIView!
	@IBOutlet var 	closeButton: UIButton!
	@IBOutlet var 	pirateButton: UIButton!
	@IBOutlet var	flashButton: UIButton!
	@IBOutlet var 	cameraRotateButton: UIButton!
	
	var verticalSlider: VerticalSlider?
	@IBOutlet var 	leftShutter: UIButton!
	@IBOutlet var 	rightShutter: UIButton!
	
	@IBOutlet var 	capturedPhotoContainerView: UIView!
	@IBOutlet var 		capturedPhotoView: UIImageView!
	@IBOutlet var 		capturedPhotoViewHeightConstraint: NSLayoutConstraint!
	@IBOutlet var 		retryButton: UIButton!
	@IBOutlet var 		useButton: UIButton!
	
	var captureSession = AVCaptureSession()
	var cameraDevice: AVCaptureDevice?					// The currently active device
	var haveLockOnDevice: Bool = false					// TRUE if we have a lock on cameraDevice and can config it
	var cameraInput: AVCaptureDeviceInput?
	var cameraPreview: AVCaptureVideoPreviewLayer?
	var photoOutput = AVCapturePhotoOutput()
	var capturedPhoto: AVCapturePhoto?

    override func viewDidLoad() {
        super.viewDidLoad()
        
		configureAVSession()
		setupGestureRecognizer()
		
		NotificationCenter.default.addObserver(self, selector: #selector(CameraViewController.deviceRotationNotification), 
				name: CoreMotion.OrientationChanged, object: nil)
	}
    
	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		cameraPreview?.frame = cameraView.bounds
		CoreMotion.shared.start()
		  
		if let inputDevice = cameraDevice {
			if verticalSlider == nil {
				verticalSlider = VerticalSlider(for: inputDevice, frame: CGRect(x: 0, y: 200, width: 40, height: 400))
				self.view.addSubview(verticalSlider!)
			}
			else {
				verticalSlider?.input = inputDevice
			}
		}
	}
	
	override func viewDidDisappear(_ animated: Bool) {
		CoreMotion.shared.stop()
		if haveLockOnDevice {
			cameraDevice?.unlockForConfiguration()
		}
	}
	
	override var shouldAutorotate: Bool {
		return false
	}
	
	@objc func deviceRotationNotification(_ notification: Notification) {
//		print ("New orientation: \(CoreMotion.shared.currentDeviceOrientation.rawValue)")
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
		UIView.animate(withDuration: 0.3) {
			self.cameraRotateButton.transform = xform
			self.flashButton.transform = xform
			self.pirateButton.transform = xform
			self.retryButton.transform = xform
			self.useButton.transform = xform
			
			let viewWidth = self.capturedPhotoContainerView.bounds.size.width
			var imageAspectRatio: CGFloat = 4.0 / 3.0
			if let image = self.capturedPhotoView.image {
				imageAspectRatio = image.size.height / image.size.width
			}
			self.capturedPhotoView.transform = xform
			self.capturedPhotoViewHeightConstraint.constant = isLandscape ? viewWidth : viewWidth * imageAspectRatio
		}
	}
	
	func configureAVSession() {
		#if targetEnvironment(simulator)
		return
		#else

		captureSession.sessionPreset = .photo
		cameraDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
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

		captureSession.startRunning()
		#endif
	}
	
// MARK: - Actions
	
	@IBAction func closeButtonTapped() {
		dismiss(animated: true, completion: nil)
	}
	
	@IBAction func pirateButtonTapped() {
		
	}
	
	@IBAction func flashButtonTapped() {
		flashButton.isSelected =  !flashButton.isSelected
	}
	
	@IBAction func cameraSwitchButtonTapped() {
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
	
	}
	
	// Connected to 8 different Control Events; looking for when either button gets highlighted.
	@IBAction func cameraShutterHighlighted(sender: UIButton, forEvent event: UIEvent) {
		leftShutter.isHighlighted = sender.isHighlighted
		rightShutter.isHighlighted = sender.isHighlighted
	}
	
	@IBAction func cameraShutterButtonPressed(sender: UIButton, forEvent event: UIEvent) {
		leftShutter.isHighlighted = false
		rightShutter.isHighlighted = false
		leftShutter.isEnabled = false
		rightShutter.isEnabled = false
		
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
		}

		//
		let settings =  AVCapturePhotoSettings(format: [AVVideoCodecKey : AVVideoCodecType.jpeg])
		settings.flashMode = flashButton.isSelected ? .auto : .off
		photoOutput.capturePhoto(with: settings, delegate: self)
	}
	
	@IBAction func photoAccepted(sender: UIButton, forEvent event: UIEvent) {
	//	let photoData = capturedPhoto?.fileDataRepresentation()
	//	performSegue(withIdentifier: "dismissCamera", sender: photoData)
	}

	@IBAction func photoRejected(sender: UIButton, forEvent event: UIEvent) {
		capturedPhotoContainerView.isHidden = true
		capturedPhoto = nil
	}
	
	var zoomGestureRecognizer: UIPanGestureRecognizer?
}

//MARK: -

extension CameraViewController : AVCapturePhotoCaptureDelegate {
	func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
		CameraLog.debug("In didFinishProcessingPhoto.", ["metadata" : photo.metadata])
		
		capturedPhotoContainerView.isHidden = false
		if let cgImage = photo.cgImageRepresentation()?.takeUnretainedValue() {
			// deal with rotation of the image
			var counterRotate: UIImage.Orientation = .right
			if let raw = photo.metadata[String(kCGImagePropertyOrientation)] as? UInt32,
					let cgOrientation = CGImagePropertyOrientation(rawValue: raw) {
				counterRotate = UIImage.Orientation(cgOrientation)
			}
			
			var isLandscape = Set(arrayLiteral: .landscapeRight, .landscapeLeft).contains(CoreMotion.shared.currentDeviceOrientation)
			let viewWidth = self.capturedPhotoContainerView.bounds.size.width
			var imageAspectRatio: CGFloat = CGFloat(cgImage.width) / CGFloat(cgImage.height)
			if Set(arrayLiteral: .up, .down).contains(counterRotate) { 
//				imageAspectRatio = 1.0 / imageAspectRatio 
				isLandscape = !isLandscape
			}
			capturedPhotoViewHeightConstraint.constant = isLandscape ? viewWidth : viewWidth * imageAspectRatio
	//		let imageViewHeight = CGFloat(cgImage.width) * CGFloat(capturedPhotoView.bounds.width) / CGFloat(cgImage.height)
			capturedPhotoView.image = UIImage(cgImage: cgImage, scale: 1.0, orientation: counterRotate)
			
			capturedPhoto = photo
		}
		leftShutter.isEnabled = true
		rightShutter.isEnabled = true
	}
}

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
