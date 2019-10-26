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
	var errorString: String?
	dynamic var fieldErrors: [String: [String]]?

	init(_ error: String) {
		super.init()
		errorString = error
	}

	override init() {
		super.init()
	}
	
	func getErrorString() -> String {
		if let errorString = errorString {
			return errorString
		}
		else if let generalErrors = fieldErrors?["general"] {
			let errorString = generalErrors[0]
			return errorString
		}
		else {
			return "Unknown Error"
		}
	}
	
	override var debugDescription: String {
		get {
			return getErrorString()
		}
	}
}

@objc class NetworkError: NSObject, Error {
	var errorString: String?
	
	init(_ str: String?) {
		errorString = str
	}
}

// The response type passed back from network calls. Note that the network governor does its own handling of
// network errors, and the results are displayed app-wide. Most handlers can ignore the networkError. If 
// the network error is set, the response and data are likely nil.
struct NetworkResponse {
	var response: URLResponse?
	var data: Data?
	var networkError: NetworkError?
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
		config.allowsCellularAccess	= false
		
		// This turns off cookies for this session.
		config.httpShouldSetCookies = false
		config.httpCookieAcceptPolicy = .never
		
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
				
					if !flags.contains(.reachable) {
						selfish.connectionState = .noConnection
					}
					else {
						selfish.connectionState = .canConnect
					}
				}
			}
			var context = SCNetworkReachabilityContext(version: 0,
					info: UnsafeMutableRawPointer(Unmanaged<NetworkGovernor>.passUnretained(self).toOpaque()), 
					retain: nil, release: nil, copyDescription: nil)
			SCNetworkReachabilitySetCallback(reachability, callbackFn, &context)
			SCNetworkReachabilitySetDispatchQueue(reachability, DispatchQueue.main)
		}
	}
	
	class func buildTwittarV2Request(withPath path:String, query:[URLQueryItem]? = nil) -> URLRequest {
	
		var components = URLComponents(url: Settings.shared.baseURL, resolvingAgainstBaseURL: false)
		components?.path = path
		components?.queryItems = query
		
		// Fallback, no query params
		let builtURL = components?.url ?? Settings.shared.baseURL.appendingPathComponent(path)
	//	let request = URLRequest(url:builtURL)
		let request = URLRequest(url:builtURL, cachePolicy:.reloadIgnoringLocalAndRemoteCacheData)
		return request
	}
	
	// Depending on what the server wants, this could add a query parameter, a HTTP header, or a cookie.
	class func addUserCredential(to request: inout URLRequest)  {
		// We can only add user creds if we're logged in--otherwise, we return request unchanged.
		guard CurrentUser.shared.isLoggedIn(), let authKey = CurrentUser.shared.loggedInUser?.twitarrV2AuthKey else {
			return
		}
	
		if let url = request.url, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
			var query = components.queryItems ?? [URLQueryItem]()
			for index in 0..<query.count {
				if query[index].name == "key" {
					query.remove(at: index)
					break
				}
			}
			query.append(URLQueryItem(name: "key", value: authKey))
			components.queryItems = query
			request.url = components.url
		}
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
			for var activeTask in self.activeTasks {
				if activeTask.task.originalRequest?.url == request.url && 
						activeTask.task.originalRequest?.httpMethod == request.httpMethod {
					activeTask.doneCallbacks.append(done)
					NetworkLog.debug("De-duped network \(request.httpMethod ?? "") request to \(request.url?.absoluteString ?? "<unknown>")")
					return
				}
			}
		
			// Make a new InternalTask, and get the network request started
			let task = self.session.dataTask(with:request) 
			let queuedTask = InternalTask(task: task, responseData: Data(), doneCallbacks:[done])
				self.activeTasks.append(queuedTask)
			task.resume()
		
			NetworkLog.debug("Started network request to \(request.url?.absoluteString ?? "<unknown>")")
		}
	}
	
	// Parses the responses as the different type of server errors that can happen.
	@discardableResult func parseServerError(_ package: NetworkResponse) -> ServerError? {
		if let response = package.response as? HTTPURLResponse {
			if response.statusCode >= 300 {
				let resultError = ServerError()
				resultError.httpStatus = response.statusCode
				
				if let data = package.data, data.count > 0 {
//					print (String(decoding:data, as: UTF8.self))
					let decoder = JSONDecoder()
	
					// There's 3 types of error JSON that could happen. Single, Multi, and FieldTagged.
	
					// Single "error" = "message" in error response
					if let errorInfo = try? decoder.decode(TwitarrV2ErrorResponse.self, from: data) {
						resultError.errorString = errorInfo.error
					}
					
					// Multi Errors, an array of error strings.
					else if let errorInfo = try? decoder.decode(TwitarrV2ErrorsResponse.self, from: data) {
						var errorString = ""
						for multiError in errorInfo.errors {
							errorString.append(multiError + "\n")
						}
						resultError.errorString = errorString.isEmpty ? "Unknown error" : errorString
					}
					
					// Dictionary Errors. A dict of tagged errors. Tags *usually* refer to form fields.
					else if let errorInfo = try? decoder.decode(TwitarrV2ErrorDictionaryResponse.self, from: data) {
					
						resultError.fieldErrors = errorInfo.errors
						
						// Any errors in the "general" category get set in errorString
						if let generalErrors = errorInfo.errors["general"] {
							let errorString = generalErrors.reduce("") { $0 + $1 + "\n" }
							resultError.errorString = errorString.isEmpty ? "Unknown error" : errorString
						}
					}
					else {
						resultError.errorString = "HTTP Error \(response.statusCode)"
					}
				}
				else {
					// No body data in response -- make a generic error string
					resultError.errorString = "HTTP Error \(response.statusCode)"
				}
				
				// Field errors from the server are almost always form input errors; don't log 'em.
				if let serverError = resultError.errorString {
					NetworkLog.error("Server Error:", ["Error" : serverError])
				}
			
				return resultError
			}
		}
		
		return nil
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
    	if let error = error {
			NetworkLog.error("Task completed with error.", ["error" : error])		
    		connectionState = .noConnection
    		    		
    		// todo: real error handling here
    		
		}
		else {
			connectionState = .canConnect
		}
		
		//
		let responsePacket = NetworkResponse(response: task.response, data: foundTask.responseData, 
				networkError: NetworkError(error?.localizedDescription))

		for doneCallback in foundTask.doneCallbacks {
			doneCallback(responsePacket)
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
