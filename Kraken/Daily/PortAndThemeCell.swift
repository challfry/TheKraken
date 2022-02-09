//
//  PortAndThemeCell.swift
//  Kraken
//
//  Created by Chall Fry on 2/2/20.
//  Copyright © 2020 Chall Fry. All rights reserved.
//

import UIKit

struct PortAndTheme {
	let cruiseDay: Int		// Day 1 is Saturday March 7, 2020
	let theme: String?

	let port: String
	let arrival: String?
	let departure: String?
}

@objc protocol PortAndThemeBindingProtocol {
}

class PortAndThemeCellModel: BaseCellModel, PortAndThemeBindingProtocol {
	private static let validReuseIDs = [ "PortAndThemeCell" : PortAndThemeCell.self ]
	override class var validReuseIDDict: [String: BaseCollectionViewCell.Type ] { return validReuseIDs }

	init() {
		super.init(bindingWith: PortAndThemeBindingProtocol.self)
	}
}

class PortAndThemeCell: BaseCollectionViewCell, PortAndThemeBindingProtocol {
	private static let cellInfo = [ "PortAndThemeCell" : PrototypeCellInfo("PortAndThemeCell") ]
	override class var validReuseIDDict: [ String: PrototypeCellInfo ] { return cellInfo }

	@IBOutlet var titleLabel: UILabel!
	@IBOutlet var portLabel: UILabel!
	@IBOutlet var arriveDepartLabel: UILabel!
	@IBOutlet var themeLabel: UILabel!
	
	static let itinerary: [PortAndTheme] = [
	PortAndTheme(cruiseDay: 1, theme: "Welcome, New Monkeys!", port: "Fort Lauderdale, Florida", arrival: nil, departure: "5:00 PM"),
	PortAndTheme(cruiseDay: 2, theme: "Heroes Day", port: "Half Moon Cay, Bahamas", arrival: "8:00 AM", departure: "5:00 PM"),
	PortAndTheme(cruiseDay: 3, theme: "Cosplay Day", port: "At Sea", arrival: nil, departure: nil),
	PortAndTheme(cruiseDay: 4, theme: nil, port: "Santo Domingo, Domician Republic", arrival: "10:00 AM", departure: "1:00 AM"),
	PortAndTheme(cruiseDay: 5, theme: "Formal Night", port: "At Sea", arrival: nil, departure: nil),
	PortAndTheme(cruiseDay: 6, theme: nil, port: "GrandTurk, Turks And Caicos", arrival: "8:00 AM", departure: "5:00 PM"),
	PortAndTheme(cruiseDay: 7, theme: "Jammies Day", port: "At Sea", arrival: nil, departure: nil),
	PortAndTheme(cruiseDay: 8, theme: "Goodbye, everyone!", port: "Fort Lauderdale, Florida", arrival: "7:00 AM", departure: nil)
	]
	
	override func awakeFromNib() {
        super.awakeFromNib()
        
		// Font styling
		portLabel.styleFor(.body)
		arriveDepartLabel.styleFor(.body)
		themeLabel.styleFor(.body)

		setupCellForToday()
    }
    
    func setupCellForToday() {
		let dateFormatter = DateFormatter()
		dateFormatter.locale = Locale(identifier: "en_US")
		dateFormatter.setLocalizedDateFormatFromTemplate("MMMMd")
		let shortDate = dateFormatter.string(from: cruiseCurrentDate())
		titleLabel.text = "Planned Itinerary for \(shortDate)"

		if let cruiseDay = dayOfCruise(), (1...8).contains(cruiseDay) {
	    	let pnt = PortAndThemeCell.itinerary[cruiseDay - 1]
    	
			let portText = NSMutableAttributedString(string: "Port: ", attributes: labelTextAttributes())
			portText.append(NSAttributedString(string: pnt.port, attributes: contentTextAttributes()))
			portLabel.attributedText = portText
			
			arriveDepartLabel.isHidden = false
			if let arrivalTime = pnt.arrival, let departureTime = pnt.departure {
				arriveDepartLabel.text = "— Arrive: \(arrivalTime), Depart: \(departureTime)"
			}
			else if let arrivalTime = pnt.arrival {
				arriveDepartLabel.text = "— Arrive: \(arrivalTime)"
			}
			else if let departureTime = pnt.departure {
				arriveDepartLabel.text = "— Depart: \(departureTime)"
			}
			else {
				arriveDepartLabel.isHidden = true
			}
			
			if let theme = pnt.theme {
				themeLabel.isHidden = false
				let themeText = NSMutableAttributedString(string: "Today's Theme: ", attributes: labelTextAttributes())
				themeText.append(NSAttributedString(string: theme, attributes: contentTextAttributes()))
				themeLabel.attributedText = themeText
			}
			else {
				themeLabel.isHidden = true
			}
		}
		else if let startDate = cruiseStartDate(), cruiseCurrentDate() < startDate {
			let ashoreDays = lastCruiseEndRelativeDays()
			
			let portText = NSMutableAttributedString(string: "Stranded Ashore: ", attributes: labelTextAttributes())
			portText.append(NSAttributedString(string: "Fort Lauderdale", attributes: contentTextAttributes()))
			portLabel.attributedText = portText
			
			arriveDepartLabel.isHidden = true
			
			themeLabel.isHidden = false
			let themeText = NSMutableAttributedString(string: "Extended shore leave: ", attributes: contentTextAttributes())
			themeText.append(NSAttributedString(string: "day \(ashoreDays)", attributes: labelTextAttributes()))
			themeLabel.attributedText = themeText
		}
		else if let ashoreDays = dayAfterCruise() {
			let portText = NSMutableAttributedString(string: "Stranded Ashore: ", attributes: labelTextAttributes())
			portText.append(NSAttributedString(string: "Fort Lauderdale", attributes: contentTextAttributes()))
			portLabel.attributedText = portText
			
			arriveDepartLabel.isHidden = true
			
			themeLabel.isHidden = false
			let themeText = NSMutableAttributedString(string: "Extended shore leave: ", attributes: contentTextAttributes())
			themeText.append(NSAttributedString(string: "day \(ashoreDays)", attributes: labelTextAttributes()))
			themeLabel.attributedText = themeText
		}
		else {
			self.cellModel?.shouldBeVisible = false
		}
    }

	func labelTextAttributes() -> [ NSAttributedString.Key : Any ] {
		let metrics = UIFontMetrics(forTextStyle: .body)
		let baseFont = UIFont(name:"Helvetica-Bold", size: 17) ?? UIFont.preferredFont(forTextStyle: .body)
		let scaledfont = metrics.scaledFont(for: baseFont)
		let result: [NSAttributedString.Key : Any] = [ .font : scaledfont as Any, 
				.foregroundColor : UIColor(named: "Kraken Label Text") as Any ]
		return result
	}
	
	func contentTextAttributes() -> [ NSAttributedString.Key : Any ] {
		let metrics = UIFontMetrics(forTextStyle: .body)
		let baseFont = UIFont(name:"Helvetica-Regular", size: 17) ?? UIFont.preferredFont(forTextStyle: .body)
		let scaledfont = metrics.scaledFont(for: baseFont)
		let result: [NSAttributedString.Key : Any] = [ .font : scaledfont as Any, 
				.foregroundColor : UIColor(named: "Kraken Label Text") as Any ]
		return result
	}
	
	
	
}


