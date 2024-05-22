//
//  PhotostreamCamera.swift
//  Kraken
//
//  Created by Chall Fry on 4/22/24.
//  Copyright © 2024 Chall Fry. All rights reserved.
//

import UIKit
import AVFoundation
import CoreMotion
import MediaPlayer
import Vision
import CoreImage.CIFilterBuiltins

class PhotostreamCameraViewController: UIViewController {
	@IBOutlet weak var 	cameraView: UIView!
	@IBOutlet weak var 	shutterButton: UIButton!
	@IBOutlet weak var 	locationButton: UIButton!
	@IBOutlet weak var 	uploadButton: UIButton!
	@IBOutlet weak var	errorLabel: UILabel!

	@IBOutlet weak var 	capturedPhotoContainerView: UIView!			// Could be UIVisualEffectView
	@IBOutlet weak var 		capturedPhotoView: UIImageView!
	@IBOutlet weak var 		retryButton: UIButton!
	
	// Props we need to run the camera
	var captureSession = AVCaptureSession()
	var cameraDevice: AVCaptureDevice?					// The currently active device
	var haveLockOnDevice: Bool = false					// TRUE if we have a lock on cameraDevice and can config it
	var cameraInput: AVCaptureDeviceInput?
	var cameraPreview: AVCaptureVideoPreviewLayer?
	var photoOutput = AVCapturePhotoOutput()
	var discoverer: AVCaptureDevice.DiscoverySession?

	var isCapturingPhoto: Bool = false
	var capturedPhoto: PhotoDataType?
	var captureTime: Date?
	
	var isUploadingPhoto: Bool = false
	var photoPassedOCR = false
	
	// MARK: Methods

    override func viewDidLoad() {
        super.viewDidLoad()
        
		configureAVSession()
						
		// Fix-up Interface Builder values that might get set wrong while editing the VC.
		cameraView.isHidden = false
		
		locationButton.changesSelectionAsPrimaryAction = true
		locationButton.showsMenuAsPrimaryAction = true
		let defaultMenuItems = [ UIAction(title: "On Boat", state: .on, handler: { action in }) ]
		locationButton.menu = UIMenu(title: "Choose Location", options: [.displayInline, .singleSelection], children: defaultMenuItems)

		PhotostreamDataManager.shared.tell(self, when: ["photostreamLocations", "photostreamEventNames"]) { observer, observed in
			var items: [UIMenuElement] = observed.photostreamLocations.map { 
				let action = UIAction(title: $0, handler: { action in }) 
				if $0 == observer.locationButton.currentTitle {
					action.state = .on
				}
				return action
			}
			if observed.photostreamEventNames.count > 0 {
				let eventItems = observed.photostreamEventNames.map {
					let action = UIAction(title: $0, handler: { action in })
					if $0 == observer.locationButton.currentTitle {
						action.state = .on
					}
					return action
				}
				items.append(UIMenu(title: "Events:", options: [ .singleSelection], children: eventItems))
			}
			
			observer.locationButton.menu = UIMenu(title: "Choose Location", options: [.displayInline, .singleSelection], children: items)
		}?.execute()
		
		PhotostreamDataManager.shared.tell(self, when: "lastError") { observer, observed in
			if let errorDesc = observed.lastError?.localizedDescription {
				let labelStr = NSMutableAttributedString(string: "Error: ", attributes: [ .foregroundColor : UIColor.red ])
				labelStr.append(NSAttributedString(string: errorDesc, attributes: [ .foregroundColor : UIColor.white ]))
				observer.errorLabel.attributedText = labelStr
			}
			else {
				observer.errorLabel.attributedText = nil
			}
		}?.execute()
	}

	override func viewWillAppear(_ animated: Bool) {
    	super.viewWillAppear(animated)		
		cameraPreview?.frame = cameraView.bounds
		UIApplication.shared.isIdleTimerDisabled = true
		capturedPhotoContainerView.isHidden = true
		PhotostreamDataManager.shared.getPhotostreamLocations()
		capturedPhoto = nil
		photoPassedOCR = false
		updateButtonStates()
		PhotostreamDataManager.shared.clearLastError()
	}
	
	override func viewDidAppear(_ animated: Bool) {
    	super.viewDidAppear(animated)		
		cameraPreview?.frame = cameraView.bounds
	}

	override func viewDidDisappear(_ animated: Bool) {
    	super.viewDidDisappear(animated)
		captureSession.stopRunning()
		if haveLockOnDevice {
			cameraDevice?.unlockForConfiguration()
		}
		UIApplication.shared.isIdleTimerDisabled = false
	}
	
	@IBAction func cameraShutterButtonPressed(sender: UIButton, forEvent event: UIEvent) {
		beginTakingPicture()
		updateButtonStates()
	}
	
	@IBAction func photoRejected(sender: UIButton, forEvent event: UIEvent) {
		capturedPhotoContainerView.isHidden = true
		capturedPhoto = nil
		photoPassedOCR = false
		updateButtonStates()
	}
	
	func updateButtonStates() {
		if isUploadingPhoto {
			capturedPhotoContainerView.isHidden = false
			shutterButton.isEnabled = false
			shutterButton.isHighlighted = false
			uploadButton.isEnabled = false
		}
		else if isCapturingPhoto {
			// Immediately after shutter pressed
			capturedPhotoContainerView.isHidden = true
			shutterButton.isEnabled = false
			shutterButton.isHighlighted = false
			uploadButton.isEnabled = false
		}
		else if !photoPassedOCR && capturedPhoto != nil {
			// Doing OCR
			capturedPhotoContainerView.isHidden = false
			shutterButton.isEnabled = false
			shutterButton.isHighlighted = false
			uploadButton.isEnabled = false
		}
		else if photoPassedOCR && capturedPhoto != nil {
			// OCR Done, clear to upload
			capturedPhotoContainerView.isHidden = false
			shutterButton.isEnabled = false
			shutterButton.isHighlighted = false
			uploadButton.isEnabled = true
		}
		else {
			// Initial state
			capturedPhotoContainerView.isHidden = true
			shutterButton.isEnabled = true
			shutterButton.isHighlighted = true
			uploadButton.isEnabled = false
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
		if  cameraDevice == nil {
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
		cameraPreview!.frame = cameraView.bounds
		captureSession.commitConfiguration()
		
		DispatchQueue.global(qos: .background).async {
			self.captureSession.startRunning()
		}
		#endif
	}

	// Starts the process of taking a picture. If we're in AVCapturePhoto mode, calls capturePhoto(). If 
	// we're in ARKit mode, takes a snapshot.
	func beginTakingPicture() {				
	#if targetEnvironment(simulator)
		return
	#else
		isCapturingPhoto = true
		capturedPhotoView.image = nil
		capturedPhoto = nil
		captureTime = Date()
		updateButtonStates()

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
		let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey : AVVideoCodecType.jpeg])
//		settings.flashMode = flashButton.isSelected ? .auto : .off
		photoOutput.capturePhoto(with: settings, delegate: self)
		
		//
		cameraPreview?.connection?.isEnabled = false
	#endif
	}
	
	@IBAction func uploadButtonTapped() {
		guard let photo = capturedPhoto, let capturedAt = self.captureTime else {
			return
		}
		isUploadingPhoto = true

		let location = locationButton.currentTitle ?? "On Boat"
		photo.getUIImage { image in
			if let image = image, let photoData = image.jpegData(compressionQuality: 0.9) {
				PhotostreamDataManager.shared.postPhotoToStream(photo: photoData, createdAt: capturedAt, locationName: location) { err in
					if let error = err {
					
					}
					else {
						self.dismiss(animated: true)
						PhotostreamDataManager.shared.updatePhotostream()
					}
				}
			}
		}
	}
	
}

extension PhotostreamCameraViewController : AVCapturePhotoCaptureDelegate {
	func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
//		CameraLog.debug("In didFinishProcessingPhoto.", ["metadata" : photo.metadata])
		
		if let err = error {
			CameraLog.debug("Photo capture error", ["error" : err])
			cameraPreview?.connection?.isEnabled = true
			return
		}
				
		// Resize 
		let origSize = CGSize(width: Double(photo.resolvedSettings.photoDimensions.height), height: Double(photo.resolvedSettings.photoDimensions.width))
		let minDimension = min(origSize.width, origSize.height)
		let newSize = CGSize(width: minDimension, height: minDimension)
		let drawRect = CGRect(x: 0, y: (newSize.height - origSize.height) / 2, width: origSize.width, height: origSize.height)
		let photoImage = UIImage(cgImage: photo.cgImageRepresentation()!, scale: 1.0, orientation: .right)
		UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
		photoImage.draw(in: drawRect)
		let newImage = UIGraphicsGetImageFromCurrentImageContext()!
		UIGraphicsEndImageContext()
		
		capturedPhotoView.image = photoImage			// Gets replaced after OCR		
		capturedPhoto = PhotoDataType.image(newImage)
		photoPassedOCR = false
		capturedPhotoView.image = newImage		
		isCapturingPhoto = false
		updateButtonStates()

		// OCR
		guard let cgImage = newImage.cgImage else { return }
		let requestHandler = VNImageRequestHandler(cgImage: cgImage)
		let request = VNRecognizeTextRequest(completionHandler: textRecognizeDone)
		try? requestHandler.perform([request])
	}
	
	func textRecognizeDone(request: VNRequest, error: Error?) {
		guard let observations = request.results as? [VNRecognizedTextObservation] else {
			cameraPreview?.connection?.isEnabled = true
    	    return
    	}
    	let recognizedStrings = observations.compactMap { observation in
	        return observation.topCandidates(1).first?.string
   		}
		if recognizedStrings.count == 0 {
			// TODO: Check that capturedPhoto hasn't changed
			cameraPreview?.connection?.isEnabled = true
			photoPassedOCR = true
			updateButtonStates()
			return
		}
		
		// Just blend it
		capturedPhoto?.getUIImage { image in
			if let image = image, let ciImage = CIImage(image: image ) {
        		let blurredImage = ciImage.applyingGaussianBlur(sigma: 100.0).cropped(to: ciImage.extent)
        		
//        		let cgMask = CGContext(data: nil, width: Int(image.size.width), height: Int(image.size.height), bitsPerComponent: 8, 
//        				bytesPerRow: ((Int(image.size.width) * 4 + 15) / 16) * 16, space: CGColorSpace(name: CGColorSpace.sRGB)!, 
//        				bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue)

				
				let renderSize = CGSize(width: image.size.width, height: image.size.height)
				let renderRect = CGRect(x: 0, y: 0, width: image.size.width, height: image.size.height)
				let format = UIGraphicsImageRendererFormat.preferred()
				format.scale = 1.0
				let renderer = UIGraphicsImageRenderer(size: renderSize, format: format)
				let maskImage = renderer.image { context in
					context.cgContext.setFillColor(UIColor.black.cgColor)
					context.fill(renderRect)
					context.cgContext.setFillColor(UIColor.green.cgColor)
					observations.forEach { observation in
						guard let candidate = observation.topCandidates(1).first else { return }
						
						// TODO: loop for each char.
						let stringRange = candidate.string.startIndex..<candidate.string.endIndex
						if let boxObservation = try? candidate.boundingBox(for: stringRange) {
							context.cgContext.beginPath()
							context.cgContext.move(to: self.maskImagePointFromVNPoint(boxObservation.topLeft, renderRect))
							context.cgContext.addLine(to: self.maskImagePointFromVNPoint(boxObservation.topRight, renderRect))
							context.cgContext.addLine(to: self.maskImagePointFromVNPoint(boxObservation.bottomRight, renderRect))
							context.cgContext.addLine(to: self.maskImagePointFromVNPoint(boxObservation.bottomLeft, renderRect))
							context.cgContext.addLine(to: self.maskImagePointFromVNPoint(boxObservation.topLeft, renderRect))
							context.cgContext.fillPath(using: .winding)
						}
					}
				}
				
   				let blendWithMaskFilter = CIFilter.blendWithMask()
   				blendWithMaskFilter.backgroundImage = ciImage
				blendWithMaskFilter.inputImage = blurredImage
				blendWithMaskFilter.maskImage = CIImage(image: maskImage)
    			let outputCIImage = blendWithMaskFilter.outputImage!
    
    			let outputImage = UIImage(ciImage: outputCIImage)
				self.capturedPhotoView.image = outputImage
				self.capturedPhoto = PhotoDataType.image(outputImage)
		//		self.capturedPhotoView.image = maskImage
				self.photoPassedOCR = true
				self.updateButtonStates()
				self.cameraPreview?.connection?.isEnabled = true
			}
		}
    }
    
    func maskImagePointFromVNPoint(_ vnPoint: CGPoint, _ imageRect: CGRect) -> CGPoint {
    	var pt = VNImagePointForNormalizedPoint(vnPoint, Int(imageRect.size.width), Int(imageRect.size.height))
    	pt.y = imageRect.size.height - pt.y
    	return pt
    }

}
