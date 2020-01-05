//
//  SocalViewController.swift
//  Kraken
//
//  Created by Chall Fry on 9/5/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit

class SocialViewController: BaseCollectionViewController {
	let dataSource = KrakenDataSource()

    override func viewDidLoad() {
        super.viewDidLoad()
		title = "Social"

  		dataSource.register(with: collectionView, viewController: self)
  		dataSource.viewController = self

		let threeSocialTypesSection = dataSource.appendFilteringSegment(named: "socalTypes")
		let topCell = LabelCellModel("\"All three types of social media, all in one place.\"")
		threeSocialTypesSection.append(topCell)
		threeSocialTypesSection.append(SocialCellModel("Twittar", imageNamed: "Twitarr", 
					nav: GlobalNavPacket(tab: .twitarr, arguments: [:])))
		threeSocialTypesSection.append(SocialCellModel("Forums", imageNamed: "Forums",
					nav: GlobalNavPacket(tab: .forums, arguments: [:])))
		threeSocialTypesSection.append(SocialCellModel("Seamail", imageNamed: "Seamail",
					nav: GlobalNavPacket(tab: .seamail, arguments: [:])))
		
		//
		// Tweet Mentions
		// Forum Mentions
		// Unread Seamail
		// Announcements?
		
		setupGestureRecognizer()
    }
}

@objc protocol SocialCellProtocol {
	dynamic var labelText: String? { get set }
	dynamic var iconName: String? { get set }
}

@objc class SocialCellModel : BaseCellModel, SocialCellProtocol {
	private static let validReuseIDs = [ "SocialCell" : SocialCell.self ]
	override class var validReuseIDDict: [String: BaseCollectionViewCell.Type ] { return validReuseIDs }

	dynamic var labelText: String? 
	dynamic var iconName: String?
	var navPacket: GlobalNavPacket
	

	init(_ titleLabel: String, imageNamed: String, nav: GlobalNavPacket) {
		labelText = titleLabel
		iconName = imageNamed
		self.navPacket = nav
		super.init(bindingWith: SocialCellProtocol.self)
	}
}

class SocialCell: BaseCollectionViewCell, SocialCellProtocol {
	@IBOutlet var label: UILabel!
	@IBOutlet var imageView: UIImageView!
	
	private static let cellInfo = [ "SocialCell" : PrototypeCellInfo("SocialCell") ]
	override class var validReuseIDDict: [ String: PrototypeCellInfo ] { return cellInfo }
	
	var labelText: String? {
		didSet { label.text = labelText }
	}
	var iconName: String? {
		didSet { 
			if let name = iconName {
				imageView.image = UIImage(named: name) 
			}
			else {
				imageView.image = nil
			}
		}
	}
	
	override var isHighlighted: Bool {
		didSet {
			if isHighlighted, let cm = cellModel as? SocialCellModel {
				RootTabBarViewController.shared?.globalNavigateTo(packet: cm.navPacket)
			}
		}
	}
}
