//
//  PhonecallDataManager.swift
//  Kraken
//
//  Created by Chall Fry on 1/12/23.
//  Copyright © 2023 Chall Fry. All rights reserved.
//

import Foundation
import CallKit
import Network
import AVFoundation
import os
import UIKit

@objc class CurrentCallInfo : NSObject {
	@objc dynamic var other: KrakenUser
	@objc dynamic var callUUID: UUID
	var answeredCall: Bool = false
	var socket: URLSessionWebSocketTask?
	var callStartTime: Date?
	@objc dynamic var callError: Error?
	
	// Direct call
	var portListener: NWListener?
	var connection: NWConnection?
	var serverURL: String?

	init(calling: KrakenUser) {
		other = calling
		callUUID = UUID()
		super.init()
		startNotificationTimer()
	}
	
	init(caller: KrakenUser, callID: UUID) {
		other = caller
		callUUID = callID
		super.init()
		startNotificationTimer()
	}
	
	// Horrible Timer Bullshit - KVO on UserDefaults doesn't work, NSNotification doesn't work. 
	// Is there a reasonable way to do IPC with a network extension?
	var defaultsChangeTimer: Timer?
	var answered: String = ""
	var ended = ""
	func startNotificationTimer() {
		DispatchQueue.main.async { [weak self] in
			guard let self = self else { return }
			self.answered = UserDefaults.standard.string(forKey: "phoneCallAnswered") ?? ""
			self.answered = UserDefaults(suiteName: "group.com.challfry-FQD.Kraken")?.string(forKey: "phoneCallAnswered") ?? ""
			self.ended = UserDefaults(suiteName: "group.com.challfry-FQD.Kraken")?.string(forKey: "phoneCallEnded") ?? ""
			self.defaultsChangeTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
				guard let self = self else { return }
				let newAnswered = UserDefaults(suiteName: "group.com.challfry-FQD.Kraken")?.string(forKey: "phoneCallAnswered") ?? ""
				let newEnded = UserDefaults(suiteName: "group.com.challfry-FQD.Kraken")?.string(forKey: "phoneCallEnded") ?? ""
				if newAnswered != self.answered {
					self.answered = newAnswered
					if self.answeredCall == false, let newEndedUUID = UUID(uuidString: newEnded), newEndedUUID == self.callUUID {
						PhonecallDataManager.shared.endCall()
					}
				}
				if newEnded != self.ended {
					self.ended = newEnded
					if let newEndedUUID = UUID(uuidString: newEnded), newEndedUUID == self.callUUID {
						// If the call ended before it started, it was declined
						if self.socket == nil {
							self.setError(ServerError("Call declined"))
						}
						PhonecallDataManager.shared.endCall()
					}
				}
			}
		}
	}
	
	func setError(_ newError: Error?) {
		self.callError = newError
	}
	
	deinit {
		defaultsChangeTimer?.invalidate()
	}
}

@objc class PhonecallDataManager: NSObject {
	static let shared = PhonecallDataManager()
	
	private let logger = Logger(subsystem: "Kraken", category: "PhonecallDataManager")
    private let dispatchQueue = DispatchQueue(label: "CallManager.dispatchQueue")
	private let provider: CXProvider
    let callController = CXCallController()
	@objc dynamic var currentCall: CurrentCallInfo? = nil

	
	// This would be so much more efficient if I just used ring buffers, but: it's *audio*. Literally not millions of samples/sec.
	var engine = AVAudioEngine()
	let bufferLock = NSLock()
	var networkData = Data()
		
    /// The app's provider configuration, representing its CallKit capabilities
    static let providerConfiguration: CXProviderConfiguration = {
        let providerConfiguration = CXProviderConfiguration()

        // Prevents multiple calls from being grouped.
        providerConfiguration.maximumCallsPerCallGroup = 1
        providerConfiguration.supportsVideo = false
        providerConfiguration.supportedHandleTypes = [.generic]
        providerConfiguration.ringtoneSound = "Ringtone.aif"

//       providerConfiguration.iconTemplateImageData =

        return providerConfiguration
    }()

	override init() {
		provider = CXProvider(configuration: type(of: self).providerConfiguration)
		super.init()
        provider.setDelegate(self, queue: nil)
	}

// MARK: - Networking

	// The user has tapped the 'Call' button and wants to initiate a phone call.
	func requestCallTo(user: KrakenUser, done: @escaping (CurrentCallInfo) -> Void) {
		dispatchQueue.async { [self] in
			// Don't accept call start if we think we're on another call or if we aren't logged in.
			logger.info("Initiating phone call to \(user.username)")
			let newCall = CurrentCallInfo(calling: user)
			currentCall = newCall
			let handle = CXHandle(type: .generic, value: user.username)
			let startCallAction = CXStartCallAction(call: newCall.callUUID, handle: handle)
			startCallAction.isVideo = false
			
			// Immediately update with the name of who we're calling.
			let transaction = CXTransaction()
			transaction.addAction(startCallAction)
			callController.request(transaction) { error in
				if let error = error {
					self.logger.info("Error requesting transaction: \(error.localizedDescription)")
					newCall.setError(error)
					return
				}
	   
				let updateNameAction = CXCallUpdate()
				updateNameAction.localizedCallerName = "\(user.username)"
				self.provider.reportCall(with: newCall.callUUID, updated: updateNameAction)
			}
			
			// Direct phone-to-phone sockets
			if Settings.shared.useDirectVOIPConnnections {
				openDirectCallWSServer(call: newCall)			
				var request = NetworkGovernor.buildTwittarRequest(withPath: "/api/v3/phone/initiate/\(newCall.callUUID)/to/\(user.userID)",
						query: nil)
				NetworkGovernor.addUserCredential(to: &request)
				request.httpMethod = "POST"
				if let bodyData = getWIFIAddressStruct() {
					request.httpBody = try! Settings.v3Encoder.encode(bodyData)
				}
				NetworkGovernor.shared.queue(request) { (package: NetworkResponse) in
					if let error = NetworkGovernor.shared.parseServerError(package) {
						NetworkLog.error(error.localizedDescription)
						newCall.setError(error)
						self.endCall(reason: .failed)
					}
				}
			}
			else {
				var request = NetworkGovernor.buildTwittarRequest(withPath: "/api/v3/phone/socket/initiate/\(newCall.callUUID)/to/\(user.userID)",
						query: nil, webSocket: true)
				NetworkGovernor.addUserCredential(to: &request)
				NetworkGovernor.shared.queue(request) { (package: NetworkResponse) in
					if let error = NetworkGovernor.shared.parseServerError(package) {
						NetworkLog.error(error.localizedDescription)
						newCall.setError(error)
						self.endCall(reason: .failed)
					}
					else if let socket = package.socket {
						newCall.socket = socket
						self.receiveMessageFromServerSocket()
					}
				}
			}
			done(newCall)
		}
	}
	
	// Called by the Local Push Manager when we get an incoming call notification (a local push notification type)
	func receivedIncomingCallNotification(userInfo: [AnyHashable : Any]) {
		guard let callerIDStr = userInfo["callerID"] as? String, let callerID = UUID(uuidString: callerIDStr),
				let callIDStr = userInfo["callID"] as? String, let callID = UUID(uuidString: callIDStr),
				let username = userInfo["username"] as? String else {
			logger.log("Incoming phonecall's userInfo dict didn't have info we needed.")
			return
		}		

		let callerHeader = TwitarrV3UserHeader(userID: callerID, username: username, displayName: userInfo["displayName"] as? String,
				userImage: userInfo["userImage"] as? String)
		UserManager.shared.updateUserHeader(for: nil, from: callerHeader) { [self] caller in
			guard currentCall == nil else {
				// TODO: I think we can get rid of this: OS-level call management can handle it!
				logger.log("Already on a call; not answering.")
				return
			} 
			guard let caller = caller else  {
				return
			}
			self.dispatchQueue.async { [self] in
				self.currentCall = CurrentCallInfo(caller: caller, callID: callID)
						
				if Settings.shared.useDirectVOIPConnnections {
					if let ipv4Addr = userInfo["ipv4Addr"] {
						self.currentCall?.serverURL = "ws://\(ipv4Addr):80"
					}
					else if let ipv6Addr = userInfo["ipv6Addr"] {
						self.currentCall?.serverURL = "ws://[\(ipv6Addr)]:80"
					}
				}

				let update = CXCallUpdate()
				update.remoteHandle = CXHandle(type: .generic, value: caller.username)
				update.hasVideo = false
				self.provider.reportNewIncomingCall(with: callID, update: update) { error in
					if let error = error {
						self.logger.info("Report incoming call failed: \(error.localizedDescription)")
						self.currentCall?.setError(error)
						self.endCall(reason: .failed)
						return
					}
				}
			}
		}
	}
	
	func getWIFIAddressStruct() -> PhoneSocketServerAddress? {
		var addressStruct = PhoneSocketServerAddress()
		var ifaddr: UnsafeMutablePointer<ifaddrs>? = nil
		guard getifaddrs(&ifaddr) == 0 else { return nil }
		guard let firstAddr = ifaddr else { return nil }
		defer { freeifaddrs(ifaddr) }
		for ifptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
			let interface = ifptr.pointee
			let addrFamily = interface.ifa_addr.pointee.sa_family
			if addrFamily == UInt8(AF_INET) || addrFamily == UInt8(AF_INET6) {
				let name: String = String(cString: (interface.ifa_name))
				if  name == "en0" {
					var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
					getnameinfo(interface.ifa_addr, socklen_t((interface.ifa_addr.pointee.sa_len)), &hostname, socklen_t(hostname.count), 
							nil, socklen_t(0), NI_NUMERICHOST)
					if addrFamily == UInt8(AF_INET) {
						addressStruct.ipV4Addr = String(cString: hostname)
					}
					else {
						var hostnameString = String(cString: hostname)
						if let weird_en0AtEnd = hostnameString.firstIndex(of: "%") {
							hostnameString = String(hostnameString[hostnameString.startIndex..<weird_en0AtEnd])
						}
						addressStruct.ipV6Addr = hostnameString
					}
				}
			}
		}
		if addressStruct.ipV4Addr != nil || addressStruct.ipV6Addr != nil {
			return addressStruct
		}
		return nil
	}

	// Called on the DataManager's dispatch queue.
	func openDirectCallWSServer(call: CurrentCallInfo) {
        do {
			let parameters = NWParameters(tls: nil)
			parameters.allowLocalEndpointReuse = true
			parameters.includePeerToPeer = true
			let wsOptions = NWProtocolWebSocket.Options()
			wsOptions.autoReplyPing = true
			parameters.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)
        
            guard let port = NWEndpoint.Port(rawValue: 80) else {
            	logger.error("Could not create port for websocket server.")
            	call.setError(ServerError("Could not create port for websocket server."))
            	return
			}
			call.portListener = try NWListener(using: parameters, on: port)
      		call.portListener?.newConnectionHandler = { newConnection in
            	self.logger.info("iOS Socket Server got new incoming Connection.")
            	call.connection = newConnection
            	
				newConnection.stateUpdateHandler = { [weak self] state in
					guard let self = self else { return }
                    switch state {
                    case .ready:
                        self.logger.info("iOS Socket Server: Client ready")
						call.callStartTime = Date()
						self.receiveMessageFromDirectSocket()
						if let jsonData = try? Settings.v3Encoder.encode(PhoneSocketStartData()) {
							self.sendDataPacket(data: jsonData, isAudio: false)
						}
                    case .failed(let error):
                        self.logger.info("Client connection failed \(error.localizedDescription)")
                    case .waiting(let error):
                        self.logger.info("Waiting for long time \(error.localizedDescription)")
					case .setup:
                        self.logger.info("iOS Socket Server: In Setup State")
					case .preparing:
                        self.logger.info("iOS Socket Server: In preparing state")
					case .cancelled:
                        self.logger.info("iOS Socket Server: In cancelled state")
					default:
						break
                    }
                }

                newConnection.start(queue: self.dispatchQueue)
     		}
        
			call.portListener?.stateUpdateHandler = { [weak self] state in
				switch state {
				case .ready:
					self?.logger.info("portListener Ready")
				case .failed(let error):
					self?.logger.info("portListener failed with \(error.localizedDescription)")
				default:
					break
				}
			}
        
			call.portListener?.start(queue: dispatchQueue)
		}
		catch {
			logger.error("Error opening Websocket Server: \(error)")
			call.setError(error)
		}
	}
	
	// Gets called when the OS tells us the user chose to answer the incoming call.
	func openAnswerSocket() {
		guard let currentCall = self.currentCall else {
			return
		}
		currentCall.answeredCall = true
		var socketRequest: URLRequest
		if let directURLStr = currentCall.serverURL, let directURL = URL(string: directURLStr) {
			socketRequest = URLRequest(url: directURL)
			
			// If we're opening a direct phone-to-phone socket, tell the server we've answered the call
			var notifyRequest = NetworkGovernor.buildTwittarRequest(withPath: "/api/v3/phone/answer/\(currentCall.callUUID)", query: nil)
			NetworkGovernor.addUserCredential(to: &notifyRequest)
			notifyRequest.httpMethod = "POST"
			NetworkGovernor.shared.queue(notifyRequest) { (package: NetworkResponse) in
			}
		}
		else {
			socketRequest = NetworkGovernor.buildTwittarRequest(withPath: "/api/v3/phone/socket/answer/\(currentCall.callUUID)", query: nil, webSocket: true)
			NetworkGovernor.addUserCredential(to: &socketRequest)
		}
		NetworkGovernor.shared.queue(socketRequest) { (package: NetworkResponse) in
			self.dispatchQueue.async {
				if let error = NetworkGovernor.shared.parseServerError(package) {
					NetworkLog.error(error.localizedDescription)
					currentCall.setError(error)
				}
				else if let socket = package.socket {
					currentCall.socket = socket
					self.receiveMessageFromServerSocket()
				}
			}
		}	
	}
	
	func endCall(reason: CXCallEndedReason? = nil) {
		if let callID = self.currentCall?.callUUID 	{
			logger.info("Reporting call ended.")
			provider.reportCall(with: callID, endedAt: Date(), reason: reason ?? .remoteEnded)
		}

		// If we have a open talk socket, close it. Otherwise, send a "decline" message to the server.
		if let socket = self.currentCall?.socket {
			socket.cancel(with: .goingAway, reason: nil)
		}
		else if let callID = currentCall?.callUUID, currentCall?.callStartTime == nil {
			// If we didn't answer the call (and send 'call answered', send a 'decline' message.
			var request = NetworkGovernor.buildTwittarRequest(withPath: "/api/v3/phone/decline/\(callID)", query: nil)
			request.httpMethod = "POST"
			NetworkGovernor.addUserCredential(to: &request)
			NetworkGovernor.shared.queue(request) { (package: NetworkResponse) in
				if let error = NetworkGovernor.shared.parseServerError(package) {
					NetworkLog.error(error.localizedDescription)
				}
			}	
		}
		if let listener = currentCall?.portListener {
			listener.cancel()
		}
		if let conn = currentCall?.connection {
			conn.cancel()
		}
		self.currentCall = nil
	}
	
	// Called by NetworkGovernor when a socket gets closed
	func notifyWhenSocketClosed(socket: URLSessionWebSocketTask) {
		// If it's the socket we were using for comms, end the call
		if let currentCall = self.currentCall, currentCall.socket?.taskIdentifier == socket.taskIdentifier {
			endCall()
		}
	}
	
// MARK: Socket Send/Receive
	func receiveMessageFromServerSocket() {
		guard let socket = currentCall?.socket else {
			return
		}
		socket.receive { [weak self] result in
			guard let self = self else { return }
			// self.logger.info("Got some data incoming!!!! ")
			switch result {
				case .failure(let error):
					self.logger.info("Error during websocket receive: \(error.localizedDescription)")
					self.currentCall?.setError(error)
					self.endCall()
					return
				case .success(let msg):
					if case let .data(msgData) = msg {
						self.processIncomingSocketMessage(msgData)
					}
			}
			self.receiveMessageFromServerSocket()
		}
	}
	
	func receiveMessageFromDirectSocket() {
		// _ completeContent: Data?, _ contentContext: NWConnection.ContentContext?, _ isComplete: Bool, _ error: NWError?
		// print("Start of the receiveMessageFromDirectSocket() method.")
		guard let conn = currentCall?.connection else {
			logger.info("No connection in the call object?")
			return
		}
		conn.receiveMessage { (data, context, isComplete, error) in
			// logger.info("Received a new message from client")
			if let data = data {
				self.processIncomingSocketMessage(data)
				self.receiveMessageFromDirectSocket()
			}
			else if let error = error {
				self.logger.info("Connection.receiveMessage returned an error: \(error)")
				self.currentCall?.setError(error)
				self.endCall()
			}
		}
	}
	
	func processIncomingSocketMessage(_ data: Data) {
		if let startPacket = try? Settings.v3Decoder.decode(PhoneSocketStartData.self, from: data) {
			self.currentCall?.callStartTime = startPacket.phonecallStartTime
		}
		else if data.count > 4 {
			if self.currentCall?.callStartTime == nil {
				// Ignore audio packets that come in before we receive the start packet.
				return
			}
			let frameCount = data.withUnsafeBytes { rawBuffer in
				rawBuffer.load(as: UInt32.self)
			}
			let networkBufData = data.subdata(in: 4..<(4 + Int(frameCount) * 2))
			
			self.bufferLock.lock()
			self.networkData.append(networkBufData)
			self.bufferLock.unlock()
//				logger.info("Write \(frameCount) frames into buffers")
		}
		else {
			logger.info("Too-small packet for audio data.")
		}
	}
	
	func sendDataPacket(data: Data, isAudio: Bool = true) {
		guard let currentCall = currentCall, !isAudio || (currentCall.callStartTime != nil) else {
			return
		}
		if let directServerConnection = currentCall.connection {
			let message = NWProtocolWebSocket.Metadata(opcode: .binary)
			let context = NWConnection.ContentContext(identifier: "send",  metadata: [message])
			directServerConnection.send(content: data, contentContext: context, completion: .contentProcessed({ error in
				if let error = error {
					self.logger.info("Error during send: \(error)")
					if case let .posix(posixError) = error, posixError == .ENOTCONN {
					} 
					else {
						self.currentCall?.setError(error)
					}
					self.endCall()
				}
			}))
		}
		else {
			currentCall.socket?.send(.data(data)) { error in
				self.logger.info("[\(Date())] Sent packet: \(data.count / 2) frames. error: \(String(describing: error))")
			}
		}
	}
	
// MARK: - Audio
	func configureAudioSession(audioSession: AVAudioSession) {
		do {
			try audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetooth])
			try audioSession.setActive(true)			
			networkData.removeAll()
			
			// Engine
			engine = AVAudioEngine()

			// Get the native audio format of the engine's input bus.
//			try engine.inputNode.setVoiceProcessingEnabled(true)
			let inputFormat = engine.inputNode.outputFormat(forBus: 0)
			let networkFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000.0, channels: 1, interleaved: true)!
			let converter = AVAudioConverter(from: inputFormat, to: networkFormat)!
	
//			engine.connect(engine.inputNode, to: engine.outputNode, format: nil)
			engine.inputNode.isVoiceProcessingAGCEnabled = true
//			try engine.inputNode.setVoiceProcessingEnabled(true)

			engine.inputNode.installTap(onBus: 1, bufferSize: 256, format: nil) { (buffer: AVAudioPCMBuffer, time: AVAudioTime) in
				let networkBufferFrames = AVAudioFrameCount(Double(buffer.frameLength) * networkFormat.sampleRate / inputFormat.sampleRate)
				guard // let socket = self.currentCall?.socket, 
						let networkBuffer = AVAudioPCMBuffer(pcmFormat: networkFormat, frameCapacity: networkBufferFrames) else {
					return
				}
				var error: NSError? = nil
				var suppliedBuffer = false
				converter.convert(to: networkBuffer, error: &error) { inNumPackets, outStatus in
					if !suppliedBuffer {
						outStatus.pointee = AVAudioConverterInputStatus.haveData
						suppliedBuffer = true
						return buffer
					}
					else {
						outStatus.pointee = AVAudioConverterInputStatus.noDataNow
						return nil
					}
				}

				if error != nil {
					self.logger.info("\(error!.localizedDescription)")
				}
				else if let channelData = networkBuffer.int16ChannelData {
					var packet = Data()
					var frames: Int32 = Int32(networkBuffer.frameLength)
					withUnsafeBytes(of: &frames, { packet.append(contentsOf: $0) })
					let buf: UnsafeMutablePointer<Int16> = channelData[0]
					let rawBuf = UnsafeRawPointer(buf)
					packet.append(Data(bytes: rawBuf, count: Int(frames) * 2))
					self.sendDataPacket(data: packet)
				//	socket.send(.data(packet)) { error in
				//		print("[\(Date())] Sent packet: \(frames) frames. error: \(String(describing: error))")
				//	}
				}
				else {
					self.logger.info("NO DATA IN 16BIT BUFFER")
				}
			}
			
			let sourceNode = AVAudioSourceNode() { silence, timeStamp, frameCount, audioBufferList -> OSStatus in
				let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
					self.bufferLock.lock()
					let framesInBuf = self.networkData.count / 2
					let framesToCopy = min(Int(frameCount), framesInBuf)
					let destRawPtr: UnsafeMutableRawPointer = ablPointer[0].mData!
					let destPtr: UnsafeMutablePointer<UInt8> = destRawPtr.bindMemory(to: UInt8.self, capacity: framesToCopy * 2)
					self.networkData.copyBytes(to: destPtr, from: 0..<(framesToCopy * 2))
					
					// Zero-fill dest buf if framesToCopy < frameCount

					// If we have more than .25 seconds worth in the buffer, dump it all.
					if framesInBuf > 16000 / 4 {
						self.networkData.removeAll()
					}
					else {
						self.networkData.removeSubrange(0..<(framesToCopy * 2))
					}
					
//					logger.info("[\(Date())] Copied \(framesToCopy) frames out of buffer, now \(self.networkData.count / 2) frames in buf.")
					self.bufferLock.unlock()
				return noErr
			}
			engine.attach(sourceNode)
			engine.connect(sourceNode, to: engine.mainMixerNode, format: networkFormat)			
		} 
		catch {
			logger.error("Failed to setup audio session: \(error, privacy: .public)")
			self.currentCall?.setError(ServerError("Failed to setup audio session: \(error)"))
		}
		engine.prepare()
	}
	
	func startAudio(audioSession: AVAudioSession) {
		do {
			try engine.start()
			logger.info("\(self.engine.description, privacy: .public)")
		}
		catch {
			logger.info("Error during startAudio: \(error)")
			self.currentCall?.setError(ServerError("Failed to setup audio: \(error)"))
		}
	}

	func stopAudio() {
		engine.inputNode.removeTap(onBus: 0)
		engine.stop()
		try? AVAudioSession.sharedInstance().setActive(false)
	}
}

extension PhonecallDataManager: CXProviderDelegate {
	func providerDidReset(_ provider: CXProvider) {
		logger.info("Got told providerDidReset.")
		stopAudio()
		endCall()
	}
	
    func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
		logger.info("Got told to start a call.")
		action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
		logger.info("Got told CXAnswerCallAction.")
		openAnswerSocket()
		action.fulfill()
    }
    
    // Gets called by provider when incoming call is ringing, as well as during call.
    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
		logger.info("Got told CXEndCallAction.")
		endCall()
		action.fulfill()
    }
    
    func provider(_ provider: CXProvider, perform action: CXSetHeldCallAction) {
		logger.info("Got told CXSetHeldCallAction.")
		action.fulfill()
    }
    
    func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
		logger.info("Got told CXSetMutedCallAction.")
		action.fulfill()
    }
    
    func provider(_ provider: CXProvider, timedOutPerforming action: CXAction) {
    	switch action {
    		case is CXStartCallAction: logger.info("Got told CXStartCallAction timed out.")
    		case is CXAnswerCallAction: logger.info("Got told CXAnswerCallAction timed out.")
    		case is CXEndCallAction: logger.info("Got told CXEndCallAction timed out.")
    		default: logger.info("Got told timed out.")
    	}
    }
    
    func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
		configureAudioSession(audioSession: audioSession)
    	startAudio(audioSession: audioSession)
		logger.info("Got told didActivate audio session.")
    }
    
	func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
		stopAudio()
		logger.info("Got told didDeactivate audio session.")
    }
}

// MARK: - V3 Socket Structs

struct PhoneSocketStartData: Codable {
	var phonecallStartTime: Date = Date()	
}

struct PhoneSocketAudioData: Codable {
	var numFrames: Int
	var leftFrames: Data
	var rightFrames: Data
}

struct PhoneSocketServerAddress: Codable {
	var ipV4Addr: String?
	var ipV6Addr: String?
}

extension PhoneSocketServerAddress : CustomDebugStringConvertible {	
	var debugDescription: String {
		"PhoneSocketServerAddress. v4: \(ipV4Addr ?? "<none>") v6: \(ipV6Addr ?? "<none>")"
	}
}

// UI
// 	Mute
// 	Audio Out
// 	Other Party In Call, name and icon
//	Hold?
//	Hangup

// MARK: - SinkNode test
//			let sinkNode = AVAudioSinkNode() { timeStamp, frameCount, audioBufferList -> OSStatus in
//	//			let ablPointer = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: audioBufferList))
//				guard let inputPCMBuffer = AVAudioPCMBuffer(pcmFormat: inputFormat, bufferListNoCopy: audioBufferList) else {
//					return noErr
//				}
//				let networkBufferFrames = AVAudioFrameCount(Double(inputPCMBuffer.frameLength) * networkFormat.sampleRate / inputFormat.sampleRate)
//				guard let socket = self.currentCall?.socket, 
//						let networkBuffer = AVAudioPCMBuffer(pcmFormat: networkFormat, frameCapacity: networkBufferFrames) else {
//					return noErr
//				}
//				var error: NSError? = nil
//				var suppliedBuffer = false
//				converter.convert(to: networkBuffer, error: &error) { inNumPackets, outStatus in
//					if !suppliedBuffer {
//						outStatus.pointee = AVAudioConverterInputStatus.haveData
//						suppliedBuffer = true
//						return inputPCMBuffer
//					}
//					else {
//						outStatus.pointee = AVAudioConverterInputStatus.noDataNow
//						return nil
//					}
//				}
//
//				if let error = error {
//					logger.info(error.localizedDescription)
//				}
//				else if let channelData = networkBuffer.int16ChannelData {
//					var packet = Data()
//					var frames: Int32 = Int32(networkBuffer.frameLength)
//					withUnsafeBytes(of: &frames, { packet.append(contentsOf: $0) })
//					let buf: UnsafeMutablePointer<Int16> = channelData[0]
//					let rawBuf = UnsafeRawPointer(buf)
//					packet.append(Data(bytes: rawBuf, count: Int(frames) * 2))
//					socket.send(.data(packet)) { error in
//						logger.info("[\(Date())] Sent packet: \(frames) frames. error: \(String(describing: error))")
//					}
//				}
//				return noErr
//				
//				// Fills buffer with whitenoise before sending to network.
////				let buf: AudioBuffer = ablPointer[0]
////				let rawDataPtr: UnsafeMutableRawPointer = buf.mData!
////				let newBufPtr: UnsafeMutablePointer<Int16> = rawDataPtr.bindMemory(to: Int16.self, capacity: Int(frameCount))
////				for index in 0..<frameCount {
////					newBufPtr[Int(index)] = Int16.random(in: -32000...32000)
////				}
//			}
			

//			let inputMixer = AVAudioMixerNode()
//			engine.attach(inputMixer)
//			engine.attach(sinkNode)
//			engine.connect(engine.inputNode, to: inputMixer, fromBus: 0, toBus: 0, format: inputFormat)
//			engine.connect(engine.inputNode, to: sinkNode, format: nil)
//			engine.connect(inputMixer, to: sinkNode, format: networkFormat)
//			inputMixer.volume = 0.1

