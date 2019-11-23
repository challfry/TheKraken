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
