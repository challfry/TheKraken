//
//  KrakenPushProvider.swift
//  KrakenLocalPushExtension
//
//  Created by Chall Fry on 2/9/22.
//  Copyright © 2022 Chall Fry. All rights reserved.
//

import os
import Foundation
import NetworkExtension
import UserNotifications

class KrakenPushProvider: NEAppPushProvider {
	var websocketNotifier = WebsocketNotifier()
	
	override init() {
		super.init()
		websocketNotifier.pushProvider = self
	}

    override func start() {
    	websocketNotifier.updateConfig()
    	websocketNotifier.start()
    }
    
	override func stop(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
		websocketNotifier.stop(with: reason, completionHandler: completionHandler)
	}

	override func handleTimerEvent() {
		websocketNotifier.handleTimerEvent()
	}
	
    // NEProvider override
    override func sleep(completionHandler: @escaping() -> Void) {
		websocketNotifier.logger.log("sleep() called")
        // Add code here to get ready to sleep.
        completionHandler()
    }
    
    // NEProvider override
    override func wake() {
       websocketNotifier.logger.log("wake() called")
    }
    
}

class WebsocketNotifier: NSObject {
	var pushProvider: KrakenPushProvider?		// NULL if notifier is being used in-app
	var session: URLSession?
	var socket: URLSessionWebSocketTask?
	var lastPing: Date?
	let logger = Logger(subsystem: "com.challfry.kraken.localpush", category: "KrakenPushProvider")
	var startState: Bool = false	// TRUE between calls to Start and Stop. Tracks NEAppPushProvider's state, NOT the socket itself.
	var isInApp: Bool = false
	var incomingPhonecallHandler: (([AnyHashable : Any]) -> Void)?
	
	// Config values that can come from ProviderConfiguration. Must be non-nil to open socket
	private var serverURL: URL?
	private var token: String?
	
	init(isInApp: Bool = false) {
		self.isInApp = isInApp
		super.init()
		logger.log("KrakenPushProvider init()")
	}
	
	deinit {
		logger.log("KrakenPushProvider de-init.")
	}
	
	func updateConfig(serverURL: URL? = nil, token: String? = nil) {
		if let provider = pushProvider {
			if let config = provider.providerConfiguration, let twitarrStr = config["twitarrURL"] as? String, let token = config["token"] as? String,
					!twitarrStr.isEmpty, !token.isEmpty, let twitarrURL = URL(string: twitarrStr) {
				self.serverURL = twitarrURL
				self.token = token		
			}
			else {
				self.serverURL = nil
				self.token = nil
			}
		}
		else {
			self.serverURL = serverURL
			self.token = token
		}
	}

    func start() {
		if startState == true {
			logger.log("KrakenPushProvider start() called while already started.")
		}
		else if let _ = self.serverURL, let token = self.token, !token.isEmpty {
			logger.log("KrakenPushProvider \(self.isInApp ? "In-App" : "Extension", privacy: .public) start()")
		}
		else {
			logger.log("KrakenPushProvider \(self.isInApp ? "In-App" : "Extension", privacy: .public) start -- can't start this config")
		}
		startState = true
		openWebSocket()
	}
	
	func openWebSocket() {
		guard let twitarrURL = self.serverURL, let token = self.token, !token.isEmpty else {
			return
		}
		if session == nil {
			let config = URLSessionConfiguration.ephemeral
			config.allowsCellularAccess = false
			config.waitsForConnectivity = true
			session = .init(configuration: config, delegate: self, delegateQueue: nil)
		}
		if let existingSocket = socket, existingSocket.state == .running {
			self.logger.log("Not opening socket; existing one is already open.")
			return
		}
	
		self.logger.log("Opening socket to \(twitarrURL.absoluteString, privacy: .public)")
		var request = URLRequest(url: twitarrURL, cachePolicy: .useProtocolCachePolicy)
		request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
		socket = session?.webSocketTask(with: request)
		if let socket = socket {
			socket.resume()
	        lastPing = Date()
			receiveNextMessage()
		}
		else {
			self.logger.log("openWebSocket didn't create a socket.")
		}
	}
	
	func receiveNextMessage() {
		if let socket = socket {
			socket.receive { [weak self] result in
				guard let self = self else { return }
//				self.logger.log("Got some data incoming!!!! ")
				self.lastPing = Date()
				switch result {
				case .failure(let error):
					self.logger.error("Error during websocket receive: \(error.localizedDescription, privacy: .public)")
					socket.cancel(with: .goingAway,  reason: nil)
					self.socket = nil
					self.session?.finishTasksAndInvalidate()
					self.session = nil					
				case .success(let msg):
					self.logger.log("got a successful message.")
					var msgData: Data?
					switch msg {
					case .string(let str): 
						self.logger.log("DATA: \(str, privacy: .public)")
						msgData = str.data(using: .utf8)
					case .data(let data): 
						msgData = data
					@unknown default:
						self.logger.error("Error during websocket receive: Unknown ws data type delivered.)")
					}
					if let msgData = msgData, let socketNotification = try? JSONDecoder().decode(SocketNotificationData.self, from: msgData) {
						var sendNotification = true
						let content = UNMutableNotificationContent()
						var title = "From Kraken"
						var userInfo: [String: Any] = [
//								"type": socketNotification.type,
								"message": socketNotification.info
						]
						switch socketNotification.type {
						case .announcement: title = "Announcement"
							userInfo["Announcement"] = socketNotification.contentID
						case .fezUnreadMsg: title = "New Looking For Group Message"
							userInfo["Fez"] = socketNotification.contentID
						case .seamailUnreadMsg: title = "New Seamail Message"
							userInfo["Seamail"] = socketNotification.contentID
						case .alertwordTwarrt: title = "Alert Word"
							userInfo["Twarrt"] = socketNotification.contentID
						case .alertwordPost: title = "Alert Word"
							userInfo["ForumPost"] = socketNotification.contentID
						case .twarrtMention: title = "Someone Mentioned You"
							userInfo["Twarrt"] = socketNotification.contentID
						case .forumMention: title = "Someone Mentioned You"
							userInfo["ForumPost"] = socketNotification.contentID
						case .followedEventStarting: title = "Event Starting Soon"
							userInfo["eventID"] = socketNotification.contentID
						case .incomingPhoneCall:
							if let caller = socketNotification.caller {
								self.incomingCallNotification(name: socketNotification.info, callID: socketNotification.contentID,
										userHeader: caller, callerAddr: socketNotification.callerAddress)
							}
							sendNotification = false
						case .phoneCallAnswered:
							sendNotification = false
							UserDefaults(suiteName: "group.com.challfry-FQD.Kraken")?.set(socketNotification.contentID, forKey: "phoneCallAnswered")
							self.logger.log("KrakenPushProvider set UserDefault for phoneCallAnswered")
						case .phoneCallEnded:
							sendNotification = false
							UserDefaults(suiteName: "group.com.challfry-FQD.Kraken")?.set(socketNotification.contentID, forKey: "phoneCallEnded")
							self.logger.log("KrakenPushProvider set UserDefault for phoneCallEnded")
						}
						if sendNotification {
							content.title = title
							content.body = socketNotification.info
							content.sound = .default
							content.userInfo = userInfo //[
							
							let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
							UNUserNotificationCenter.current().add(request) { [weak self] error in
								if let error = error {
									self?.logger.log("Error submitting local notification: \(error.localizedDescription, privacy: .public)")
									return
								}
								
								self?.logger.log("Local notification posted successfully")
							}
						}
					}
					else {
						self.logger.error("Error during websocket receive: Looks like we couldn't parse the data?)")
					}
				}
				self.receiveNextMessage()
			}
		}
    }
    
    func stop(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        logger.log("stop() called")
		socket?.cancel(with: .goingAway,  reason: nil)
		socket = nil
		session?.finishTasksAndInvalidate()
		startState = false
		completionHandler()
    }
    
    func handleTimerEvent() {
		logger.log("HandleTimerEvent() called for instance \(String(format: "%p", self), privacy: .public) lastPing: \(self.lastPing?.debugDescription ?? "<nil>", privacy: .public)")
        if let pingTime = lastPing, Date().timeIntervalSince(pingTime) < 1.0 {
	        logger.warning("HandleTimerEvent() called with very low delay from last call.")
	        return
        }
        lastPing = Date()
        if socket == nil {
        	openWebSocket()
        }
        socket?.sendPing { [weak self] error in
        	if let err = error {
				self?.logger.error("Error during ping to server: \(err.localizedDescription, privacy: .public)")
				self?.socket?.cancel(with: .goingAway,  reason: nil)
				self?.socket = nil
				self?.start()
        	}
        }
    }
    
    func incomingCallNotification(name: String, callID: String, userHeader: Extension_TwitarrV3UserHeader, callerAddr: Extension_PhoneSocketServerAddress?) {
        logger.log("Incoming call")
		var dict = [ "name": name, "callID": callID, "callerID": userHeader.userID.uuidString,
				"username": userHeader.username] as [String : Any]
		if let ipv4Addr = callerAddr?.ipV4Addr {
			dict["ipv4Addr"] = ipv4Addr
		}
		if let ipv6Addr = callerAddr?.ipV6Addr {
			dict["ipv6Addr"] = ipv6Addr
		}
		if let displayName = userHeader.displayName {
			dict["displayName"] = displayName
		}
		if let userImage = userHeader.userImage {
			dict["userImage"] = userImage
		}
		if let provider = pushProvider {
	    	provider.reportIncomingCall(userInfo: dict)
		}
		else {
			// This optional block exists so our in-app socket can deliver an incoming phone call without linking anything new into the extension.
			incomingPhonecallHandler?(dict)
		}
    }
}

extension WebsocketNotifier: URLSessionTaskDelegate {
	func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
        logger.log("Session went invalid because: \(error)")
       	self.session = nil
	}
}

extension WebsocketNotifier: URLSessionWebSocketDelegate {	
	func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol: String?) {
        logger.log("Socket opened with protocol: \(didOpenWithProtocol ?? "<unknown>", privacy: .public)")
	
	}
	
	func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        logger.log("Socket closed with code: \(didCloseWith.rawValue)")
		socket?.cancel(with: .goingAway,  reason: nil)
		socket = nil
	}
}

// MARK: - Twitarr V3 API Encoding/Decoding

struct SocketNotificationData: Codable {
	enum NotificationTypeData: Codable {
		/// A server-wide announcement has just been added.
		case announcement
		/// A participant in a Fez the user is a member of has posted a new message.
		case fezUnreadMsg
		/// A participant in a Seamail thread the user is a member of has posted a new message.
		case seamailUnreadMsg
		/// A user has posted a Twarrt that contains a word this user has set as an alertword.
		case alertwordTwarrt
		/// A user has posted a Forum Post that contains a word this user has set as an alertword.
		case alertwordPost
		/// A user has posted a Twarrt that @mentions this user.
		case twarrtMention
		/// A user has posted a Forum Post that @mentions this user.
		case forumMention
		/// An event the user is following is about to start. NOT CURRENTLY IMPLEMENTED. Plan is to add support for this as a bulk process that runs every 30 mins
		/// at :25 and :55, giving all users following an event about to start a notification 5 mins before the event start time.
		case followedEventStarting
		/// Someone is trying to call this user via KrakenTalk.
		case incomingPhoneCall
		/// The callee answered the call, possibly on another device. 
		case phoneCallAnswered
		/// Caller hung up while phone was rining, or other party ended the call in progress
		case phoneCallEnded
	}
	/// The type of event that happened. See <doc:SocketNotificationData.NotificationTypeData> for values.
	var type: NotificationTypeData
	/// A string describing what happened, suitable for adding to a notification alert.
	var info: String 
	/// An ID of an Announcement, Fez, Twarrt, ForumPost, or Event.
	var contentID: String
	/// For .incomingPhoneCall notifications, the caller.
	var caller: Extension_TwitarrV3UserHeader?
	/// For .incomingPhoneCall notification,s the caller's IP addresses. May be nil, in which case the receiver opens a server socket instead.
	var callerAddress: Extension_PhoneSocketServerAddress?
}

struct Extension_PhoneSocketServerAddress: Codable {
	var ipV4Addr: String?
	var ipV6Addr: String?
}

// UserHeader is already defined in the app, but I need it defined in the extension without pulling everything in.
struct Extension_TwitarrV3UserHeader: Codable {
    /// The user's ID.
    var userID: UUID
    /// The user's username.
    var username: String
    /// The user's displayName.
    var displayName: String?
    /// The user's profile image.
    var userImage: String?
}
