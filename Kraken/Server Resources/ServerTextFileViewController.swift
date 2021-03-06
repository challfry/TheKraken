//
//  ServerTextFileViewController.swift
//  Kraken
//
//  Created by Chall Fry on 5/3/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit

class ServerTextFileViewController: UIViewController {

	@IBOutlet var textView: UITextView!
	@IBOutlet var navItem: UINavigationItem!
	@IBOutlet var loadingView: UIView!
	@IBOutlet var errorLabel: UILabel!
	
	@objc dynamic var parser: ServerTextFileParser?
	var titleText: String?
	var fileToLoad: String?

    override func viewDidLoad() {
        super.viewDidLoad()
        
        if let title = titleText {
	        navItem.title = title
		}
		else {
			if fileToLoad == "helptext.json" {
				navItem.title = "Twitarr Help"
			}
			else if fileToLoad == "codeofconduct.json" {
				navItem.title = "Code of Conduct"
			}
		}
        
        if let fileName = fileToLoad {
        	parser = ServerTextFileParser(forFile: fileName)
        }

        self.tell(self, when: "parser.fileContents") { observer, observed in 
        	observer.textView.attributedText = observed.parser?.fileContents
        }?.execute()

        self.tell(self, when: "parser.isFetchingData") { observer, observed in 
        	observer.loadingView.isHidden = observed.parser?.isFetchingData != true
        }?.execute()
        
        self.tell(self, when: "parser.lastError") { observer, observed in 
        	observer.errorLabel.isHidden = observed.parser?.lastError == nil
        	observer.errorLabel.text = "Could not load file \"\(observer.fileToLoad ?? "")\" from server. \(observed.parser?.lastError?.errorString ?? "")"
        }?.execute()
    }
    
    @IBAction func doneButton() {
    	dismiss(animated: true, completion: nil)
    }
    

}
