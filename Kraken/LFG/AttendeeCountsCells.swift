//
//  AttendeeCountsCell.swift
//  Kraken
//
//  Created by Chall Fry on 2/3/23.
//  Copyright © 2023 Chall Fry. All rights reserved.
//

import Foundation
import UIKit
import CoreData

@objc protocol AttendeeCountsCellBindingProtocol: KrakenCellBindingProtocol {
	var minAttendees: Int32 { get set }
	var maxAttendees: Int32 { get set }
}

@objc class AttendeeCountsCellModel: BaseCellModel, AttendeeCountsCellBindingProtocol {
	override class var validReuseIDDict: [String: BaseCollectionViewCell.Type ] { return [ "AttendeeCountsCell" : AttendeeCountsCell.self ] }

	dynamic var minAttendees: Int32 = 2 {
		didSet { minAttendees = minAttendees.clamped(to: 2...50) }
	}
	dynamic var maxAttendees: Int32 = 2 {
		didSet { maxAttendees = maxAttendees.clamped(to: 2...50) }
	}

	init() {
		super.init(bindingWith: AttendeeCountsCellBindingProtocol.self)
	}
}

class AttendeeCountsCell: BaseCollectionViewCell, AttendeeCountsCellBindingProtocol, UITextFieldDelegate {
	private static let cellInfo = [ "AttendeeCountsCell" : PrototypeCellInfo("AttendeeCountsCell") ]
	override class var validReuseIDDict: [ String: PrototypeCellInfo] { return AttendeeCountsCell.cellInfo }
	
	@IBOutlet weak var minAttendeesField: UITextField!	
	@IBOutlet weak var maxAttendeesField: UITextField!	
	@IBOutlet weak var minAttendeesStepper: UIStepper!
	@IBOutlet weak var maxAttendeesStepper: UIStepper!
	
	var minAttendees: Int32 = 2 {
		didSet { 
			if minAttendees != Int32(minAttendeesStepper.value) {
				minAttendeesField.text = String(minAttendees)
				minAttendeesStepper.value = Double(minAttendees)
			}
		}
	}
	
	var maxAttendees: Int32 = 2 {
		didSet { 
			if maxAttendees != Int32(maxAttendeesStepper.value) {
				maxAttendeesField.text = String(maxAttendees)
				maxAttendeesStepper.value = Double(maxAttendees)
			}
		}
	}
	
	override func awakeFromNib() {
		super.awakeFromNib()
		
		minAttendeesStepper.addTarget(self, action: #selector(self.stepperValueChanged), for: .valueChanged)
		maxAttendeesStepper.addTarget(self, action: #selector(self.stepperValueChanged), for: .valueChanged)
		minAttendeesField.delegate = self
		maxAttendeesField.delegate = self
	}
	
	@objc func stepperValueChanged(sender: UIStepper) {
		if sender == minAttendeesStepper {
			minAttendeesField.text = String(Int(sender.value))
			(cellModel as? AttendeeCountsCellBindingProtocol)?.minAttendees = Int32(sender.value)
		}
		else {
			maxAttendeesField.text = String(Int(sender.value))
			(cellModel as? AttendeeCountsCellBindingProtocol)?.maxAttendees = Int32(sender.value)
		}
	}
	
	func textField(_ textField: UITextField, shouldChangeCharactersIn: NSRange, replacementString: String) -> Bool {
		var textFieldContents = textField.text ?? ""
		let swiftRange: Range<String.Index> = Range(shouldChangeCharactersIn, in: textFieldContents)!
		textFieldContents.replaceSubrange(swiftRange, with: replacementString)
		let value = Int32(textFieldContents) ?? 0
		if textFieldContents.allSatisfy({ $0.isNumber && $0.isASCII }), (0...50).contains(value) {
			if textField == minAttendeesField {
				minAttendeesStepper.value = Double(value)
				(cellModel as? AttendeeCountsCellBindingProtocol)?.minAttendees = value
			}
			else {
				maxAttendeesStepper.value = Double(value)
				(cellModel as? AttendeeCountsCellBindingProtocol)?.maxAttendees = value
			}
			return true
		}
		return false
	}
	
	func textFieldDidEndEditing(_ textField: UITextField, reason: UITextField.DidEndEditingReason) {
		let value = (Int32(textField.text ?? "0") ?? 0).clamped(to: 2...50)
		textField.text = String(value)
		if textField == minAttendeesField {
			minAttendeesStepper.value = Double(value)
			(cellModel as? AttendeeCountsCellBindingProtocol)?.minAttendees = value
		}
		else {
			maxAttendeesStepper.value = Double(value)
			(cellModel as? AttendeeCountsCellBindingProtocol)?.maxAttendees = value
		}
	}
}

extension Comparable {
	func clamped(to limits: ClosedRange<Self>) -> Self {
		return max(limits.lowerBound, min(self, limits.upperBound))
	}
}
