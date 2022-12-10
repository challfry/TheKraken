//
//  PostOpStatusCell.swift
//  Kraken
//
//  Created by Chall Fry on 10/11/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit

@objc protocol PostOpStatusCellProtocol {
	dynamic var descriptionText: String? { get set }
	dynamic var statusText: String? { get set }
	dynamic var errorText: String? { get set }
	dynamic var showSpinner: Bool { get set }
	dynamic var disableCancelButton: Bool { get set }
	dynamic var hideCancelButton: Bool { get set }
}

@objc class OperationStatusCellModel: BaseCellModel, PostOpStatusCellProtocol {
	private static let validReuseIDs = [ "PostOpStatusCell" : PostOpStatusCell.self ]
	override class var validReuseIDDict: [String: BaseCollectionViewCell.Type ] { return validReuseIDs }

	@objc dynamic var descriptionText: String?
	@objc dynamic var errorText: String?
	@objc dynamic var statusText: String?
	@objc dynamic var showSpinner: Bool = false
	@objc dynamic var disableCancelButton: Bool = false
	@objc dynamic var hideCancelButton: Bool = false
	
	var cancelAction: (() -> Void)?

	init() {
		super.init(bindingWith: PostOpStatusCellProtocol.self)
	}
}

@objc class PostOpStatusCellModel: OperationStatusCellModel {
	@objc dynamic var postOp: PostOperation? {
		didSet {
			shouldBeVisible = postOp != nil
		}
	}
	
	override init() {
		super.init()
		self.tell(self, when: "postOp.errorString") { observer, observed in
			observer.errorText = observed.postOp?.errorString
		}?.execute()
		
		self.tell(self, when: "postOp.operationDescription") { observer, observed in
			observer.descriptionText = observed.postOp?.operationDescription
		}?.execute()
		
		self.tell(self, when: "postOp.operationState") { observer, observed in
			observer.statusText = observed.postOp?.operationStatus()
			if let state = observed.postOp?.operationState {
				observer.disableCancelButton = state == .callSuccess || state == .sentNetworkCall
			}
		}?.execute()
		
		cancelAction = { [weak self] in
			if let op = self?.postOp {
				PostOperationDataManager.shared.remove(op: op)
			}
		}
	}
}	

class PostOpStatusCell: BaseCollectionViewCell, PostOpStatusCellProtocol {
	private static let cellInfo = [ "PostOpStatusCell" : PrototypeCellInfo("PostOpStatusCell") ]
	override class var validReuseIDDict: [ String: PrototypeCellInfo ] { return cellInfo }

	@IBOutlet var descriptionLabel: UILabel!
	@IBOutlet var statusLabel: UILabel!
	@IBOutlet var errorLabel: UILabel!
	@IBOutlet var cancelButton: UIButton!

	var descriptionText: String? {
		didSet {
			descriptionLabel.text = descriptionText
			cellSizeChanged()
		}
	}
	var statusText: String? {
		didSet {
			statusLabel.text = statusText
			cellSizeChanged()
		}
	}
	var errorText: String? {
		didSet {
			errorLabel.text = errorText
			cellSizeChanged()
		}
	}
	var showSpinner: Bool = false // No spinner
	
	var disableCancelButton: Bool = false {
		didSet {
			cancelButton.isEnabled = !disableCancelButton
		}
	}
	
	var hideCancelButton: Bool = false {
		didSet {
			cancelButton.isHidden = hideCancelButton
		}
	}
	
	@IBAction func cancelButtonTapped(_ sender: Any) {
		if let model = cellModel as? OperationStatusCellModel {
			model.cancelAction?()
		}
	}
	
}
