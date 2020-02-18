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

	var postToReport: KrakenManagedObject?

	
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
			textFileVC.fileToLoad = "codeofconduct"
			textFileVC.titleText = "Code Of Conduct"
			present(textFileVC, animated: true, completion: nil)
		}
	}
	
	@IBAction func sendReportButtonTapped(_ sender: Any) {
		let recipients = Set([PossibleKrakenUser(username: "moderator")])
		var subject: String = ""
		var message: String = ""
		if let tweetToReport = postToReport as? TwitarrPost {
			subject = "Reporting a Twitarr post by \(tweetToReport.author.username)"
			message.append("Twitarr post by \(tweetToReport.author.username)\n\n")
			message.append("Posted at \(tweetToReport.postDate()). Tweet text: \n\n\(tweetToReport.text)")
			if tweetToReport.photoDetails != nil {
				message.append("\n\n<Tweet has an attached photo>")
			}
			if let notes = textView.text, !notes.isEmpty {
				message.append("\n\nReporter comment: \(notes)")
			}
		}
		else if let forumPostToReport = postToReport as? ForumPost {
			subject = "Reporting a Forums post by \(forumPostToReport.author.username)"
			message.append("Reporting Forums post by \(forumPostToReport.author.username) in forum titled \"\(forumPostToReport.thread.subject)\".")
			message.append(" Posted at \(forumPostToReport.postDate()). Post text: \n\n\(forumPostToReport.text)")
			if forumPostToReport.photos.count > 0 {
				message.append("\n\n<Post has \(forumPostToReport.photos.count) attached photos>")
			}
			if let notes = textView.text, !notes.isEmpty {
				message.append("\n\nReporter comment: \(notes)")
			}
		}
		else {
			return
		}
		SeamailDataManager.shared.queueNewSeamailThreadOp(existingOp: nil, subject: subject, message: message, 
				recipients: recipients, done: postQueued)
	}
	
	func postQueued(_ post: PostOpSeamailThread?) {
		DispatchQueue.main.async {
			self.dismiss(animated: true, completion: nil)
		}
	}	
}
