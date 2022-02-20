//
//  ServerTextFileViewController.swift
//  Kraken
//
//  Created by Chall Fry on 5/3/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit

struct ServerTextFileSeguePackage {
	var titleText: String?
	var fileToLoad: String?
}

class ServerTextFileViewController: UIViewController {

	@IBOutlet var textView: UITextView!
	@IBOutlet var navItem: UINavigationItem!
	@IBOutlet var loadingView: UIView!
	@IBOutlet var errorLabel: UILabel!
	
	@objc dynamic var parser: ServerTextFileParser?
	var package: ServerTextFileSeguePackage?

    override func viewDidLoad() {
        super.viewDidLoad()
        
        if let title = package?.titleText {
	        navItem.title = title
		}
		else {
			if package?.fileToLoad?.hasPrefix("twitarrhelptext") == true {
				navItem.title = "Twitarr Help"
			}
			else if package?.fileToLoad?.hasPrefix("codeofconduct") == true {
				navItem.title = "Code of Conduct"
			}
		}
        
        if let fileName = package?.fileToLoad {
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
        	observer.errorLabel.text = "Could not load file \"\(observer.package?.fileToLoad ?? "")\" from server. \(observed.parser?.lastError?.errorString ?? "")"
        }?.execute()
    }
    
    @IBAction func doneButton() {
    	dismiss(animated: true, completion: nil)
    }
    

}
