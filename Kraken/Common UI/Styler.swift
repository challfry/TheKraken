//
//  Styler.swift
//  Kraken
//
//  Created by Chall Fry on 10/29/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit

// This is a collection of UIKit object extensions that make supporting dynamic font sizes easier for IB-built widgets. 
// To use, set the right font size for the Large (iOS default) content size in IB, then call styleFor(.body) on the widget
// in awakeFronNib(). From what little testing I did, I can't see how the text style you use makes a difference when
// applied to custom fonts--they all seem to scale the same? Anyway, probably just use .body.
//
// It is probably not a good idea to call the styleFor() methods on the same widget repeatedly.

extension UILabel {
	func styleFor(_ style: UIFont.TextStyle) {
		let metrics = UIFontMetrics(forTextStyle: style)
		let scaledFont = metrics.scaledFont(for: font)
		font = scaledFont
		adjustsFontForContentSizeCategory = true
	}
	
	func getAttrs() -> [ NSAttributedString.Key : Any ] {
		return [ .font : self.font as Any, .foregroundColor : self.textColor as Any ]
	}
}

extension UITextField {
	func styleFor(_ style: UIFont.TextStyle) {
		let metrics = UIFontMetrics(forTextStyle: style)
		if let currentFont = font {
			let scaledFont = metrics.scaledFont(for: currentFont)
			font = scaledFont
			adjustsFontForContentSizeCategory = true
		}
	}
}

extension UITextView {
	// Do not use on text views that can have attributed text! Setting the font changes the font on the entire
	// contents, and if the user changes the dynamic type size, it may change the whole string.
	func styleFor(_ style: UIFont.TextStyle) {
		let metrics = UIFontMetrics(forTextStyle: style)
		if let currentFont = font {
			let scaledFont = metrics.scaledFont(for: currentFont)
			font = scaledFont
			adjustsFontForContentSizeCategory = true
		}
	}
	
	// What we may want is something like this fn, which takes an attributed string with fonts scaled to the Large
	// content size and then re-scales the text in each attribute range appropriately.
	// func scaleAndSetText(_ str: NSAttributedString)
}

extension UIButton {
	func styleFor(_ style: UIFont.TextStyle) {
		let metrics = UIFontMetrics(forTextStyle: style)
		if let currentFont = titleLabel?.font {
			let scaledFont = metrics.scaledFont(for: currentFont, maximumPointSize: 28)
			titleLabel?.font = scaledFont
			titleLabel?.adjustsFontForContentSizeCategory = true
		}
	}
}

// A simple extension to attributed string so you can append Strings to it.
// You can pass nil for attrs to append with the same attributes as the tail of the current string.
extension NSMutableAttributedString {
	func append(string: String, attrs: [NSAttributedString.Key : Any]? = nil) {
		var stringToAppend: NSAttributedString
		if let inputAttrs = attrs {
			stringToAppend = NSAttributedString(string: string, attributes: inputAttrs)
		}
		else {
			if length > 0 {
				let endAttributes = attributes(at: length - 1, effectiveRange: nil)
				stringToAppend = NSAttributedString(string: string, attributes: endAttributes)
			}
			else {
				stringToAppend = NSAttributedString(string: string)
			}
		}
		append(stringToAppend)
	}
}

extension UIFont {
    class func systemFont(ofSize fontSize: CGFloat, symbolicTraits: UIFontDescriptor.SymbolicTraits) -> UIFont {
        let font = UIFont.systemFont(ofSize: fontSize).including(symbolicTraits: symbolicTraits) ?? UIFont.preferredFont(forTextStyle: .body)
        return UIFontMetrics(forTextStyle: .body).scaledFont(for: font)
    }

    func including(symbolicTraits: UIFontDescriptor.SymbolicTraits) -> UIFont? {
        var traits = self.fontDescriptor.symbolicTraits
        traits.update(with: symbolicTraits)
        return withOnly(symbolicTraits: traits)
    }

    func excluding(symbolicTraits: UIFontDescriptor.SymbolicTraits) -> UIFont? {
        var traits = self.fontDescriptor.symbolicTraits
        traits.remove(symbolicTraits)
        return withOnly(symbolicTraits: traits)
    }

    func withOnly(symbolicTraits: UIFontDescriptor.SymbolicTraits) -> UIFont? {
        guard let fontDescriptor = fontDescriptor.withSymbolicTraits(symbolicTraits) else { return nil }
        return .init(descriptor: fontDescriptor, size: pointSize)
    }
}
