//
//  ServerTextFileViewController.swift
//  Kraken
//
//  Created by Chall Fry on 5/3/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit
import WebKit

struct ServerTextFileSeguePackage {
	var titleText: String?
	var serverFilePath: String?
	var localFilePath: String?
}

class ServerTextFileViewController: UIViewController {

	@IBOutlet var textView: UITextView!
	@IBOutlet var navItem: UINavigationItem!
	@IBOutlet var loadingView: UIView!
	@IBOutlet var errorLabel: UILabel!
	@IBOutlet var webView: WKWebView!
	
	@objc dynamic var parser: ServerTextFileParser?
	var package: ServerTextFileSeguePackage?
	
	static func canShowFile(path: URL) -> Bool {
		let suffix = path.pathExtension
		if ["html", "pdf", ""].contains(suffix) {
			return true
		}
		if ServerTextFileParser.parseableFileTypes().contains(path.pathExtension) {
			return true
		}
		return false
	}	

    override func viewDidLoad() {
        super.viewDidLoad()
        
		var filePath: String = package?.localFilePath ?? package?.serverFilePath ?? ""
        var fileName: String
        var fileSuffix: String = ""
        
        // Do a bit of link-rewriting. 
		let fp = filePath.lowercased()
		if fp == "/about" {
			filePath = "/public/twitarrhelptext.md"
		}
		else if fp == "/codeofconduct" {
			filePath = "/public/codeofconduct.md"
		}
        
        // Determine the title
		fileName = filePath.split(separator: "/").last?.string ?? ""
		if !fileName.isEmpty {
			let fn = fileName.lowercased()
			fileSuffix = fn.split(separator: ".").last?.string ?? ""
		
			if let title = package?.titleText {
				navItem.title = title
			}
			else {
				if fn.hasPrefix("twitarrhelptext") {
					navItem.title = "Twitarr Help"
				}
				else if fn.hasPrefix("codeofconduct") {
					navItem.title = "Code of Conduct"
				}
				else if fn.hasPrefix("faq") {
					navItem.title = "FAQ"
				}
				else {
					navItem.title = fileName
				}
			}
		}
		
        
		if ServerTextFileParser.parseableFileTypes().contains(fileSuffix) {
			webView.isHidden = true
			if let localFP = package?.localFilePath {
				parser = ServerTextFileParser(forLocalFile: localFP)
			}
			else {
				parser = ServerTextFileParser(forServerPath: filePath)
			}
			
			self.tell(self, when: "parser.parsedContents") { observer, observed in 
				observer.textView.attributedText = observed.parser?.parsedContents
			}?.execute()

			self.tell(self, when: "parser.isFetchingData") { observer, observed in 
				observer.loadingView.isHidden = observed.parser?.isFetchingData != true
			}?.execute()
			
			self.tell(self, when: "parser.lastError") { observer, observed in 
				observer.errorLabel.isHidden = observed.parser?.lastError == nil
				observer.errorLabel.text = "Could not load file \"\(observer.package?.serverFilePath ?? "")\" from server. \(observed.parser?.lastError ?? "")"
			}?.execute()
		}
		else if fileSuffix == "" || fileSuffix == "html" || fileSuffix == "pdf" {
			// Show html in a web view
			webView.isHidden = false
			var components = URLComponents(url: Settings.shared.baseURL, resolvingAgainstBaseURL: false)
			components?.path = filePath
			let builtURL = components?.url ?? Settings.shared.baseURL.appendingPathComponent(filePath)
			webView.load(URLRequest(url: builtURL))

		}
		else {
//			if let url = URL(string: filePath, relativeTo: Settings.shared.settingsBaseURL) {
//				let doc = UIDocumentInteractionController(url: url)
//				doc.presentOptionsMenu(from: in:animated:)
//			}
		}
    }
        
    @IBAction func doneButton() {
    	dismiss(animated: true, completion: nil)
    }
    

}
