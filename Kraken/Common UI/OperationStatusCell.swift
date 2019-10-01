//
//  OperationStatusCell.swift
//  Kraken
//
//  Created by Chall Fry on 4/25/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import Foundation
import UIKit


// MARK: Status cell; activity name + spinner, or error status on failure
@objc protocol OperationStatusCellProtocol {
	dynamic var statusText: String { get set }
	dynamic var errorText: String? { get set }
	dynamic var showSpinner: Bool { get set }
}

@objc class OperationStatusCellModel: BaseCellModel, OperationStatusCellProtocol {
	private static let validReuseIDs = [ "OperationStatusCell" : OperationStatusCell.self ]
	override class var validReuseIDDict: [String: BaseCollectionViewCell.Type ] { return validReuseIDs }

	@objc dynamic var errorText: String?
	@objc dynamic var statusText: String = ""
	@objc dynamic var showSpinner: Bool = false

	init() {
		super.init(bindingWith: OperationStatusCellProtocol.self)
	}
}

@objc class LoginStatusCellModel: BaseCellModel, OperationStatusCellProtocol {	
	private static let validReuseIDs = [ "OperationStatusCell" : OperationStatusCell.self ]
	override class var validReuseIDDict: [String: BaseCollectionViewCell.Type ] { return validReuseIDs }

	@objc dynamic var statusText: String = ""
	@objc dynamic var errorText: String?
	@objc dynamic var showSpinner: Bool = false

	init() {
		super.init(bindingWith: OperationStatusCellProtocol.self)
		
		CurrentUser.shared.tell(self, when:[ "isChangingLoginState", "lastError" ]) { observer, observed in
					
			observer.shouldBeVisible = observed.isChangingLoginState || observed.lastError != nil 
			observer.showSpinner = observed.isChangingLoginState
			if observed.isChangingLoginState {
//				observer.statusText = observed.isLoggedIn() ? "Logging out" : "Logging in"
				observer.statusText = "Logging in"
			}
			else {
				if let error = observed.lastError {
					observer.errorText = error.getErrorString()
	//				observer.statusText = "This is a very long error string, specifically to test out how the cell resizes itself in response to the text in the label changing."
				}
				else {
					observer.errorText = nil
				}
			}
		}?.schedule()
	}
}


// When errorText is non-nil, it's what's shown in the cell, and status is hidden.
@objc class OperationStatusCell: BaseCollectionViewCell, OperationStatusCellProtocol {
	@IBOutlet var errorLabel: UILabel!
	@IBOutlet var statusView: UIView!
	@IBOutlet var statusLabel: UILabel!
	@IBOutlet var spinner: UIActivityIndicatorView!
	@objc dynamic var collection: UICollectionView?

	private static let cellInfo = [ "OperationStatusCell" : PrototypeCellInfo("OperationStatusCell") ]
	override class var validReuseIDDict: [ String: PrototypeCellInfo ] { return cellInfo }

	var statusText: String = "" {
		didSet { 
			statusLabel.text = statusText
			self.layer.removeAllAnimations()
		}
	}
	var errorText: String? {
		didSet {
			errorLabel.isHidden = errorText == nil
			statusView.isHidden = errorText != nil
			errorLabel.text = errorText
			self.layer.removeAllAnimations()
		}
	}
	
	var showSpinner: Bool = false { 
		didSet { spinner.isHidden = !showSpinner }
	}
}

