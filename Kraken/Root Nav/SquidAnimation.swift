//
//  SquidAnimation.swift
//  Kraken
//
//  Created by Chall Fry on 2/8/20.
//  Copyright © 2020 Chall Fry. All rights reserved.
//

import UIKit
import MetalKit

protocol DeepSeaView {
	func buildDeepSeaImage()
}

class OctopusPictureView: UIImageView, DeepSeaView {
	func buildDeepSeaImage() {
		image = UIImage(named: "octo1")
		contentMode = .scaleAspectFill
	}
}

class SquidAnimationView: MTKView, DeepSeaView, MTKViewDelegate {
    // Metal resources
    var commandQueue: MTLCommandQueue!
    var sourceTexture: MTLTexture!
    
    // Core Image resources
    var context: CIContext!
    let filter = CIFilter(name: "CIGaussianBlur")!
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    
    var inputImage: UIImage = UIImage(named: "Squid3")! 
    var centerTransform: CGAffineTransform = CGAffineTransform.identity
	var offsetAnimation: UIViewPropertyAnimator?
	var seconds: Double = 0

    func buildDeepSeaImage() {
		guard let localDevice = MTLCreateSystemDefaultDevice() else { return }
		device = localDevice

        commandQueue = localDevice.makeCommandQueue()
        delegate = self
        framebufferOnly = false
        context = CIContext(mtlDevice: localDevice) 
        preferredFramesPerSecond = 5
		clearColor = MTLClearColor(red: 0.096, green: 0.996 , blue: 0.096, alpha: 1.0)
		backgroundColor = UIColor(red: 0.096, green: 0.096 , blue: 0.996, alpha: 1.0)
		
		CoreMotion.shared.tell(self, when: "motionState") { observer, observed in 
			if let yOffset = observed.motionState?.attitude.pitch,
					let xOffset = observed.motionState?.attitude.roll {
				observer.offsetAnimation?.stopAnimation(true)
				observer.offsetAnimation = UIViewPropertyAnimator(duration: 1.0, curve: .linear) {
					self.frame = CGRect(x: CGFloat(xOffset) * 80.0, y: CGFloat(yOffset) * 80.0, 
							width: self.bounds.size.width, height: self.bounds.size.height)
				}
				observer.offsetAnimation?.startAnimation()

			}
		}
				
		centerTransform = CGAffineTransform(translationX: bounds.size.width / 2, y: bounds.size.height / 2).scaledBy(x: 3.0, y: 3.0)
	}
	
	public func draw(in view: MTKView) {
		seconds = Date().timeIntervalSince1970
		if let currentDrawable = currentDrawable, let commandBuffer = commandQueue.makeCommandBuffer() {
			guard var outputImage = CIImage(image: inputImage) else { return }
			
			var viewSize = bounds
			viewSize.size.width = viewSize.size.width * layer.contentsScale
			viewSize.size.height = viewSize.size.height * layer.contentsScale
			
			let imageXCenter = inputImage.size.width / 2
			let imageYCenter = inputImage.size.height / 2

			let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: currentRenderPassDescriptor!)!
			renderEncoder.endEncoding()

			
			if let filter = CIFilter(name: "CIPerspectiveTransform") {
				filter.setValue(outputImage, forKey: kCIInputImageKey)
				filter.setValue(CIVector(x: sinePeriod(3.4) * imageXCenter / 5.0,
						y: sinePeriod(2.2) * imageYCenter / 5.0), forKey: "inputBottomLeft")
				filter.setValue(CIVector(x: sinePeriod(10.3) * imageXCenter / 5.0, 
						y: inputImage.size.height - sinePeriod(7) * imageYCenter / 5.0), forKey: "inputTopLeft")
				filter.setValue(CIVector(x: inputImage.size.width - sinePeriod(5.6) * imageXCenter / 5.0, 
						y: inputImage.size.height - sinePeriod(3.8) * imageYCenter / 5.0), forKey: "inputTopRight")
				filter.setValue(CIVector(x: inputImage.size.width - sinePeriod(2.8) * imageXCenter / 5.0, 
						y: sinePeriod(11.8) * imageYCenter / 5.0), forKey: "inputBottomRight")

				if let nextImage = filter.outputImage {
					outputImage = nextImage
				}
			}
			
			if let filter = CIFilter(name: "CIAffineClamp") {
				filter.setValue(outputImage, forKey: kCIInputImageKey)
				let xform = CGAffineTransform(scaleX: 1.0 + sinePeriod(7.7) * 0.3, y: 1.0 + sinePeriod(7.7) * 0.3);
				filter.setValue(xform, forKey: kCIInputTransformKey)
				if let nextImage = filter.outputImage {
					outputImage = nextImage
				}
			}

			if let filter = CIFilter(name: "CIGaussianBlur") {
				filter.setValue(outputImage, forKey: kCIInputImageKey)
				filter.setValue(6.0 + sinePeriod(1.7) * 2.0, forKey: kCIInputRadiusKey)
				if let nextImage = filter.outputImage {
					outputImage = nextImage
				}
			}
			
			outputImage = outputImage.clamped(to: outputImage.extent.insetBy(dx: 50, dy: 0))
			
			if let filter = CIFilter(name: "CITwirlDistortion") {
				filter.setValue(outputImage, forKey: kCIInputImageKey)
				filter.setValue(sinePeriod(1.0) / 10.0, forKey: kCIInputAngleKey)
				filter.setValue(CIVector(x: imageXCenter + sinePeriod(3) * imageXCenter / 2.0, 
						y: imageYCenter + sinePeriod(4.5) * imageYCenter / 2.0), forKey: kCIInputCenterKey)
				filter.setValue(imageYCenter * 1.5 + sinePeriod(1.8) * imageYCenter / 5.0, forKey: kCIInputRadiusKey)
				if let nextImage = filter.outputImage {
					outputImage = nextImage
				}
			}
			
			if let filter = CIFilter(name: "CIAffineTransform") {
				filter.setValue(outputImage, forKey: kCIInputImageKey)
				filter.setValue(centerTransform, forKey: kCIInputTransformKey)
				if let nextImage = filter.outputImage {
					outputImage = nextImage
				}
			}
			
			if let filter = CIFilter(name: "CIBlendWithAlphaMask") {
				filter.setValue(outputImage, forKey: kCIInputImageKey)
				filter.setValue(outputImage, forKey: kCIInputMaskImageKey)
				filter.setValue(CIImage(color: CIColor(red: 0.096, green: 0.096, blue: 0.096, alpha: 1.0)), 
						forKey: kCIInputBackgroundImageKey)
				if let nextImage = filter.outputImage {
					outputImage = nextImage
				}
			}
			
						
			context.render(outputImage, to: currentDrawable.texture,
				commandBuffer: commandBuffer, bounds: viewSize, colorSpace: colorSpace)
			commandBuffer.present(currentDrawable) 
			commandBuffer.commit()
		}
	}
	
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
		centerTransform = CGAffineTransform(translationX: size.width / 2, y: size.height / 2).scaledBy(x: 3.0, y: 3.0)
    }
    
    func sinePeriod(_ forPeriod: Double) -> CGFloat {
    	let result = sin(seconds / forPeriod)
    	return CGFloat(result)
    }
}

//				filter.setValue(CIVector(x: 1.0, y: 1.0, z: 1.0, w: 0.5), forKey: "inputMaxComponents")
//				filter.setValue(CIVector(x: 0.096, y: 0.096, z: 0.096, w: 0), forKey: "inputMinComponents")
//				filter.setValue(CIVector(x: 0.0, y: 0.0, z: 0.0, w: 0), forKey: "inputMinComponents")
