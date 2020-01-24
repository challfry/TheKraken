//
//  AboutViewController.swift
//  Kraken
//
//  Created by Chall Fry on 1/23/20.
//  Copyright © 2020 Chall Fry. All rights reserved.
//

import UIKit

class AboutViewController: UIViewController {
	@IBOutlet var textView: UITextView!
	
    override func viewDidLoad() {
        super.viewDidLoad()

		if let aboutTextURL = Bundle.main.url(forResource: "AboutText", withExtension: "md"), 
				let markdown = SwiftyMarkdown(url: aboutTextURL) {
			markdown.body.fontName = "Georgia"
			textView.attributedText = markdown.attributedString()
		}
    }
}
