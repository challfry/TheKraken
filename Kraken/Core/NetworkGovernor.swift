//
//  NetworkGovernor.swift
//  Kraken
//
//  Created by Chall Fry on 3/23/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import SystemConfiguration
import Foundation


// Note 1: This is ONLY for server errors--that is error responses that come from the server, usually with 
// an HTTP status of 300 or more. NOT for networking errors.
// Note 2: Error-conforming objects are often enums in Swift, but we don't actually have a use case for this
// here. UI-level code generally treats all server errors the same, but wants good description strings.
@objc class ServerError: NSObject, Error {
	var httpStatus: Int?
	var errorString: String						// All errors, concatenated.
	dynamic var fieldErrors: [String: String]?

	init(_ error: String) {
		errorString = error
		super.init()
	}

	override init() {
		errorString = ""
		super.init()
	}
	
	// Gets the part of the error that applies to the whole operation. Should be used in cases where the field errors
	// will be shown separately.
	func getGeneralError() -> String {
		if let fields = fieldErrors {
			return fields["general"] ?? ""
		}
		return errorString
	}
	
	// Concats everything into a single error string.
	func getCompleteError() -> String {
//		if let generalErrors = fieldErrors?["general"] {
//			let errorString = generalErrors
//			return errorString
//		}
//		else if let fieldCount = fieldErrors?.count, fieldCount > 0 {
//			if fieldCount == 1, let fieldName = fieldErrors?.first?.key {
//				return "Error in field \(fieldName)"
//			}
//			else {
//				return "\(fieldCount) fields have errors"
//			}
//		}
//		else {
//			return "Unknown Error"
//		}
		return errorString
	}
	
	override var debugDescription: String {
		get {
			return getCompleteError()
		}
	}
}

@objc class NetworkError: NSObject, Error {
	var errorString: String?
	
	init(_ str: String?) {
		errorString = str
	}
	
	func getErrorString() -> String? {
		return errorString
	}
}

// The response type passed back from network calls. Note that the network governor does its own handling of
// network errors, and the results are displayed app-wide. Most handlers can ignore the networkError. If 
// the network error is set, the response and data are likely nil.
struct NetworkResponse {
	var response: HTTPURLResponse?
	var data: Data?
	var networkError: NetworkError?
	var serverError: ServerError?
	var socket: URLSessionWebSocketTask?
	
	func debugPrintData() -> String {
		if let d = data {
			return String(decoding: d, as: UTF8.self)
		}
		else {
			return "No Data"
		}
	}
	
	func getAnyError() -> Error? {
		return networkError ?? serverError
	}
}


// All networking calls the app makes should funnel through here. This is so we can do global traffic
// management, analysis, and logging. 
@objc class NetworkGovernor: NSObject {
	static let shared = NetworkGovernor()
	var session: URLSession
	var reachability: SCNetworkReachability?
	
	//
	@objc public enum ConnectionState: Int {
		case canConnect					// Last attempt to connect succeeded, and no reachability change since.
		case maybeConnect				// Reachability changed since we last spoke to server so ... ??
		case noConnection				// 
	}
	@objc dynamic var connectionState = ConnectionState.noConnection
	@objc dynamic var connectedViaWIFI: Bool = false
	
	private var internalConnectionState = ConnectionState.noConnection
	
		// lastError here will ONLY ever refer to networking errors. If we talk to the server and get an HTTP
		// or other server error, it appears elsewhere.
	var lastError: Error?
	
	// Internal to NetworkGovenor. Associates a SessionTask with its reponse data and who to tell when it's done.
	// The Error in the Done Callback will only contain network 
	fileprivate struct InternalTask {
		let task: URLSessionTask
		var responseData: Data
		var doneCallbacks: [(NetworkResponse) -> Void]
	}
	private var activeTasks = [InternalTask]()
	private let activeTasksQ = DispatchQueue(label:"ActiveTask mutation serializer")
	
// MARK: Methods	
	override init() {
		session = URLSession.shared
		super.init()
	
//		let config = URLSessionConfiguration.background(withIdentifier: "Kraken_twitarrv2_background")
		let config = URLSessionConfiguration.default
		config.allowsCellularAccess	= true
		
		// This turns off cookies for this session.
		config.httpShouldSetCookies = false
		config.httpCookieAcceptPolicy = .never
		
		// Cancel calls after 20 seconds of no data.
		config.timeoutIntervalForRequest = 20.0
		
		session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
		
		if let hostname = Settings.shared.baseURL.host {
			reachability = SCNetworkReachabilityCreateWithName(nil, hostname)
		}
		else {
			var socketAddress = sockaddr()
			socketAddress.sa_len = UInt8(MemoryLayout<sockaddr>.size)
			socketAddress.sa_family = sa_family_t(AF_INET)
			reachability = SCNetworkReachabilityCreateWithAddress(nil, &socketAddress)
		}
		if let reachability = reachability {
			let callbackFn: SCNetworkReachabilityCallBack = { (reachabilityObj, flags, context) in 
				if let context = context {
					let selfish = Unmanaged<NetworkGovernor>.fromOpaque(context).takeUnretainedValue()
					selfish.newConnectionState(flags.contains(.reachable) ? .canConnect : .noConnection, isWifi: !flags.contains(.isWWAN))
				}
			}
			var context = SCNetworkReachabilityContext(version: 0,
					info: UnsafeMutableRawPointer(Unmanaged<NetworkGovernor>.passUnretained(self).toOpaque()), 
					retain: nil, release: nil, copyDescription: nil)
			SCNetworkReachabilitySetCallback(reachability, callbackFn, &context)
			SCNetworkReachabilitySetDispatchQueue(reachability, DispatchQueue.main)
			
			// Also call up front to get initial state
			var flags: SCNetworkReachabilityFlags = []
			if SCNetworkReachabilityGetFlags(reachability, &flags) {
				newConnectionState(flags.contains(.reachable) ? .canConnect : .noConnection, isWifi: !flags.contains(.isWWAN))
			}
		}
		
		Settings.shared.tell(self, when: "blockNetworkTraffic") { observer, observed in
			observer.newConnectionState(observer.internalConnectionState, isWifi: false)
		}
	}
	
	func newConnectionState(_ newState: ConnectionState, isWifi: Bool? = nil) {
		internalConnectionState = newState
		if let wifi = isWifi {
			connectedViaWIFI = wifi
		}
		if Settings.shared.blockNetworkTraffic {
			connectionState = .noConnection
		}
		else {
			connectionState = newState
		}
	}
	
	class func buildTwittarRequest(withPath path:String, query:[URLQueryItem]? = nil, webSocket: Bool = false) -> URLRequest {
	
		var components = URLComponents(url: Settings.shared.baseURL, resolvingAgainstBaseURL: false)
		components?.path = path
		components?.queryItems = query
		if webSocket {
			// Better if this looked at baseURL to see if it was https
			components?.scheme = "ws"
		}
		
		// Fallback, no query params
		let builtURL = components?.url ?? Settings.shared.baseURL.appendingPathComponent(path)
	//	let request = URLRequest(url:builtURL)
		let request = URLRequest(url: builtURL, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData)
		return request
	}

	class func buildTwittarRequest(withEscapedPath path:String, query:[URLQueryItem]? = nil) -> URLRequest {
	
		var components = URLComponents(url: Settings.shared.baseURL, resolvingAgainstBaseURL: false)
		components?.percentEncodedPath = path
		components?.queryItems = query
		
		// Fallback, no query params
		let builtURL = components?.url ?? Settings.shared.baseURL.appendingPathComponent(path)
	//	let request = URLRequest(url:builtURL)
		let request = URLRequest(url:builtURL, cachePolicy:.reloadIgnoringLocalAndRemoteCacheData)
		return request
	}
	
	// Depending on what the server wants, this could add a query parameter, a HTTP header, or a cookie.
	// In V2 it works by adding a URL query parameter. V3 adds a "Authorization" HTTP header.
	// The idea is that this fn can mutate the request however necessary.
	class func addUserCredential(to request: inout URLRequest, forUser: KrakenUser? = nil) {
		// We usually add the current user's creds; some deferred PostOps may need to run for an author
		// other than the current user.
		let userToAuth = forUser ?? CurrentUser.shared.loggedInUser
		// We can only add user creds if we're logged in--otherwise, we return request unchanged.
		guard let loggedInUserToAuth = userToAuth as? LoggedInKrakenUser, let authKey = loggedInUserToAuth.authKey else {
			return
		}
	
		request.addValue("Bearer \(authKey)", forHTTPHeaderField: "Authorization")
	}
	
	// All network calls should funnel through here.
	func queue(_ request:URLRequest, _ done: @escaping (NetworkResponse) -> Void) {

		// A quick way to test no-network conditions	
		if Settings.shared.blockNetworkTraffic {
			done(NetworkResponse(response: nil, data: nil, networkError: NetworkError("Error: Testing network blocked condition")))
			return
		}

		activeTasksQ.async {
			// If there's already a request outstanding for this exact URL, de-duplicate it here
			for taskIndex in 0..<self.activeTasks.count {
				if self.activeTasks[taskIndex].task.originalRequest?.url == request.url && 
						self.activeTasks[taskIndex].task.originalRequest?.httpMethod == request.httpMethod {
					self.activeTasks[taskIndex].doneCallbacks.append(done)
					NetworkLog.debug("De-duped network \(request.httpMethod ?? "") request to \(request.url?.absoluteString ?? "<unknown>")")
					return
				}
			}
		
			// Make a new InternalTask, and get the network request started
			var task: URLSessionTask
			if request.url?.scheme == "ws" || request.url?.scheme == "wss" {
				task = self.session.webSocketTask(with: request)
			}
			else {
				task = self.session.dataTask(with:request)
			}
			let queuedTask = InternalTask(task: task, responseData: Data(), doneCallbacks:[done])
			self.activeTasks.append(queuedTask)
			task.resume()
			
			let requestStr = request.httpMethod ?? ""
			NetworkLog.debug("Started network \(requestStr) request to \(request.url?.absoluteString ?? "<unknown>")")
		}
	}
	
	// Parses the responses as the different type of server errors that can happen.
	@discardableResult func parseServerError(_ package: NetworkResponse) -> ServerError? {
		if let response = package.response {
			if response.statusCode >= 300 {
				let resultError = ServerError()
				resultError.httpStatus = response.statusCode
				
				// Hopefully replaced with something better, see below
				resultError.errorString = "HTTP Error \(response.statusCode)"
				
				if let data = package.data, data.count > 0 {
//					print (String(decoding:data, as: UTF8.self))					
					if let errorInfo = try? Settings.v3Decoder.decode(TwitarrV3ErrorResponse.self, from: data) {
						resultError.errorString = errorInfo.reason
						resultError.fieldErrors = errorInfo.fieldErrors
					}
				}
				
				// Field errors from the server are almost always form input errors; don't log 'em.
				let serverError = resultError.errorString
				NetworkLog.error("Server Error:", ["Error" : serverError])
			
				return resultError
			}
		}
		
		return nil
	}
	
	func cancelAllTasks() {
		session.getAllTasks { tasks in
			for task in tasks {
				task.cancel()
			}
		}
	}
}

// MARK: URLSessionDelegate
extension NetworkGovernor: URLSessionDelegate {		
	//
    public func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
    	if let error = error {
	    	NetworkLog.error("URL Session became invalid.", ["error" : error])
		}
    }

    public func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, 
    		completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
		NetworkLog.debug("URLSession sent an URLAuthentication challenge.")
		completionHandler(.performDefaultHandling, nil)
	}

    public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
		NetworkLog.debug("urlSessionDidFinishEvents.")
    }
}

// MARK: URLSessionTaskDelegate
extension NetworkGovernor: URLSessionTaskDelegate {
	//
	public func urlSession(_ session: URLSession, task: URLSessionTask, willBeginDelayedRequest request: URLRequest, 
			completionHandler: @escaping (URLSession.DelayedRequestDisposition, URLRequest?) -> Void) {
//		NetworkLog.debug("urlSession willBeginDelayedRequest.")
		completionHandler(.continueLoading, request)
	}

    
    public func urlSession(_ session: URLSession, taskIsWaitingForConnectivity task: URLSessionTask) {
		NetworkLog.debug("urlSession taskIsWaitingForConnectivity.")
	}

    public func urlSession(_ session: URLSession, task: URLSessionTask, 
    		willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, 
    		completionHandler: @escaping (URLRequest?) -> Void)  {
		NetworkLog.debug("urlSession willPerformHTTPRedirection.")
	}

    public func urlSession(_ session: URLSession, task: URLSessionTask, 
    		didReceive challenge: URLAuthenticationChallenge, 
    		completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
		NetworkLog.debug("urlSession didReceive challenge.")
	}
    
    public func urlSession(_ session: URLSession, task: URLSessionTask, 
    		needNewBodyStream completionHandler: @escaping (InputStream?) -> Void) {
		NetworkLog.debug("urlSession needNewBodyStream.")
	}

	public func urlSession(_ session: URLSession, task: URLSessionTask, 
			didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
//		NetworkLog.debug("urlSession didSendBodyData.")
	}

	public func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
//		NetworkLog.debug("Collected metrics for task.", ["metrics" : metrics])		
	}

	public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
		let findOurTask: InternalTask? = activeTasksQ.sync {
			if let index = activeTasks.firstIndex(where: { $0.task.taskIdentifier == task.taskIdentifier } ) {
				let result = activeTasks.remove(at: index)
				return result
			}
			return nil
		}
		guard let foundTask = findOurTask else {
			return
		}
		
		// Error, in this context, only refers to networking errors. If the server produces a response, even 
		// if it's an error response, it's not an 'error'.
		lastError = error
		var networkError: NetworkError? 
    	if let error = error {
			NetworkLog.error("Task completed with error.", ["error" : error])
			if !(task is URLSessionWebSocketTask) {		// Websocket tasks break for reasons that aren't server disconnects
				newConnectionState(.noConnection)	
			}
			networkError = NetworkError(error.localizedDescription)
    		    		
    		// todo: real error handling here
    		
		}
		else {
			newConnectionState(.canConnect)	
		}
		
		//
		var responseData: Data? = foundTask.responseData
		if foundTask.responseData.count == 0 {
			responseData = nil
		}
		
		// According to docs, this will always be an HTTPURLResponse (or nil) for our HTTP calls. It's never an URLResponse.
		if let resp = task.response as? HTTPURLResponse {
		
			// Handle globally applicable status codes here
			if resp.statusCode == 401 {
				CurrentUser.shared.logoutUser(nil, sendLogoutMsg: false)
			}
			
			var responsePacket = NetworkResponse(response: resp, data: responseData, networkError: networkError)
			responsePacket.serverError = NetworkGovernor.shared.parseServerError(responsePacket)
			if let err =  responsePacket.serverError {
				NetworkLog.error(err.localizedDescription)
			}
			for doneCallback in foundTask.doneCallbacks {
				doneCallback(responsePacket)
			}
		}
		else {
			var responsePacket = NetworkResponse(response: nil, data: nil, networkError: networkError)
			for doneCallback in foundTask.doneCallbacks {
				doneCallback(responsePacket)
			}
		}
//		print (String(decoding:foundTask.responseData, as: UTF8.self))
	}
}

// MARK: URLSessionDataDelegate
extension NetworkGovernor: URLSessionDataDelegate {

	//
    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, 
    		completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
//		print (response)
		completionHandler(.allow)
	}

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
		activeTasksQ.async {
			if let foundIndex = self.activeTasks.firstIndex(where: { $0.task.taskIdentifier == dataTask.taskIdentifier } ) {
				self.activeTasks[foundIndex].responseData.append(data)
			}
		}
    	
//		print (String(decoding:data, as: UTF8.self))
    }
}

extension NetworkGovernor: URLSessionWebSocketDelegate {

	func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol: String?) {
		print("NetworkGovernor: socket opened.")
		let findOurTask: InternalTask? = activeTasksQ.sync {
			if let index = activeTasks.firstIndex(where: { $0.task.taskIdentifier == webSocketTask.taskIdentifier } ) {
				return activeTasks[index]
			}
			return nil
		}
		guard let foundTask = findOurTask else {
			return
		}
		
		var responsePacket = NetworkResponse(response: nil, data: nil, networkError: nil)
		responsePacket.socket = webSocketTask
		for doneCallback in foundTask.doneCallbacks {
			doneCallback(responsePacket)
		}
	}
	
	func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith: URLSessionWebSocketTask.CloseCode, reason: Data?) {
		print("NetworkGovernor: socket closed.")
		activeTasksQ.sync {
			if let index = activeTasks.firstIndex(where: { $0.task.taskIdentifier == webSocketTask.taskIdentifier } ) {
				activeTasks.remove(at: index)
			}
		}
		PhonecallDataManager.shared.notifyWhenSocketClosed(socket: webSocketTask)
	}
}

// MARK: - Twitarr V3 API Structs

struct TwitarrV3ErrorResponse: Codable {
	let error: Bool
	let reason: String
	let fieldErrors: [String : String]?
}
