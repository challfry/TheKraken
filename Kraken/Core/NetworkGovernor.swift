//
//  NetworkGovernor.swift
//  Kraken
//
//  Created by Chall Fry on 3/23/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import Foundation



// All networking calls the app makes should funnel through here. This is so we can do global traffic
// management, analysis, and logging. 
class NetworkGovernor: NSObject {
	static let shared = NetworkGovernor()
	var session: URLSession
	
	struct InternalTask {
		let task: URLSessionTask
		var responseData: Data
		let doneCallback: (Data?, URLResponse?) -> Void
	}
	private var activeTasks = [InternalTask]()
	private let activeTasksQ = DispatchQueue(label:"ActiveTask mutation serializer")
	
	
	override init() {
		session = URLSession.shared
		super.init()
	
		let config = URLSessionConfiguration.background(withIdentifier: "Kraken_twitarrv2_background")
//		let config = URLSessionConfiguration.default
		config.allowsCellularAccess	= false
		session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
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
	
	func queue(_ request:URLRequest, _ done: @escaping (Data?, URLResponse?) -> Void) {
	
		// This is where we could check for duplicate request URLs...
	
		let task = session.dataTask(with:request) 
		let queuedTask = InternalTask(task: task, responseData: Data(), doneCallback:done)
		activeTasksQ.async {
			self.activeTasks.append(queuedTask)
		}
		task.resume()
		
		print ("Started network request to \(request.url?.absoluteString ?? "<unknown>")")
	}
	
}

extension NetworkGovernor: URLSessionDelegate {		
	//
    public func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
    	if let error = error {
	    	print (error)
		}
    }

    public func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, 
    		completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
		print ("didReceive challenge")
		completionHandler(.performDefaultHandling, nil)
	}

    public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
		print ("urlSessionDidFinishEvents")
    }
}

extension NetworkGovernor: URLSessionTaskDelegate {
	//
	public func urlSession(_ session: URLSession, task: URLSessionTask, willBeginDelayedRequest request: URLRequest, 
			completionHandler: @escaping (URLSession.DelayedRequestDisposition, URLRequest?) -> Void) {
//		print ("willBeginDelayedRequest")
		completionHandler(.continueLoading, request)
	}

    
    public func urlSession(_ session: URLSession, taskIsWaitingForConnectivity task: URLSessionTask) {
		print ("taskIsWaitingForConnectivity")
	}

    public func urlSession(_ session: URLSession, task: URLSessionTask, 
    		willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, 
    		completionHandler: @escaping (URLRequest?) -> Void)  {
		print ("willPerformHTTPRedirection")
		
	}

    public func urlSession(_ session: URLSession, task: URLSessionTask, 
    		didReceive challenge: URLAuthenticationChallenge, 
    		completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
		print ("didReceive challenge")
	}
    
    public func urlSession(_ session: URLSession, task: URLSessionTask, 
    		needNewBodyStream completionHandler: @escaping (InputStream?) -> Void) {
		print ("needNewBodyStream")
	}

	public func urlSession(_ session: URLSession, task: URLSessionTask, 
			didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
//		print("didSendBodyData")		
	}

	public func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
//		print(metrics)		
	}

	public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
		let findOurTask = activeTasksQ.sync {
			activeTasks.first(where: { $0.task.taskIdentifier == task.taskIdentifier } )
		}
		guard let foundTask = findOurTask else {
			return
		}
		
		// Error, in this context, only refers to networking errors. If the server produces a response, even 
		// if it's an error response, it's not an 'error'.
    	if let error = error {
    		print(error)
    		
    		// todo: real error handling here
    		
		}

		foundTask.doneCallback(foundTask.responseData, task.response)
//		print (String(decoding:foundTask.responseData, as: UTF8.self))
	}
}

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
