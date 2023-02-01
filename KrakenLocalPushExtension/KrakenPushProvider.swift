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
	var session: URLSession?
	var socket: URLSessionWebSocketTask?
	var lastPing: Date?
	let logger = Logger(subsystem: "com.challfry.kraken.localpush", category: "KrakenPushProvider")
	
	override init() {
		super.init()
		logger.log("KrakenPushProvider init()")
		let config = URLSessionConfiguration.default
		session = .init(configuration: config, delegate: self, delegateQueue: nil)
	}

    override func start() {
		logger.log("KrakenPushProvider start()")
		openWebSocket()
	}
	
	func openWebSocket() {
		guard let config = providerConfiguration, let twitarrStr = config["twitarrURL"] as? String, let token = config["token"] as? String,
				!twitarrStr.isEmpty, !token.isEmpty, let twitarrURL = URL(string: twitarrStr) else {
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
				case .success(let msg):
//					self.logger.log("got a successful message.")
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
    
    override func stop(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        logger.log("stop() called")
		socket?.cancel(with: .goingAway,  reason: nil)
		socket = nil
		completionHandler()
    }
    
    override func handleTimerEvent() {
        logger.log("HandleTimerEvent() called")
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
    
    override func sleep(completionHandler: @escaping() -> Void) {
        logger.log("sleep() called")
        // Add code here to get ready to sleep.
        completionHandler()
    }
    
    override func wake() {
        logger.log("wake() called")
    }
    
    func incomingCallNotification(name: String, callID: String, userHeader: TwitarrV3UserHeader, callerAddr: PhoneSocketServerAddress?) {
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
    	reportIncomingCall(userInfo: dict)
    }
}

extension KrakenPushProvider: URLSessionTaskDelegate {
	func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
        logger.log("Session went invalid because: \(error)")
	}
	
	func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol: String?) {
        logger.log("Socket opened with protocol: \(didOpenWithProtocol ?? "<unknown>")")
	
	}
	
	func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        logger.log("Socket closed with code: \(didCloseWith.rawValue)")
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
	var caller: TwitarrV3UserHeader?
	/// For .incomingPhoneCall notification,s the caller's IP addresses. May be nil, in which case the receiver opens a server socket instead.
	var callerAddress: PhoneSocketServerAddress?
}

struct PhoneSocketServerAddress: Codable {
	var ipV4Addr: String?
	var ipV6Addr: String?
}

struct TwitarrV3UserHeader: Codable {
    /// The user's ID.
    var userID: UUID
    /// The user's username.
    var username: String
    /// The user's displayName.
    var displayName: String?
    /// The user's profile image.
    var userImage: String?
}
