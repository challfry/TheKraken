//
//  SmallUserCell.swift
//  Kraken
//
//  Created by Chall Fry on 7/14/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit

@objc protocol SmallUserCellBindingProtocol: FetchedResultsBindingProtocol {
	var username: String? { get set }
	var showDeleteIcon: Bool { get set } 
}

@objc class SmallUserCellModel: FetchedResultsCellModel, SmallUserCellBindingProtocol {
	override class var validReuseIDDict: [String: BaseCollectionViewCell.Type ] { return [ "SmallUserCell" : SmallUserCell.self ] }
	dynamic var selectionCallback: (() -> Void)? 
	dynamic var username: String?
	dynamic var showDeleteIcon: Bool = false
	
	@objc override dynamic var model: NSFetchRequestResult? {
		didSet {
			username = (model as? KrakenUser)?.username
		}
	}
	
	override init(withModel: NSFetchRequestResult?, reuse: String, bindingWith: Protocol = SmallUserCellBindingProtocol.self)
	{
		super.init(withModel: withModel, reuse: reuse, bindingWith: bindingWith)
		username = (model as? KrakenUser)?.username
	}
	
	override func cellTapped(dataSource: KrakenDataSource?, vc: UIViewController?) {
		selectionCallback?()
	}
}

class SmallUserCell: BaseCollectionViewCell, SmallUserCellBindingProtocol {
	@IBOutlet var imageView: UIImageView!
	@IBOutlet var usernameLabel: UILabel!
	@IBOutlet var deleteIcon: UIImageView!
	
	private static let cellInfo = [ "SmallUserCell" : PrototypeCellInfo("SmallUserCell") ]
	override class var validReuseIDDict: [ String: PrototypeCellInfo] { return SmallUserCell.cellInfo }
			
	var model: NSFetchRequestResult? {
		didSet {
			if let user = model as? KrakenUser {
	    		addObservation(user.tell(self, when:"thumbPhoto") { observer, observed in
					observed.loadUserThumbnail()
					observer.imageView.image = observed.thumbPhoto
	    		}?.execute())
			}
			else if model == nil {
				imageView.image = UIImage(named: "UnknownUser")
			}
		}
	}
	
	var username: String? {
		didSet {
			usernameLabel.text = "@\(username ?? "")"
			usernameLabel.accessibilityLabel = username ?? ""
		}
	}
	var showDeleteIcon: Bool = false {
		didSet {
			deleteIcon.isHidden = !showDeleteIcon
		}
	}
		
	override func awakeFromNib() {
		super.awakeFromNib()
		fullWidth = false
	}
	
		
	override var isHighlighted: Bool {
		didSet {
			standardHighlightHandler()
		}
	}
}

