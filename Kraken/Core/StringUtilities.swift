//
//  StringUtilities.swift
//  Kraken
//
//  Created by Chall Fry on 5/18/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit

class StringUtilities {

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
		
 
 	// Takes text that may contain HTML fragment tags and removes the tags. This fn can also perform SOME TYPES of transforms,
 	// parsing the HTML tags and applying their attributes to the text, converting HTML to Attributed String attributes.
 	// 
 	// Thanks to the way AttributedStrings work, you can get a 'clean' String for an edit text field using cleanupText().string
    class func cleanupText(_ text:String, addLinks: Bool = true, font: UIFont? = nil) -> NSMutableAttributedString {
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
			if let tempString = scanner.KscanUpToCharactersFrom(openTag) {
				let cleanedTempString = tempString.decodeHTMLEntities()
				let attrString = NSAttributedString(string: cleanedTempString, attributes: baseTextAttrs)
				outputString.append(attrString)
			}
			
			// Now scan the tag and whatever junk is in it, from '<' to '>'
			scanner.scanString("<", into: nil)
	   		if let tagContents = scanner.KscanUpToCharactersFrom(closeTag) {
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
		   	scanner.scanString(">", into: nil)
	   	}
	   	
	   	// Trim trailing newlines
	   	while outputString.string.hasSuffix("\n") {
	   		outputString.deleteCharacters(in: NSMakeRange(outputString.length - 1, 1))
	   	}
    	
    	return outputString
    }
    
    class func getInlineImage(from: String, size: CGFloat) -> UIImage? {
     	let scanner = Scanner(string: from)
     	scanner.charactersToBeSkipped = CharacterSet(charactersIn: "")
		scanner.KscanUpTo("src=\"")
		scanner.KscanString("src=\"")
		if let imagePath = scanner.KscanUpTo("\""), imagePath.hasPrefix("/img/emoji/small/"),
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
			if let tempString = scanner.KscanUpToCharactersFrom(openTag) {
				outputString.append(tempString)
			}
			
			// Now scan the tag and whatever junk is in it, from '<' to '>'
			scanner.scanString("<", into: nil)
	   		if let tagContents = scanner.KscanUpToCharactersFrom(closeTag) {
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
		   	scanner.scanString(">", into: nil)
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

// I think they finally fixed the junky API for Scanner in iOS 13, but I can't use it yet.
// The fns in this extension are API glue to make Scanner fns return optionals.
// The "K" prefixes are so that, years from now, someone can USE THE REFACTOR TOOL to get rid of this code
// and call the too-new iOS APIs directly (it makes it obvious which fns are local, and keeps us from
// interfering with the framework methods).
extension Scanner {
  
	@discardableResult func KscanUpToCharactersFrom(_ set: CharacterSet) -> String? {
		var result: NSString?                                                           
		return scanUpToCharacters(from: set, into: &result) ? (result as String?) : nil 
	}

	@discardableResult func KscanCharactersFrom(_ set: CharacterSet) -> String? {
		var result: NSString?                                                           
		return scanCharacters(from: set, into: &result) ? (result as String?) : nil 
	}

	@discardableResult func KscanUpTo(_ string: String) -> String? {
		var result: NSString?
		return self.scanUpTo(string, into: &result) ? (result as String?) : nil
	}

	@discardableResult func KscanString(_ string: String) -> String? {
		var result: NSString?
		return self.scanString(string, into: &result) ? (result as String?) : nil
	}

	@discardableResult func KscanDouble() -> Double? {
		var double: Double = 0
		return scanDouble(&double) ? double : nil
	}
	
	@discardableResult func KscanInt() -> Int? {
		var intVal: Int = 0
		return scanInt(&intVal) ? intVal : nil
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
			let foundAmpersand = scanner.scanString("&", into: nil)
    		let entityString = scanner.KscanUpToCharactersFrom(CharacterSet(charactersIn: "&;"))
    		let foundSemicolon = scanner.scanString(";", into: nil)
    		
    		if foundAmpersand, foundSemicolon, let entityString = entityString {
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
				outputString.append("\(foundAmpersand ? "&" : "")\(entityString ?? "")\(foundSemicolon ? ";" : "")")
			}
		}
		return outputString
	}
	
	// Returns a percent encoded string for a COMPONENT of an URL path. Percent encodes non-urlPathAllowed chars plus "/".
	func addingPathComponentPercentEncoding() -> String? {
		var pathComponentChars = NSCharacterSet.urlPathAllowed
		pathComponentChars.remove(charactersIn: "/")
		let encoded = addingPercentEncoding(withAllowedCharacters: pathComponentChars) ?? ""
		return encoded
	}
}
