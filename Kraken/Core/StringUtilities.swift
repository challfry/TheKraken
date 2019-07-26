//
//  StringUtilities.swift
//  Kraken
//
//  Created by Chall Fry on 5/18/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit

class StringUtilities {
 
    class func cleanupText(_ text:String, addLinks: Bool = true) -> NSMutableAttributedString {
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
				if tagStack.isEmpty || !addLinks {
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
    
	class func relativeTimeString(forDate: Date) -> String {
		let formatter = DateComponentsFormatter()
		formatter.unitsStyle = .full
		formatter.maximumUnitCount = 1
	//	formatter.allowsFractionalUnits = true
		formatter.allowedUnits = [.second, .minute, .hour, .day, .month, .year]
		if let relativeTimeStr = formatter.string(from: forDate, to: Date()) {
			let resultStr = relativeTimeStr + " ago"
			return resultStr
		}
		return "some time ago"
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

