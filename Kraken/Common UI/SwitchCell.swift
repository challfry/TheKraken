//
//  SwitchCell.swift
//  Kraken
//
//  Created by Chall Fry on 7/7/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit

@objc protocol SwitchCellProtocol {

	dynamic var labelText: String? { get set }
	dynamic var switchState: Bool { get set } 
	dynamic var switchEnabled: Bool { get set } 
	dynamic var switchStateChanged: (() -> Void)? { get set } 
}

@objc class SwitchCellModel: BaseCellModel, SwitchCellProtocol {
	private static let validReuseIDs = [ "SwitchCell" : SwitchCell.self ]
	override class var validReuseIDDict: [String: BaseCollectionViewCell.Type ] { return validReuseIDs }

	dynamic var labelText: String?
	dynamic var switchState: Bool = false
	dynamic var switchEnabled: Bool = true
	dynamic var switchStateChanged: (() -> Void)?

	init(labelText: String) {
		self.labelText = labelText
		super.init(bindingWith: SwitchCellProtocol.self)
	}
}

class SwitchCell: BaseCollectionViewCell, SwitchCellProtocol {
	@IBOutlet var switchControl: UISwitch!
	@IBOutlet var label: UILabel!

	private static let cellInfo = [ "SwitchCell" : PrototypeCellInfo("SwitchCell") ]
	override class var validReuseIDDict: [ String: PrototypeCellInfo ] { return cellInfo }

	var labelText: String? { 
		didSet { 
			label.text = labelText 
			cellSizeChanged()
		} 
	}
	var switchState: Bool = false { didSet { switchControl.setOn(switchState, animated: true) } } 
	var switchEnabled: Bool = true { didSet { switchControl.isEnabled = switchEnabled } } 

	var switchStateChanged: (() -> Void)?
	@IBAction func switchTapped(_ sender: Any) {
		(cellModel as? SwitchCellProtocol)?.switchState = switchControl.isOn
		switchStateChanged?()
	}
}
