//
//  KrakenPushProvider.swift
//  KrakenLocalPushExtension
//
//  Created by Chall Fry on 2/9/22.
//  Copyright © 2022 Chall Fry. All rights reserved.
//

import NetworkExtension

class KrakenPushProvider: NEAppPushProvider {
//	var session: URLSession
	var socket: URLSessionWebSocketTask?
	
//	override init() {
//		let config = URLSessionConfiguration.default
//		session = .init(configuration: config, delegate: self, delegateQueue: nil)
//		super.init()
//	}

    override func start() {
		socket = URLSession.shared.webSocketTask(with: URL(string: "ws://192.168.0.19:8081/api/v3/notification/socket")!)
		if let socket = socket {
			socket.resume()
		
			socket.receive { result in
				print("KrakenPushProvider received data!")
			}
		}
 
    }
    
    override func stop(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
		socket?.cancel(with: .goingAway,  reason: nil)
		completionHandler()
    }
    
    override func handleTimerEvent() {
    }
    
    override func sleep(completionHandler: @escaping() -> Void) {
        // Add code here to get ready to sleep.
        completionHandler()
    }
    
    override func wake() {
        // Add code here to wake up.
    }
    
}

extension KrakenPushProvider: URLSessionTaskDelegate {

}

