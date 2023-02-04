//
//  ReportContentViewController.swift
//  Kraken
//
//  Created by Chall Fry on 2/18/20.
//  Copyright © 2020 Chall Fry. All rights reserved.
//

import UIKit

class ReportContentViewController: UIViewController {
	@IBOutlet var textView: UITextView!

	var contentToReport: KrakenManagedObject?
	var lastError: Error?
	
	override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    override func viewDidAppear(_ animated: Bool) {
		textView.becomeFirstResponder()
	}
    
	@IBAction func closeButtonTapped(_ sender: Any) {
		dismiss(animated: true, completion: nil)
	}
	
	@IBAction func viewCodeOfConductButtonTapped(_ sender: Any) {
		let storyboard = UIStoryboard(name: "Main", bundle: nil)
		if let textFileVC = storyboard.instantiateViewController(withIdentifier: "ServerTextFileDisplay") as? ServerTextFileViewController {
			textFileVC.package = ServerTextFileSeguePackage(titleText: "Code of Conduct", fileToLoad: "codeofconduct.json")
			present(textFileVC, animated: true, completion: nil)
		}
	}
	
	@IBAction func sendReportButtonTapped(_ sender: Any) {
		var requestPath: String
		switch contentToReport {
		case let tweetToReport as TwitarrPost:
			requestPath = "/api/v3/twitarr/\(tweetToReport.id)/report"
		case let forumToReport as ForumThread:
			requestPath = "/api/v3/forum/\(forumToReport.id)/report"
		case let forumPostToReport as ForumPost:
			requestPath = "/api/v3/forum/post/\(forumPostToReport.id)/report"
		// LFGs and LFG posts are reportable; but not in Kraken yet

		case let userProfileToReport as KrakenUser:
			requestPath = "/api/v3/users/\(userProfileToReport.userID)/report"
		default:
			reportSent()
			return
		}
		var request = NetworkGovernor.buildTwittarRequest(withPath: requestPath)
		request.httpMethod = "POST"
		let postStruct = TwitarrV3ReportData(message: textView.text)
		let httpContentData = try! Settings.v3Encoder.encode(postStruct)
		request.httpBody = httpContentData
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		NetworkGovernor.addUserCredential(to: &request)
		NetworkGovernor.shared.queue(request) { (package: NetworkResponse) in
			if let error = NetworkGovernor.shared.parseServerError(package) {
				self.lastError = error
			}
			else {
				self.reportSent()
			}
		}

	}
	
	func reportSent() {
		DispatchQueue.main.async {
			self.dismiss(animated: true, completion: nil)
		}
	}	
}

public struct TwitarrV3ReportData: Codable {
    /// An optional message from the submitting user.
    var message: String
}
