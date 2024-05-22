//
//  KrakenError.swift
//  Kraken
//
//  Created by Chall Fry on 4/7/21.
//  Copyright © 2021 Chall Fry. All rights reserved.
//

import Foundation

@objc class KrakenError: NSObject, LocalizedError {
	var errorString: String						// All errors, concatenated.

	init(_ error: String) {
		errorString = error
		super.init()
	}
	
	public var errorDescription: String? { 
		return errorString
	}
}
