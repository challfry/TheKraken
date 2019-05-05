//
//  TwitarrTweetCell.swift
//  Kraken
//
//  Created by Chall Fry on 3/30/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit

class TwitarrTweetCell: BaseCollectionViewCell, UITextViewDelegate {
	@IBOutlet var titleLabel: UITextView!
	@IBOutlet var tweetTextView: UITextView!
	@IBOutlet var postImage: UIImageView!
	@IBOutlet var userButton: UIButton!
	
	var viewController: TwitarrViewController?
	
	private static let cellInfo = [ "tweet" : PrototypeCellInfo("TwitarrTweetCell") ]
	override class var validReuseIDDict: [ String: PrototypeCellInfo] { return TwitarrTweetCell.cellInfo }
	
	private static var prototypeCell: TwitarrTweetCell =
		UINib(nibName: "TwitarrTweetCell", bundle: nil).instantiate(withOwner: nil, options: nil)[0] as! TwitarrTweetCell

	static func makePrototypeCell(for collectionView: UICollectionView, indexPath: IndexPath) -> TwitarrTweetCell? {
		let cell = TwitarrTweetCell.prototypeCell
		return cell
	}

    var tweetModel: TwitarrPost? {
    	didSet {
    		titleLabel.text = tweetModel?.author.displayName
    		if let text = tweetModel?.text {
	    		tweetTextView.attributedText = cleanupText(text)
	    		
				let fixedWidth = tweetTextView.frame.size.width
				let newSize = tweetTextView.sizeThatFits(CGSize(width: fixedWidth, height: CGFloat.greatestFiniteMagnitude))
				tweetTextView.frame.size = CGSize(width: max(newSize.width, fixedWidth), height: newSize.height)
			}
			else {
				tweetTextView.attributedText = nil
			}
			
    		if let user = tweetModel?.author {
	    		user.loadUserThumbnail()
	    		user.tell(self, when:"thumbPhoto") { observer, observed in
					observer.userButton.setBackgroundImage(observed.thumbPhoto, for: .normal)
					observer.userButton.setTitle("", for: .normal)
	    		}?.schedule()
			}
			
			if let photo = tweetModel?.photoDetails {
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
	
	func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange, 
			interaction: UITextItemInteraction) -> Bool {
 //		UIApplication.shared.open(URL, options: [:])
 		viewController?.pushSubController(forFilterString: URL.absoluteString)
        return false
    }
    
   	@IBAction func showUserProfile() {
   		if let userName = tweetModel?.author.username {
			viewController?.pushUserProfileController(forUser: userName)
		}
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
