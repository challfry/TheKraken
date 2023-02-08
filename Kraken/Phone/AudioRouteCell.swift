//
//  AudioRouteCell.swift
//  Kraken
//
//  Created by Chall Fry on 2/6/23.
//  Copyright © 2023 Chall Fry. All rights reserved.
//

import Foundation
import UIKit
import CoreData

@objc protocol AudioRouteCellBindingProtocol: KrakenCellBindingProtocol {
	var image: UIImage? { get set }
	var title: String { get set}
	var routeIsSelected: Bool { get set }
}

@objc class AudioRouteCellModel: BaseCellModel, AudioRouteCellBindingProtocol {
	override class var validReuseIDDict: [String: BaseCollectionViewCell.Type ] { return [ "AudioRouteCell" : AudioRouteCell.self ] }

	dynamic var image: UIImage?
	dynamic var title: String = ""
	dynamic var routeIsSelected: Bool
	var route: PhonecallDataManager.AudioRoute
	
	init(title: String, image: UIImage?, route: PhonecallDataManager.AudioRoute, checked: Bool = false) {
		self.title = title
		self.image = image
		self.routeIsSelected = checked
		self.route = route
		super.init(bindingWith: AudioRouteCellBindingProtocol.self)
	}
	
	override func cellTapped(dataSource: KrakenDataSource?, vc: UIViewController?) {
		if let activeCallVC = vc as? ActiveCallVC {
			activeCallVC.audioRouteTapped(route)
			routeIsSelected = true
		}
	}
}

class AudioRouteCell: BaseCollectionViewCell, AudioRouteCellBindingProtocol {
	private static let cellInfo = [ "AudioRouteCell" : PrototypeCellInfo("AudioRouteCell") ]
	override class var validReuseIDDict: [ String: PrototypeCellInfo] { return AudioRouteCell.cellInfo }
	
	@IBOutlet weak var iconImageView: UIImageView!
	@IBOutlet weak var titleLabel: UILabel!
	@IBOutlet weak var checkedImage: UIImageView!
	
	var image: UIImage? {
		didSet { iconImageView.image = image }
	}
	var title: String = "" {
		didSet { titleLabel.text = title }
	}
	var routeIsSelected: Bool = false {
		didSet { checkedImage.image = routeIsSelected ? UIImage(systemName: "checkmark.circle") : nil }
	}
	
	override var isHighlighted: Bool {
		didSet {
			standardHighlightHandler()
		}
	}
	
	override func awakeFromNib() {
		allowsSelection = true
		isAccessibilityElement = true
		titleLabel.styleFor(.body)
	}	
}

