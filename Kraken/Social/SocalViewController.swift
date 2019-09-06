//
//  SocalViewController.swift
//  Kraken
//
//  Created by Chall Fry on 9/5/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit

class SocalViewController: BaseCollectionViewController {
	let dataSource = KrakenDataSource()

    override func viewDidLoad() {
        super.viewDidLoad()
		title = "Social"

  		dataSource.register(with: collectionView, viewController: self)
  		dataSource.viewController = self

		let threeSocialTypesSection = dataSource.appendFilteringSegment(named: "socalTypes")
		let topCell = LabelCellModel("\"All three types of social media, all in one place.\"")
		threeSocialTypesSection.append(topCell)
		threeSocialTypesSection.append(SocialCellModel("Twittar", imageNamed: "Twitarr", segueID: "Twitarr"))
		threeSocialTypesSection.append(SocialCellModel("Forums", imageNamed: "Forums", segueID: "Forums"))
		threeSocialTypesSection.append(SocialCellModel("Seamail", imageNamed: "Seamail", segueID: "Seamail"))
		
		//
		// Tweet Mentions
		// Forum Mentions
		// Unread Seamail
		// Announcements?
    }

	override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
    	switch segue.identifier {
			default: 
				print("huh.")
		}
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
	var segueID: String?
	

	init(_ titleLabel: String, imageNamed: String, segueID: String) {
		labelText = titleLabel
		iconName = imageNamed
		self.segueID = segueID
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
			if isHighlighted, let segueID = (cellModel as? SocialCellModel)?.segueID  {
				viewController?.performSegue(withIdentifier: segueID, sender: self)
			}
		}
	}
}
