//
//  LoadingStatusCell.swift
//  Kraken
//
//  Created by Chall Fry on 4/25/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import Foundation
import UIKit


// LoadingStatusCell is meant to be used to indicate loads in progress. The cell should usually hide when a load
// isn't in progress, and there's no error state to show. Posts in progress should use the postOpStatusCell instead.
// Contains: activity name + spinner, or error status on failure
@objc protocol LoadingStatusCellProtocol {
	dynamic var statusText: String { get set }
	dynamic var errorText: String? { get set }
	dynamic var showSpinner: Bool { get set }
}

@objc class LoadingStatusCellModel: BaseCellModel, LoadingStatusCellProtocol {
	private static let validReuseIDs = [ "LoadingStatusCell" : LoadingStatusCell.self ]
	override class var validReuseIDDict: [String: BaseCollectionViewCell.Type ] { return validReuseIDs }

	@objc dynamic var errorText: String?
	@objc dynamic var statusText: String = ""
	@objc dynamic var showSpinner: Bool = false

	init() {
		super.init(bindingWith: LoadingStatusCellProtocol.self)
	}
}

@objc class LoginStatusCellModel: BaseCellModel, LoadingStatusCellProtocol {	
	private static let validReuseIDs = [ "LoadingStatusCell" : LoadingStatusCell.self ]
	override class var validReuseIDDict: [String: BaseCollectionViewCell.Type ] { return validReuseIDs }

	@objc dynamic var statusText: String = ""
	@objc dynamic var errorText: String?
	@objc dynamic var showSpinner: Bool = false

	init() {
		super.init(bindingWith: LoadingStatusCellProtocol.self)
		
		CurrentUser.shared.tell(self, when:[ "isChangingLoginState", "lastError" ]) { observer, observed in
					
			observer.shouldBeVisible = observed.isChangingLoginState || observed.lastError != nil 
			observer.showSpinner = observed.isChangingLoginState
			observer.statusText = "Logging in"
			if observed.isChangingLoginState {
//				observer.statusText = observed.isLoggedIn() ? "Logging out" : "Logging in"
			}
			if let error = observed.lastError {
				switch error {
					case let serverError as ServerError: observer.errorText = serverError.getGeneralError()
					case let networkError as NetworkError: observer.errorText = networkError.getErrorString()
					default: observer.errorText = error.localizedDescription
				}
//				observer.statusText = "This is a very long error string, specifically to test out how the cell resizes itself in response to the text in the label changing."
			}
			else {
				observer.errorText = nil
			}
		}?.schedule()
	}
}


// When errorText is non-nil, it's what's shown in the cell, and status is hidden.
@objc class LoadingStatusCell: BaseCollectionViewCell, LoadingStatusCellProtocol {
	@IBOutlet var errorLabel: UILabel!
	@IBOutlet var statusView: UIView!
	@IBOutlet var statusLabel: UILabel!
	@IBOutlet var spinner: UIActivityIndicatorView!
	@objc dynamic var collection: UICollectionView?

	private static let cellInfo = [ "LoadingStatusCell" : PrototypeCellInfo("LoadingStatusCell") ]
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
			cellSizeChanged()
		}
	}
	
	var showSpinner: Bool = false { 
		didSet { spinner.isHidden = !showSpinner }
	}
	
	override func awakeFromNib() {		
		// Font styling
		errorLabel.styleFor(.body)
		statusLabel.styleFor(.body)
	}
}

