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
	
	@objc dynamic var parser: ServerTextFileParser?
	var titleText: String?
	var fileToLoad: String?

    override func viewDidLoad() {
        super.viewDidLoad()
        navItem.title = "Code Of Conduct"
        
        if let fileName = fileToLoad {
        	parser = ServerTextFileParser(forFile: fileName)
        }

        self.tell(self, when: "parser.fileContents") { observer, observed in 
        	observer.textView.attributedText = observed.parser?.fileContents
        }?.execute()

        self.tell(self, when: "parser.isFetchingData") { observer, observed in 
        	observer.loadingView.isHidden = observed.parser?.isFetchingData != true
        }?.execute()
    }
    
    @IBAction func doneButton() {
    	dismiss(animated: true, completion: nil)
    }
    

}
