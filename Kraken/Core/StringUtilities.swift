//
//  StringUtilities.swift
//  Kraken
//
//  Created by Chall Fry on 5/18/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit






class StringUtilities {

	static func applyMarkdownRules() {
	}

	struct HTMLTag {
		var tagName: String
		var position: Int
	}
	
	static var isoDateNoFraction = ISO8601DateFormatter()
	static var isoDateWithFraction: ISO8601DateFormatter {
		let formatter = ISO8601DateFormatter()
		formatter.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime, 
				.withTimeZone, .withFractionalSeconds]
		return formatter
	}
	
	static var validUsernameChars: CharacterSet {
        var usernameChars: CharacterSet = .init()
        usernameChars.insert(charactersIn: "-.+_")
    	usernameChars.formUnion(.alphanumerics)
        return usernameChars
    }

    // Defines a character set containing characters other than alphanumerics that are allowed
    // in a username. However, these characters cannot be at the start or end of a username.
    static var usernameSeparators: CharacterSet {
        var separatorChars: CharacterSet = .init()
        separatorChars.insert(charactersIn: "-.+_")
        return separatorChars
    }
        
	static let genericUrlRegex = {
		let genericUrlRegexStr = """
				(?i)\\b((?:https?:(?:/{1,3}|[a-z0-9%])|[a-z0-9.\\-]+[.](?:com|net|org|edu|gov|mil|aero|asia|biz|cat|coop|info|int|jobs|mobi|museum|name|post|pro|tel|travel|xxx|ac|ad|ae|af|ag|ai|al|am|an|ao|aq|ar|as|at|au|aw|ax|az|ba|bb|bd|be|bf|bg|bh|bi|bj|bm|bn|bo|br|bs|bt|bv|bw|by|bz|ca|cc|cd|cf|cg|ch|ci|ck|cl|cm|cn|co|cr|cs|cu|cv|cx|cy|cz|dd|de|dj|dk|dm|do|dz|ec|ee|eg|eh|er|es|et|eu|fi|fj|fk|fm|fo|fr|ga|gb|gd|ge|gf|gg|gh|gi|gl|gm|gn|gp|gq|gr|gs|gt|gu|gw|gy|hk|hm|hn|hr|ht|hu|id|ie|il|im|in|io|iq|ir|is|it|je|jm|jo|jp|ke|kg|kh|ki|km|kn|kp|kr|kw|ky|kz|la|lb|lc|li|lk|lr|ls|lt|lu|lv|ly|ma|mc|md|me|mg|mh|mk|ml|mm|mn|mo|mp|mq|mr|ms|mt|mu|mv|mw|mx|my|mz|na|nc|ne|nf|ng|ni|nl|no|np|nr|nu|nz|om|pa|pe|pf|pg|ph|pk|pl|pm|pn|pr|ps|pt|pw|py|qa|re|ro|rs|ru|rw|sa|sb|sc|sd|se|sg|sh|si|sj|Ja|sk|sl|sm|sn|so|sr|ss|st|su|sv|sx|sy|sz|tc|td|tf|tg|th|tj|tk|tl|tm|tn|to|tp|tr|tt|tv|tw|tz|ua|ug|uk|us|uy|uz|va|vc|ve|vg|vi|vn|vu|wf|ws|ye|yt|yu|za|zm|zw)/)(?:[^\\s()<>{}\\[\\]]+|\\([^\\s()]*?\\([^\\s()]+\\)[^\\s()]*?\\)|\\([^\\s]+?\\))+(?:\\([^\\s()]*?\\([^\\s()]+\\)[^\\s()]*?\\)|\\([^\\s]+?\\)|[^\\s`!()\\[\\]{};:'".,<>?«»“”‘’])|(?:(?<!@)[a-z0-9]+(?:[.\\-][a-z0-9]+)*[.](?:com|net|org|edu|gov|mil|aero|asia|biz|cat|coop|info|int|jobs|mobi|museum|name|post|pro|tel|travel|xxx|ac|ad|ae|af|ag|ai|al|am|an|ao|aq|ar|as|at|au|aw|ax|az|ba|bb|bd|be|bf|bg|bh|bi|bj|bm|bn|bo|br|bs|bt|bv|bw|by|bz|ca|cc|cd|cf|cg|ch|ci|ck|cl|cm|cn|co|cr|cs|cu|cv|cx|cy|cz|dd|de|dj|dk|dm|do|dz|ec|ee|eg|eh|er|es|et|eu|fi|fj|fk|fm|fo|fr|ga|gb|gd|ge|gf|gg|gh|gi|gl|gm|gn|gp|gq|gr|gs|gt|gu|gw|gy|hk|hm|hn|hr|ht|hu|id|ie|il|im|in|io|iq|ir|is|it|je|jm|jo|jp|ke|kg|kh|ki|km|kn|kp|kr|kw|ky|kz|la|lb|lc|li|lk|lr|ls|lt|lu|lv|ly|ma|mc|md|me|mg|mh|mk|ml|mm|mn|mo|mp|mq|mr|ms|mt|mu|mv|mw|mx|my|mz|na|nc|ne|nf|ng|ni|nl|no|np|nr|nu|nz|om|pa|pe|pf|pg|ph|pk|pl|pm|pn|pr|ps|pt|pw|py|qa|re|ro|rs|ru|rw|sa|sb|sc|sd|se|sg|sh|si|sj|Ja|sk|sl|sm|sn|so|sr|ss|st|su|sv|sx|sy|sz|tc|td|tf|tg|th|tj|tk|tl|tm|tn|to|tp|tr|tt|tv|tw|tz|ua|ug|uk|us|uy|uz|va|vc|ve|vg|vi|vn|vu|wf|ws|ye|yt|yu|za|zm|zw)\\b/?(?!@))|(?:(?<!@)[a-z0-9]+(?:[.\\-][a-z0-9]+)*(?::[0-9]+/)(?:[^\\s()<>{}\\[\\]]+|\\([^\\s()]*?\\([^\\s()]+\\)[^\\s()]*?\\)|\\([^\\s]+?\\))+(?:\\([^\\s()]*?\\([^\\s()]+\\)[^\\s()]*?\\)|\\([^\\s]+?\\)|[^\\s`!()\\[\\]{};:'".,<>?«»“”‘’])\\b/?(?!@)))
				"""
		return try! NSRegularExpression(pattern: genericUrlRegexStr, options: .caseInsensitive)
	}()

// MARK: -
	
    class func cleanupText(_ string: String, addLinks: Bool = true, font: UIFont? = nil) -> NSMutableAttributedString {
		let unscaledBaseFont = font ?? UIFont.systemFont(ofSize: 17)
		let baseFont = UIFontMetrics(forTextStyle: .body).scaledFont(for: unscaledBaseFont)
		let defaultAttrs: [NSAttributedString.Key : Any] = [ .font : baseFont, .foregroundColor : UIColor(named: "Kraken Label Text") as Any]
		var linkAttrs: [NSAttributedString.Key : Any] = [ .foregroundColor : UIColor.blue as Any, .font : baseFont ]
		
		var inputString = string.decodeHTMLEntities()
	   	// Trim trailing newlines
	   	while inputString.hasSuffix("\n") {
	   		inputString.removeLast()
	   	}
		inputString = inputString.replacingOccurrences(of: "\r\n", with: "\n")
		
		var attrString: NSMutableAttributedString
		if inputString.hasPrefix("<Markdown>") {
			let mdSourceString = String(inputString.dropFirst("<Markdown>".count))
			let markdown = SwiftyMarkdown(string: "") 
			markdown.setFontNameForAllStyles(with: "TimesNewRomanPSMT")
			markdown.setFontColorForAllStyles(with: UIColor(named: "Kraken Label Text")!)
			markdown.code.fontName = "Courier New"
			markdown.blockquotes.fontName = "Courier New"
			attrString = NSMutableAttributedString(attributedString: markdown.attributedString(from: mdSourceString))
		}
		else {
			attrString = NSMutableAttributedString(string: inputString, attributes: defaultAttrs)
		}
		
		let str = attrString.string
		var stringIndex = str.startIndex
		while stringIndex < str.endIndex {
			if str[stringIndex] == "@", stringIndex == str.startIndex || str[str.index(before: stringIndex)] == " " {
				let startIndex = stringIndex
				let nameStartIndex = str.index(after: startIndex)
				var endIndex = nameStartIndex
				while endIndex < str.endIndex, validUsernameChars.contains(str.unicodeScalars[endIndex]) { 
					endIndex = str.index(after: endIndex) 
				}
				while endIndex > nameStartIndex {
					let prevIndex = str.index(before: endIndex)
					if !usernameSeparators.contains(str.unicodeScalars[prevIndex]) { 
						break
					}
					endIndex = prevIndex 
				}
				if str.distance(from: nameStartIndex, to: endIndex) >= 2 {
					let username = str[nameStartIndex..<endIndex]
					linkAttrs.updateValue("\(Settings.shared.settingsBaseURL)/profile/\(username)", forKey: .link)
					attrString.setAttributes(linkAttrs, range: NSRange(location: str.distance(from: string.startIndex, to: startIndex), 
							length: str.distance(from: startIndex, to: endIndex)))
					stringIndex = endIndex
				}
			}
			else if str[stringIndex] == "#", stringIndex == str.startIndex || str[str.index(before: stringIndex)] == " " {
				let startIndex = stringIndex
				let nameStartIndex = str.index(after: startIndex)
				var endIndex = nameStartIndex
				while endIndex < str.endIndex, CharacterSet.alphanumerics.contains(str.unicodeScalars[endIndex]) { 
					endIndex = str.index(after: endIndex) 
				}
				if str.distance(from: nameStartIndex, to: endIndex) >= 2 {
					let hashtag = str[nameStartIndex..<endIndex]
					linkAttrs.updateValue("\(Settings.shared.settingsBaseURL)/tweets?hashtag=\(hashtag)", forKey: .link)
					attrString.setAttributes(linkAttrs, range: NSRange(location: str.distance(from: string.startIndex, to: startIndex), 
							length: str.distance(from: startIndex, to: endIndex)))
					stringIndex = endIndex
				}
			}
			if stringIndex < str.endIndex {
				stringIndex = str.index(after: stringIndex)
			}
		}
				
		if addLinks {
			let str = attrString.string
			let matches = genericUrlRegex.matches(in: str, range: NSRange(0..<str.count))
			processUrlMatches(attrString: &attrString, matches: matches)
		}

		let stringWithJocomoji = StringUtilities.addInlineImages(str: attrString)
    	return stringWithJocomoji
	}
 
	/// Process a set of regex matches and substitute appropriate content in a return HTML string.
	///
	/// Pass by ref can kinda be voodoo.
	/// https://stackoverflow.com/questions/27364117/is-swift-pass-by-value-or-pass-by-reference
	///
	/// - Parameters:
	///   - string: Reference to the Leaf string that is the HTML content to return to the user.
	///   - matches: Array of regex matching ranges.
	/// - Returns: void
	///
	private class func processUrlMatches(attrString: inout NSMutableAttributedString, matches: [NSTextCheckingResult]) -> Void {

		// We reverse the matches since we're gonna manipulate the string and insert characters (ie, HTML)
		// so we want to preserve the range indices if there are multiple matches within the same string.
		for match in matches.reversed() {
			guard let stringRange = Range(match.range(at: 0), in: attrString.string) else { continue }
			var urlStr = String(attrString.string[stringRange])
			
			// The link regex sometimes matches "filename.md" and similar. We don't want those.
			if !urlStr.contains("/") {
				return
			}

			// iOS Safari doesn't put "http(s)://" at the start links copied from the linkbar.
			// If the scheme isn't specified it messes with the URLComponents constructor and it
			// interprets the entire string as a path component. Weird.
			if !urlStr.hasPrefix("http") {
				urlStr = "http://\(urlStr)"
			}
			// Sometimes people write urls at the end of sentence like https://twitarr.com. This is
			// not a valid URL and usually 404's, so we chomp off that last period from the match.
			// https://stackoverflow.com/questions/24122288/remove-last-character-from-string-swift-language
			//
			// A future consideration could be to insert a special unicode character or sequence that the 
			// frontend JS can detect and give users a popup saying their URL has been messed with.
			var urlTextSuffix = ""
			if urlStr.hasSuffix(".") {
				urlStr = String(urlStr.dropLast())
				urlTextSuffix = "."
			}
			
			var linkText = urlStr
			if let url = URL(string: urlStr) {
				if ["twitarr.com", "joco.hollandamerica.com", Settings.shared.settingsBaseURL.host]
						.contains(url.host ?? "nohostfoundasdfasfasf") {
					if url.pathComponents.count > 1, url.pathComponents[0] == "/" {
						switch url.pathComponents[1] {
							case "tweets": linkText = "[Twitarr Tweet Link]"
							case "forums": 
								if url.pathComponents.count == 2 {
									linkText = "[Forum Categories Link]"
								}
								else {
									linkText = "[Forum Category Link]"
								}
							case "forum": linkText = "[Forum Link]"
							case "seamail": linkText = "[Seamail Link]"
							case "fez": 
								if url.pathComponents.count > 2 {
									switch url.pathComponents[2] {
										case "joined": linkText = "[Joined LFGs Link]"
										case "owned": linkText = "[Your LFGs Link]"
										case "faq": linkText = "[LFG FAQ Link]"
										default: linkText = "[LFG Link]"
									}
								}
								else {
									linkText = "[LFGs Link]"
								}
							case "events": linkText = "[Events Link]"
							case "user", "profile": linkText = "[User Link]"
							case "boardgames": 
								if url.pathComponents.count > 2 {
									linkText = "[Boardgame Link]"
								}
								else {
									linkText = "[Boardgames Link]"
								}
							case "karaoke": 
								linkText = "[Karaoke Link]"
							case "microkaraoke": 
								linkText = "[Micro Karaoke Link]"
							case "performers": 
								linkText = "[Performer Gallery Link]"
							case "performer": 
								linkText = "[Performer Link]"
							case "faq": 
								linkText = "[FAQ Link]"
							case "about": 
								linkText = "[About Twitarr Link]"
							case "codeOfConduct": 
								linkText = "[Code Of Conduct Link]"
							case "time": 
								linkText = "[Time Zone Check]"
							case "public":
								let linkName = url.lastPathComponent.isEmpty ? "Public File Link" : url.lastPathComponent
								linkText = "[\(linkName)]"
							default: linkText = "[Twitarr Link]"
						}
					}
					else {
						linkText = "[Twitarr Link]"
					}
				}
			}
			
			let baseAttrs = attrString.attributes(at: match.range(at: 0).lowerBound, effectiveRange: nil)
			var linkAttrs = baseAttrs
			linkAttrs.updateValue(UIColor.blue as Any, forKey: .foregroundColor)
			linkAttrs.updateValue(urlStr, forKey: .link)
			let linkAttributedStr = NSMutableAttributedString(string: linkText, attributes: linkAttrs)
			linkAttributedStr.append(NSAttributedString(string: urlTextSuffix, attributes: baseAttrs))
			attrString.replaceCharacters(in: match.range(at: 0), with: linkAttributedStr)
		}
	}

 	// Takes text that may contain HTML fragment tags and removes the tags. This fn can also perform SOME TYPES of transforms,
 	// parsing the HTML tags and applying their attributes to the text, converting HTML to Attributed String attributes.
 	// 
 	// Thanks to the way AttributedStrings work, you can get a 'clean' String for an edit text field using cleanupText().string
    class func cleanupTextold(_ text:String, addLinks: Bool = true, font: UIFont? = nil) -> NSMutableAttributedString {
    	let outputString = NSMutableAttributedString()
    	let openTag = CharacterSet(charactersIn: "<")
    	let closeTag = CharacterSet(charactersIn: ">")
    	let emptySet = CharacterSet(charactersIn: "")
    	var tagStack = [HTMLTag]()
    	
		let unscaledBaseFont = font ?? UIFont.systemFont(ofSize: 17)
		let baseFont = UIFontMetrics(forTextStyle: .body).scaledFont(for: unscaledBaseFont)
		let baseTextAttrs: [NSAttributedString.Key : Any] = [ .font : baseFont, .foregroundColor : UIColor(named: "Kraken Label Text") as Any ]
		
    	// The jankiest HTML fragment parser I've written this week.
     	let scanner = Scanner(string: text)
     	scanner.charactersToBeSkipped = emptySet
		while !scanner.isAtEnd {
			// Scan to the start of the next tag. If tagStack is empty, it's text 'outside' of all tags. 
			// Else, it's text that's 'inside' all the tags in the stack.
			if let tempString = scanner.scanUpToCharacters(from: openTag) {
				let cleanedTempString = tempString.decodeHTMLEntities()
				let attrString = NSAttributedString(string: cleanedTempString, attributes: baseTextAttrs)
				outputString.append(attrString)
			}
			
			// Now scan the tag and whatever junk is in it, from '<' to '>'
	   		if scanner.scanString("<") != nil,  let tagContents = scanner.scanUpToCharacters(from: closeTag) {
	   			let firstSpace = tagContents.firstIndex(of: " ") ?? tagContents.endIndex
				let tagName = String(tagContents[..<firstSpace])
				if tagName.hasPrefix("/"){
					// Close tag
					let tagWithoutPrefix = tagName.dropFirst(1)
					var attrsToAdd: [NSAttributedString.Key : Any]?
					if let tagIndex = tagStack.lastIndex(where: { $0.tagName == tagWithoutPrefix }) {
						let tag = tagStack.remove(at: tagIndex)
						switch tag.tagName {
						case "a": 
							if addLinks {
								// Add the string as linktext, with the string itself as the contents of the 'link'. The text view
								// this text is put into should have a handler for taps on the link.
								let linkText = outputString.string.suffix(outputString.length - tag.position)
								attrsToAdd = [ .link : linkText, .foregroundColor : UIColor.blue as Any]
							}
						case "b": 
							attrsToAdd = [ .font : boldFont(for: baseFont)]
	//					case "blockquote":
	//					case "code":
	//					case "del": 
						case "em": attrsToAdd = [ .font : boldFont(for: baseFont)]
						case "i": attrsToAdd = [ .font : italicFont(for: baseFont)]
						case "p": outputString.replaceCharacters(in: NSMakeRange(outputString.length, 0), with: "\n\n")
	//					case "pre":
	//					case "q":
						case "strong": attrsToAdd = [ .font : boldFont(for: baseFont)]
	//					case "sub":
	//					case "sup":
						case "u": attrsToAdd = [ .underlineStyle : NSNumber(1) ]
						default: break
						}
						
						if let attrs = attrsToAdd {
							outputString.addAttributes(attrs, range: NSMakeRange(tag.position, outputString.length - tag.position))
						}
					}
				}
				else if tagContents.hasSuffix("/") || isVoidElementTag(tagName) {
					// This is an self-closing tag e.g. <br />, or a void eleement e.g. <br>
					var appendStr: String?
					switch tagName {
					case "br/": appendStr = "\n"
					case "br": appendStr = "\n"
					
					case "img":
						var fontSize: CGFloat = 17.0
						if outputString.length > 0, let currentFont = outputString.attribute(.font, 
								at: outputString.length - 1, effectiveRange: nil) as? UIFont {
							fontSize = currentFont.pointSize
						}

						if let img = StringUtilities.getInlineImage(from: tagContents, size: fontSize) {
							let attachment = NSTextAttachment()
							attachment.image = img
							outputString.append(NSAttributedString(attachment: attachment))
						}
					
					// We don't care about the rest of the void elements.
					default: break
					}
					
					if let str = appendStr {
						outputString.replaceCharacters(in: NSMakeRange(outputString.length, 0), with: str)
					}

				}
				else {
					// This is an open tag e.g. <a>
					tagStack.append(HTMLTag(tagName: tagName, position: outputString.length))
				}
			}
			_ = scanner.scanString(">")
	   	}
	   	
	   	// Trim trailing newlines
	   	while outputString.string.hasSuffix("\n") {
	   		outputString.deleteCharacters(in: NSMakeRange(outputString.length - 1, 1))
	   	}
    	
	   	//
		let stringWithJocomoji = StringUtilities.addInlineImages(str: outputString)
    	return stringWithJocomoji
    }
    
    // For strings that aren't HTML fragments, Jocomoji appear as ":fez:". This converts those tokens, inserting 
    // inline images sized to match the font size at that point in the string.
	static let jocomoji = [ "buffet", "die-ship", "die", "fez", "hottub", "joco", "pirate", "ship-front",
			"ship", "towel-monkey", "tropical-drink", "zombie" ]
    class func addInlineImages(str: NSMutableAttributedString) -> NSMutableAttributedString {
    	let resultString = str
		for emojiTag in jocomoji {
			var searchRange = resultString.string.startIndex..<resultString.string.endIndex
			while let rng = resultString.string.range(of: ":\(emojiTag):", range: searchRange) {
				let convertedRange = NSRange(rng, in: resultString.string)
				var fontSize: CGFloat = 17.0
				if let currentFont = resultString.attribute(.font, at: convertedRange.location, effectiveRange: nil) as? UIFont {
					fontSize = currentFont.pointSize
				}

				if let sourceImage = UIImage(named: emojiTag) {
					let outputImageSize = CGSize(width: fontSize, height: fontSize)
					UIGraphicsBeginImageContext(outputImageSize)
					sourceImage.draw(in: CGRect(origin: CGPoint.zero, size: outputImageSize))
					let outputImage = UIGraphicsGetImageFromCurrentImageContext()
					UIGraphicsEndImageContext()
					let attachment = NSTextAttachment()
					attachment.image = outputImage
					resultString.replaceCharacters(in: convertedRange, with: NSAttributedString(attachment: attachment))
					searchRange = rng.lowerBound..<resultString.string.endIndex
				}
				else {
					// Leave emoji if we can't replace with image; skip past it in search range
					searchRange = rng.upperBound..<resultString.string.endIndex
				}
			}
		}
		return resultString
    }
    
    class func getInlineImage(from: String, size: CGFloat) -> UIImage? {
     	let scanner = Scanner(string: from)
     	scanner.charactersToBeSkipped = CharacterSet(charactersIn: "")
		_ = scanner.scanUpToString("src=\"")
		_ = scanner.scanString("src=\"")
		if let imagePath = scanner.scanUpToString("\""), imagePath.hasPrefix("/img/emoji/small/"),
				let imageName = imagePath.split(separator: "/").last, imageName.count < 40 {
			let sourceImage = UIImage(named: String(imageName))
			let outputImageSize = CGSize(width: size, height: size)
			UIGraphicsBeginImageContext(outputImageSize)
			sourceImage?.draw(in: CGRect(origin: CGPoint.zero, size: outputImageSize))
			let outputImage = UIGraphicsGetImageFromCurrentImageContext()
			UIGraphicsEndImageContext()
			
			return outputImage
		}
		return nil
    }
    
    class func extractHashtags(_ text:String) -> Set<String> {
    	var hashtags = Set<String>()
    	var outputString = String()
    	let openTag = CharacterSet(charactersIn: "<")
    	let closeTag = CharacterSet(charactersIn: ">")
    	let emptySet = CharacterSet(charactersIn: "")
    	var tagStack = [HTMLTag]()
    			
    	// The second jankiest HTML fragment parser I've written this week.
     	let scanner = Scanner(string: text)
     	scanner.charactersToBeSkipped = emptySet
		while !scanner.isAtEnd {
			// Scan to the start of the next tag. If tagStack is empty, it's text 'outside' of all tags. 
			// Else, it's text that's 'inside' all the tags in the stack.
			if let tempString = scanner.scanUpToCharacters(from: openTag) {
				outputString.append(tempString)
			}
			
			// Now scan the tag and whatever junk is in it, from '<' to '>'
			
	   		if scanner.scanString("<") != nil, let tagContents = scanner.scanUpToCharacters(from: closeTag) {
	   			let firstSpace = tagContents.firstIndex(of: " ") ?? tagContents.endIndex
				let tagName = String(tagContents[..<firstSpace])
				if tagName.hasPrefix("/") {
					// Close tag
					let tagWithoutPrefix = tagName.dropFirst(1)
					if let tagIndex = tagStack.lastIndex(where: { $0.tagName == tagWithoutPrefix }) {
						let tag = tagStack.remove(at: tagIndex)
						switch tag.tagName {
						case "a": 
							let linkText = outputString.suffix(outputString.count - tag.position)
							if linkText.hasPrefix("#") && !linkText.contains(" ") {
								let strippedTag = linkText.dropFirst()
								hashtags.insert(String(strippedTag))
							}
						default: break
						}
					}
				}
				else if tagContents.hasSuffix("/") || isVoidElementTag(tagName) {
					// This is an self-closing tag e.g. <br />, or a void eleement e.g. <br>
				}
				else {
					// This is an open tag e.g. <a>
					tagStack.append(HTMLTag(tagName: tagName, position: outputString.count))
				}
			}
			_ = scanner.scanString(">")
	   	}
	   	
    	return hashtags
    }
    
    class func boldFont(for baseFont: UIFont) -> UIFont {
    	if let desc = baseFont.fontDescriptor.withSymbolicTraits(.traitBold) {
			let boldFont = UIFont(descriptor: desc, size: baseFont.pointSize)
			return boldFont
		}
		return baseFont
    }
        
    class func italicFont(for baseFont: UIFont) -> UIFont {
    	// This could also be done with the NSAttributedString key for obliqueness
    	if let desc = baseFont.fontDescriptor.withSymbolicTraits(.traitItalic) {
			let boldFont = UIFont(descriptor: desc, size: baseFont.pointSize)
			return boldFont
		}
		return baseFont
    }
        
    static var voidElements = Set(["area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param", 
    		"source", "track", "wbr", "command", "keygen", "menuitem"])
    class func isVoidElementTag(_ tag: String) -> Bool {
    	return voidElements.contains(tag)
    }
    
    
	class func relativeTimeString(forDate: Date) -> String {
		if forDate.timeIntervalSinceNow > -1.0 {
			return "a second ago"
		}
		
		// If the date is Date.distantPast
		if forDate.timeIntervalSinceNow < 0 - 60 * 60 * 24 * 365 * 100 {
			return ""
		}
	
		let hour = 60.0 * 60.0
		let day = hour * 24.0
		let month = day * 31.0
		
		// Fix for a really annoying DateFormatter bug. For successive allowedUnits A, B, and C, if the interval
		// is > 1B - .5A but < 1B, DateFormatter will return "0 C" instead of "1 B". 
		var interval = cruiseCurrentDate().timeIntervalSince(forDate)
		switch interval {
		case (hour - 30.0)...hour: interval = hour			// = 1hr for everything above 59.5 minutes
		case (day - hour / 2)...day: interval = day			// = 1day for everything above 23.5 hours
		case (month - day / 2)...month: interval = month	// = 1mo for everything above 30.5 days
		default: break
		}

		let formatter = DateComponentsFormatter()
		formatter.unitsStyle = .full
		formatter.maximumUnitCount = 1
		formatter.allowedUnits = [.second, .minute, .hour, .day, .month, .year]
		if let relativeTimeStr = formatter.string(from: interval) {
			let resultStr = relativeTimeStr + " ago"
			return resultStr
		}
		return "some time ago"
	}
	
	// Makes a multiline attributed string showing the start and end time, in both Device Time and Boat Time, unless they match.
	class func eventTimeString(startTime: Date, endTime: Date?, baseFont: UIFont = UIFont.systemFont(ofSize: 17.0)) -> NSMutableAttributedString {
		let timeString = NSMutableAttributedString()
		let baseAttrs: [NSAttributedString.Key : Any] = [ .font : baseFont as Any, .foregroundColor : UIColor(named: "Kraken Label Text") as Any ]
		var boatAttrs = baseAttrs
		if let descriptor = baseFont.fontDescriptor.withSymbolicTraits(.traitItalic) {
	        let italicFont = UIFont(descriptor: descriptor, size: 0) 
			boatAttrs  = [ .font : italicFont as Any, .foregroundColor : UIColor(named: "Kraken Secondary Text") as Any ]
		}
		
		let dateFormatter = DateFormatter()
		dateFormatter.dateStyle = .short
		dateFormatter.timeStyle = .short
		dateFormatter.locale = Locale(identifier: "en_US")
		var includeDeviceTime = false
		if let serverTZ = ServerTime.shared.serverTimezone {
			dateFormatter.timeZone = serverTZ
			timeString.append(string: dateFormatter.string(from: startTime), attrs: baseAttrs)
			dateFormatter.dateStyle = .none
			if let endTime = endTime {
				timeString.append(string: " - \(dateFormatter.string(from: endTime))")
			}

			if abs(ServerTime.shared.deviceTimeOffset + TimeInterval(ServerTime.shared.timeZoneOffset)) > 300.0 {
				timeString.append(string: " (Boat Time)\n", attrs: boatAttrs)
				includeDeviceTime = true
			}
		}
		else {
			includeDeviceTime = true
		}
		
		// If we're ashore and don't have access to server time (and, specifically, the server timezone),
		// OR we do have access and the serverTime is > 5 mins off of deviceTime, show device time.
		if includeDeviceTime {
			dateFormatter.timeZone = ServerTime.shared.deviceTimezone
			dateFormatter.dateStyle = .none
			timeString.append(string: "\(dateFormatter.string(from: startTime))", attrs: baseAttrs)
			if let endTime = endTime {
				timeString.append(string: " - \(dateFormatter.string(from: endTime))")
			}
			timeString.append(string: " (Device Time)", attrs: boatAttrs)
		}
		return timeString
	}

	// Apple's ISO8601 date formatter does not actually parse most of the variants the standard specsifies. And,
	// for the cases it does handle you generally have to specify beforehand what options you're expecting. For 
	// our purposes, V3 sends dates with fractional seconds, but the default ISO8601DateFormatter won't parse them
	// unless you set the .withFractionalSeconds option. But maybe the server won't always do this--therefore this fn
	// exists to handle slightly different ISO 8601 date formats.
	class func parseISO8601DateString(_ decoder: Decoder) throws -> Date {
		let container = try decoder.singleValueContainer()
		let str = try container.decode(String.self)
		if let result = StringUtilities.isoDateWithFraction.date(from: str) ??
				StringUtilities.isoDateNoFraction.date(from: str) {
			return result
		}
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Couldn't build date from string: \(str)")
	}
}


// rcf copied from https://gist.github.com/mwaterfall/25b4a6a06dc3309d9555
// Very slightly adapted from http://stackoverflow.com/a/30141700/106244
// 99.99% Credit to Martin R!
// Mapping from XML/HTML character entity reference to character
// From http://en.wikipedia.org/wiki/List_of_XML_and_HTML_character_entity_references
private let characterEntities : [String: Character] = [
    
    // XML predefined entities:
    "quot"     : "\"",
    "amp"      : "&",
    "apos"     : "'",
    "lt"       : "<",
    "gt"       : ">",
    
    // HTML character entity references:
	"nbsp"     : "\u{00A0}",    "iexcl"    : "\u{00A1}",    "cent"     : "\u{00A2}",    "pound"    : "\u{00A3}",
	"curren"   : "\u{00A4}",    "yen"      : "\u{00A5}",    "brvbar"   : "\u{00A6}",    "sect"     : "\u{00A7}",    
	"uml"      : "\u{00A8}",    "copy"     : "\u{00A9}",    "ordf"     : "\u{00AA}",    "laquo"    : "\u{00AB}",    
	"not"      : "\u{00AC}",    "shy"      : "\u{00AD}",    "reg"      : "\u{00AE}",    "macr"     : "\u{00AF}",    
	"deg"      : "\u{00B0}",    "plusmn"   : "\u{00B1}",    "sup2"     : "\u{00B2}",    "sup3"     : "\u{00B3}",    
	"acute"    : "\u{00B4}",    "micro"    : "\u{00B5}",    "para"     : "\u{00B6}",    "middot"   : "\u{00B7}",    
	"cedil"    : "\u{00B8}",    "sup1"     : "\u{00B9}",    "ordm"     : "\u{00BA}",    "raquo"    : "\u{00BB}",    
	"frac14"   : "\u{00BC}",    "frac12"   : "\u{00BD}",    "frac34"   : "\u{00BE}",    "iquest"   : "\u{00BF}",    
	"Agrave"   : "\u{00C0}",    "Aacute"   : "\u{00C1}",    "Acirc"    : "\u{00C2}",    "Atilde"   : "\u{00C3}",    
	"Auml"     : "\u{00C4}",    "Aring"    : "\u{00C5}",    "AElig"    : "\u{00C6}",    "Ccedil"   : "\u{00C7}",    
	"Egrave"   : "\u{00C8}",    "Eacute"   : "\u{00C9}",    "Ecirc"    : "\u{00CA}",    "Euml"     : "\u{00CB}",    
	"Igrave"   : "\u{00CC}",    "Iacute"   : "\u{00CD}",    "Icirc"    : "\u{00CE}",    "Iuml"     : "\u{00CF}",    
	"ETH"      : "\u{00D0}",    "Ntilde"   : "\u{00D1}",    "Ograve"   : "\u{00D2}",    "Oacute"   : "\u{00D3}",    
	"Ocirc"    : "\u{00D4}",    "Otilde"   : "\u{00D5}",    "Ouml"     : "\u{00D6}",    "times"    : "\u{00D7}",    
	"Oslash"   : "\u{00D8}",    "Ugrave"   : "\u{00D9}",    "Uacute"   : "\u{00DA}",    "Ucirc"    : "\u{00DB}",    
	"Uuml"     : "\u{00DC}",    "Yacute"   : "\u{00DD}",    "THORN"    : "\u{00DE}",    "szlig"    : "\u{00DF}",    
	"agrave"   : "\u{00E0}",    "aacute"   : "\u{00E1}",    "acirc"    : "\u{00E2}",    "atilde"   : "\u{00E3}",    
	"auml"     : "\u{00E4}",    "aring"    : "\u{00E5}",    "aelig"    : "\u{00E6}",    "ccedil"   : "\u{00E7}",    
	"egrave"   : "\u{00E8}",    "eacute"   : "\u{00E9}",    "ecirc"    : "\u{00EA}",    "euml"     : "\u{00EB}",    
	"igrave"   : "\u{00EC}",    "iacute"   : "\u{00ED}",    "icirc"    : "\u{00EE}",    "iuml"     : "\u{00EF}",    
	"eth"      : "\u{00F0}",    "ntilde"   : "\u{00F1}",    "ograve"   : "\u{00F2}",    "oacute"   : "\u{00F3}",    
	"ocirc"    : "\u{00F4}",    "otilde"   : "\u{00F5}",    "ouml"     : "\u{00F6}",    "divide"   : "\u{00F7}",   
	"oslash"   : "\u{00F8}",    "ugrave"   : "\u{00F9}",    "uacute"   : "\u{00FA}",    "ucirc"    : "\u{00FB}",    
	"uuml"     : "\u{00FC}",    "yacute"   : "\u{00FD}",    "thorn"    : "\u{00FE}",    "yuml"     : "\u{00FF}",    
	"OElig"    : "\u{0152}",    "oelig"    : "\u{0153}",    "Scaron"   : "\u{0160}",    "scaron"   : "\u{0161}",    
	"Yuml"     : "\u{0178}",    "fnof"     : "\u{0192}",    "circ"     : "\u{02C6}",    "tilde"    : "\u{02DC}",    
	"Alpha"    : "\u{0391}",    "Beta"     : "\u{0392}",    "Gamma"    : "\u{0393}",    "Delta"    : "\u{0394}",    
	"Epsilon"  : "\u{0395}",    "Zeta"     : "\u{0396}",    "Eta"      : "\u{0397}",    "Theta"    : "\u{0398}",    
	"Iota"     : "\u{0399}",    "Kappa"    : "\u{039A}",    "Lambda"   : "\u{039B}",    "Mu"       : "\u{039C}",    
	"Nu"       : "\u{039D}",    "Xi"       : "\u{039E}",    "Omicron"  : "\u{039F}",    "Pi"       : "\u{03A0}",    
	"Rho"      : "\u{03A1}",    "Sigma"    : "\u{03A3}",    "Tau"      : "\u{03A4}",    "Upsilon"  : "\u{03A5}",    
	"Phi"      : "\u{03A6}",    "Chi"      : "\u{03A7}",    "Psi"      : "\u{03A8}",    "Omega"    : "\u{03A9}",    
	"alpha"    : "\u{03B1}",    "beta"     : "\u{03B2}",    "gamma"    : "\u{03B3}",    "delta"    : "\u{03B4}",    
	"epsilon"  : "\u{03B5}",    "zeta"     : "\u{03B6}",    "eta"      : "\u{03B7}",    "theta"    : "\u{03B8}",    
	"iota"     : "\u{03B9}",    "kappa"    : "\u{03BA}",    "lambda"   : "\u{03BB}",    "mu"       : "\u{03BC}",    
	"nu"       : "\u{03BD}",    "xi"       : "\u{03BE}",    "omicron"  : "\u{03BF}",    "pi"       : "\u{03C0}",    
	"rho"      : "\u{03C1}",    "sigmaf"   : "\u{03C2}",    "sigma"    : "\u{03C3}",    "tau"      : "\u{03C4}",    
	"upsilon"  : "\u{03C5}",    "phi"      : "\u{03C6}",    "chi"      : "\u{03C7}",    "psi"      : "\u{03C8}",    
	"omega"    : "\u{03C9}",    "thetasym" : "\u{03D1}",    "upsih"    : "\u{03D2}",    "piv"      : "\u{03D6}",    
	"ensp"     : "\u{2002}",    "emsp"     : "\u{2003}",    "thinsp"   : "\u{2009}",    "zwnj"     : "\u{200C}",    
	"zwj"      : "\u{200D}",    "lrm"      : "\u{200E}",    "rlm"      : "\u{200F}",    "ndash"    : "\u{2013}",    
	"mdash"    : "\u{2014}",    "lsquo"    : "\u{2018}",    "rsquo"    : "\u{2019}",    "sbquo"    : "\u{201A}",    
	"ldquo"    : "\u{201C}",    "rdquo"    : "\u{201D}",    "bdquo"    : "\u{201E}",    "dagger"   : "\u{2020}",    
	"Dagger"   : "\u{2021}",    "bull"     : "\u{2022}",    "hellip"   : "\u{2026}",    "permil"   : "\u{2030}",    
	"prime"    : "\u{2032}",    "Prime"    : "\u{2033}",    "lsaquo"   : "\u{2039}",    "rsaquo"   : "\u{203A}",    
	"oline"    : "\u{203E}",    "frasl"    : "\u{2044}",    "euro"     : "\u{20AC}",    "image"    : "\u{2111}",    
	"weierp"   : "\u{2118}",    "real"     : "\u{211C}",    "trade"    : "\u{2122}",    "alefsym"  : "\u{2135}",    
	"larr"     : "\u{2190}",    "uarr"     : "\u{2191}",    "rarr"     : "\u{2192}",    "darr"     : "\u{2193}",    
	"harr"     : "\u{2194}",    "crarr"    : "\u{21B5}",    "lArr"     : "\u{21D0}",    "uArr"     : "\u{21D1}",    
	"rArr"     : "\u{21D2}",    "dArr"     : "\u{21D3}",    "hArr"     : "\u{21D4}",    "forall"   : "\u{2200}",    
	"part"     : "\u{2202}",    "exist"    : "\u{2203}",    "empty"    : "\u{2205}",    "nabla"    : "\u{2207}",    
	"isin"     : "\u{2208}",    "notin"    : "\u{2209}",    "ni"       : "\u{220B}",    "prod"     : "\u{220F}",    
	"sum"      : "\u{2211}",    "minus"    : "\u{2212}",    "lowast"   : "\u{2217}",    "radic"    : "\u{221A}",    
	"prop"     : "\u{221D}",    "infin"    : "\u{221E}",    "ang"      : "\u{2220}",    "and"      : "\u{2227}",    
	"or"       : "\u{2228}",    "cap"      : "\u{2229}",    "cup"      : "\u{222A}",    "int"      : "\u{222B}",    
	"there4"   : "\u{2234}",    "sim"      : "\u{223C}",    "cong"     : "\u{2245}",    "asymp"    : "\u{2248}",    
	"ne"       : "\u{2260}",    "equiv"    : "\u{2261}",    "le"       : "\u{2264}",    "ge"       : "\u{2265}",    
	"sub"      : "\u{2282}",    "sup"      : "\u{2283}",    "nsub"     : "\u{2284}",    "sube"     : "\u{2286}",    
	"supe"     : "\u{2287}",    "oplus"    : "\u{2295}",    "otimes"   : "\u{2297}",    "perp"     : "\u{22A5}",    
	"sdot"     : "\u{22C5}",    "lceil"    : "\u{2308}",    "rceil"    : "\u{2309}",    "lfloor"   : "\u{230A}",    
	"rfloor"   : "\u{230B}",    "lang"     : "\u{2329}",    "rang"     : "\u{232A}",    "loz"      : "\u{25CA}",    
	"spades"   : "\u{2660}",    "clubs"    : "\u{2663}",    "hearts"   : "\u{2665}",    "diams"    : "\u{2666}"]
	
extension String {
    
    // Returns a new string with HTML entity references of the form "&quot;" replaced with their entities.
    // Works for all HTML5 character entity refs and for numeric character references.
    func decodeHTMLEntities() -> String {
    	var outputString = ""
    
    	let scanner = Scanner(string: self)
    	scanner.charactersToBeSkipped = CharacterSet(charactersIn: "")
    	while !scanner.isAtEnd {
			let foundAmpersand = scanner.scanString("&")
    		let entityString = scanner.scanUpToCharacters(from: CharacterSet(charactersIn: "&;"))
    		let foundSemicolon = scanner.scanString(";")
    		
    		if foundAmpersand != nil, foundSemicolon != nil, let entityString = entityString {
				if entityString.hasPrefix("#x") || entityString.hasPrefix("#X"), 
						let codePoint = UInt32(entityString["#x".endIndex...], radix: 16),
						let scalar = Unicode.Scalar(codePoint) {
					outputString.append(Character(scalar))
				}
				else if entityString.hasPrefix("#"), let codePoint = UInt32(entityString["#".endIndex...]),
						let scalar = Unicode.Scalar(codePoint) { 
					outputString.append(Character(scalar))
				}
				else if let entityAsChar = characterEntities[entityString]  {
					outputString.append(entityAsChar)
				}
				else {
					// Started with an ampersand, ended with a semicolon, but couldn't convert
					outputString.append("&\(entityString);")
				}
			}
			else {
				// Some of the elements of an entity ref were missing. Output what we scanned without conversion.
				outputString.append("\(foundAmpersand ?? "")\(entityString ?? "")\(foundSemicolon ?? "")")
			}
		}
		return outputString
	}
	
	// Returns a percent encoded string for a COMPONENT of an URL path. Percent encodes non-urlPathAllowed chars plus "/".
	// URLComponents and URLQueryItem and such handle most of these types of cases, and setting the whole path of
	// a URLComponents works. Ths sanitizes appending a single path component.
	func addingPathComponentPercentEncoding() -> String? {
		var pathComponentChars = NSCharacterSet.urlPathAllowed
		pathComponentChars.remove(charactersIn: "/")
		let encoded = addingPercentEncoding(withAllowedCharacters: pathComponentChars) ?? ""
		return encoded
	}
}

extension Substring {
	// Gets a String from a Substring, in a way that allows function chaining. This in turn lets us work with
	// Optional Substrings easier, as we can do things like `stringVariable.split("/").last?.lowercased().string`
	var string: String {
		String(self)	
	}
}
