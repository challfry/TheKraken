//
//  DatePickerCell.swift
//  Kraken
//
//  Created by Chall Fry on 2/2/23.
//  Copyright © 2023 Chall Fry. All rights reserved.
//

import Foundation
import UIKit
import CoreData

@objc protocol DatePickerCellBindingProtocol: KrakenCellBindingProtocol {
	var title: String { get set }
	var minuteInterval: Int { get set }
	var selectedDate: Date { get set }
}

@objc class DatePickerCellModel: BaseCellModel, DatePickerCellBindingProtocol {
	override class var validReuseIDDict: [String: BaseCollectionViewCell.Type ] { return [ "DatePickerCell" : DatePickerCell.self ] }

	dynamic var title: String = ""
	dynamic var minuteInterval: Int = 5
	dynamic var selectedDate: Date = Date()
	
	init(title: String, fixStartDate: Bool = true ) {
		self.title = title
		// Sets the initial time for the date picker to the next 30 minute interval--people often want to start events at 3:00,
		// but rarely want to start them at 3:13.
		if fixStartDate {
			let components = Calendar(identifier: .gregorian).dateComponents([.minute], from: cruiseCurrentDate())
			let minutesToAdd = 30 - ((components.minute ?? 0) % 30)
			selectedDate = Calendar(identifier: .gregorian).date(byAdding: .minute, value: minutesToAdd, to: cruiseCurrentDate()) ?? cruiseCurrentDate()
		}
		super.init(bindingWith: DatePickerCellBindingProtocol.self)
	}
}

class DatePickerCell: BaseCollectionViewCell, DatePickerCellBindingProtocol {
	private static let cellInfo = [ "DatePickerCell" : PrototypeCellInfo("DatePickerCell") ]
	override class var validReuseIDDict: [ String: PrototypeCellInfo] { return DatePickerCell.cellInfo }
	
	@IBOutlet weak var titleLabel: UILabel!
	@IBOutlet weak var datePicker: UIDatePicker!
	
	var title: String = "" {
		didSet { titleLabel.text = title }
	}
	var minuteInterval: Int = 5 {
		didSet { datePicker.minuteInterval = minuteInterval }
	}
	var selectedDate: Date = Date() {
		didSet { 
			if selectedDate != datePicker.date {
				datePicker.date = selectedDate 
			}			
		}
	}
	
	override func awakeFromNib() {
		super.awakeFromNib()
		datePicker.addTarget(self, action: #selector(self.updateDateFromControl), for: .valueChanged)
	}
	
	@objc func updateDateFromControl() {
		if let model = cellModel as? DatePickerCellBindingProtocol {
			model.selectedDate = datePicker.date
		}
	}
}

