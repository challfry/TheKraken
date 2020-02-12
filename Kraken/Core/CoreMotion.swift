//
//  CoreMotion.swift
//  Kraken
//
//  Created by Chall Fry on 8/6/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//
  
import UIKit
import CoreMotion


// CMMotionManager needs to be a singleton in the app; it configures the motion sensors, and they can only
// be configured one way.
@objc class CoreMotion: NSObject {
	static let shared = CoreMotion()
	let manager = CMMotionManager()
	var currentDeviceOrientation: UIDeviceOrientation = .portrait
	var forceNotifyNextPass = false
	var clients: [String : Int] = [:]
	
	@objc dynamic var motionState: CMDeviceMotion?
	
	static let OrientationChanged = NSNotification.Name("KrakenOrientationChanged")

	func start(forClient: String, updatesPerSec: Int) {
		clients[forClient] = updatesPerSec
	
		calculatUpdateFrequency()
		if manager.isDeviceMotionAvailable {
			manager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { (data, error) in 
				if let data = data {
					self.motionState = data
					
//					let q = data.attitude.quaternion
//					print("w: \(Int(q.w * 10)) x: \(Int(q.x * 10)) y: \(Int(q.y * 10)) z: \(Int(q.z * 10))")

					var newOrientation = self.currentDeviceOrientation
					
					// This code says if the device is within a 30 degree cone of straight up or down, that's it's orientation. Else, if it's within 
					// a ~30 degree cone of edge-on left or right, that's the orientation. Else we can't tell.
					let a = data.attitude
				//	print("roll: \(Int(a.roll * 100)) pitch: \(Int(a.pitch * 100)) yaw: \(Int(a.yaw * 100))")
					if a.pitch > .pi / 3 {
						newOrientation = .portrait
					}
					else if a.pitch < -.pi / 3.0 {
						newOrientation = .portraitUpsideDown
					}
					else if a.roll > .pi / 3.0 && a.roll < .pi * 0.6666 {
						newOrientation = .landscapeRight
					}
					else if a.roll < -.pi / 3.0 && a.roll > -.pi * 0.6666 {
						newOrientation = .landscapeLeft
					}
					
					if newOrientation != self.currentDeviceOrientation || self.forceNotifyNextPass {
						self.forceNotifyNextPass = false
						self.currentDeviceOrientation = newOrientation
						
						NotificationCenter.default.post(Notification(name: CoreMotion.OrientationChanged))
					}
				}
			}
		}
	}
	
	func calculatUpdateFrequency() {
		let result = clients.reduce(1) { max($0, $1.value) }
		let frequency = 1.0 / Double(result)
		manager.deviceMotionUpdateInterval = frequency
	}
	
	func stop(client: String) {
		clients.removeValue(forKey: client)
		calculatUpdateFrequency()
		if clients.isEmpty {
			manager.stopDeviceMotionUpdates()
		}
	}
}
