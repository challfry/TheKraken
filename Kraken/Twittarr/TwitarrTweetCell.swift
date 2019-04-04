//
//  TwitarrTweetCell.swift
//  Kraken
//
//  Created by Chall Fry on 3/30/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit

class TwitarrTweetCell: UICollectionViewCell, UITextViewDelegate {
	@IBOutlet var titleLabel: UITextView!
	@IBOutlet var tweetTextView: UITextView!
	@IBOutlet var userAvatar: UIImageView!
	@IBOutlet var postImage: UIImageView!

    var tweetModel: TwitarrV2Post? {
    	didSet {
    		titleLabel.text = tweetModel?.author.displayName
    		if let text = tweetModel?.text {
	    		tweetTextView.attributedText = cleanupText(text)
	    		
				let fixedWidth = tweetTextView.frame.size.width
				let newSize = tweetTextView.sizeThatFits(CGSize(width: fixedWidth, height: CGFloat.greatestFiniteMagnitude))
				tweetTextView.frame.size = CGSize(width: max(newSize.width, fixedWidth), height: newSize.height)
	    		
			}
    		if let username = tweetModel?.author.username, let user = UserManager.shared.user(username) {
	    		user.loadUserThumbnail()
	    		user.tell(self, when:"thumbPhoto") { observer, observed in
					observer.userAvatar.image = observed.thumbPhoto
	    		}?.schedule()
			}
			
			if let photo = tweetModel?.photo {
				self.postImage.isHidden = false
				ImageManager.shared.image(withSize:.medium, forKey: photo.id) { image in
					self.postImage.image = image
				}
			}
			else {
				self.postImage.image = nil
				self.postImage.isHidden = true
			}

			titleLabel.textContainerInset = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
			tweetTextView.textContainerInset = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
    	}
	}
	
	override func preferredLayoutAttributesFitting(_ layoutAttributes: UICollectionViewLayoutAttributes) 
			-> UICollectionViewLayoutAttributes {
		setNeedsLayout()
		layoutIfNeeded()
		let size = contentView.systemLayoutSizeFitting(layoutAttributes.size)
		var frame = layoutAttributes.frame
		frame.size.height = ceil(size.height)
		layoutAttributes.frame = frame
//		print(frame)
		return layoutAttributes
	}
	
	func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange, 
			interaction: UITextItemInteraction) -> Bool {
        UIApplication.shared.open(URL, options: [:])
        return false
    }
		
    func cleanupText(_ text:String) -> NSAttributedString {
    	let outputString = NSMutableAttributedString()
    	let openTag = CharacterSet(charactersIn: "<")
    	let closeTag = CharacterSet(charactersIn: ">")
    	let emptySet = CharacterSet(charactersIn: "")
    	var tagStack = [String]()
    	
    	// The jankiest HTML fragment parser I've written this week.
     	let scanner = Scanner(string: text)
     	scanner.charactersToBeSkipped = emptySet
		while !scanner.isAtEnd {
			if let tempString = scanner.scanUpToCharactersFrom(openTag) {
				if tagStack.isEmpty {
					let attrString = NSAttributedString(string: tempString)
					outputString.append(attrString)
				}
				else {
    				let tagAttrs: [NSAttributedString.Key : Any] = [ .link : tempString ]
					let attrString = NSAttributedString(string: tempString, attributes: tagAttrs)
					outputString.append(attrString)
				}
			}
			scanner.scanString("<", into: nil)
	   		if let tagContents = scanner.scanUpToCharactersFrom(closeTag) {
	   			let firstSpace = tagContents.firstIndex(of: " ") ?? tagContents.endIndex
				let tagName = tagContents[..<firstSpace]
				if tagName.hasPrefix("/") {
					_ = tagStack.popLast()
				}
				else {
					tagStack.append(String(tagName))
				}
			}
		   	scanner.scanString(">", into: nil)
	   	}
    	
    	return outputString
    }
    
}

extension Scanner {
  
  @discardableResult func scanUpToCharactersFrom(_ set: CharacterSet) -> String? {
    var result: NSString?                                                           
    return scanUpToCharacters(from: set, into: &result) ? (result as String?) : nil 
  }
  
  func scanUpTo(_ string: String) -> String? {
    var result: NSString?
    return self.scanUpTo(string, into: &result) ? (result as String?) : nil
  }
  
  func scanDouble() -> Double? {
    var double: Double = 0
    return scanDouble(&double) ? double : nil
  }
}



// "<a class=\"tweet-url username\" href=\"#/user/profile/kvort\">@kvort</a> Okay. This is a reply."
