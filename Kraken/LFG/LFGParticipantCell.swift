//
//  LFGParticipantCell.swift
//  Kraken
//
//  Created by Chall Fry on 12/5/22.
//  Copyright © 2022 Chall Fry. All rights reserved.
//

import Foundation
import UIKit

@objc protocol ParticipantCellBindingProtocol: FetchedResultsBindingProtocol {
	dynamic var showActionButton: Bool { get set } 
	dynamic var actionButtonTitle: String { get set }
	dynamic var buttonAction: (() -> Void)? { get set } 
}

@objc class ParticipantCellModel: FetchedResultsCellModel, ParticipantCellBindingProtocol {
	override class var validReuseIDDict: [String: BaseCollectionViewCell.Type ] { return [ "ParticipantCell" : ParticipantCell.self ] }
	dynamic var selectionCallback: (() -> Void)? 
	dynamic var showActionButton: Bool = false
	dynamic var actionButtonTitle: String = "Remove"
	dynamic var buttonAction: (() -> Void)?
		
	override init(withModel: NSFetchRequestResult?, reuse: String, bindingWith: Protocol = ParticipantCellBindingProtocol.self)
	{
		super.init(withModel: withModel, reuse: reuse, bindingWith: bindingWith)
	}
}

class ParticipantCell: BaseCollectionViewCell, ParticipantCellBindingProtocol {
	@IBOutlet var imageView: UIImageView!
	@IBOutlet var usernameLabel: UILabel!
	@IBOutlet var actionButton: UIButton!
	dynamic var buttonAction: (() -> Void)?
	
	private static let cellInfo = [ "ParticipantCell" : PrototypeCellInfo("LFGParticipantCell") ]
	override class var validReuseIDDict: [ String: PrototypeCellInfo] { return ParticipantCell.cellInfo }
			
	var model: NSFetchRequestResult? {
		didSet {
			clearObservations()

			if let user = model as? KrakenUser {
	    		addObservation(user.tell(self, when:"thumbPhoto") { observer, observed in
					observed.loadUserThumbnail()
					observer.imageView.image = observed.thumbPhoto
	    		}?.execute())
	    		addObservation(user.tell(self, when:"username") { observer, observed in
					observer.usernameLabel.text = observed.username
	    		}?.execute())
			}
			else if model == nil {
				imageView.image = UIImage(named: "UnknownUser")
				usernameLabel.text = "Unknown"
			}
		}
	}
	
	var showActionButton: Bool = false {
		didSet {
			actionButton.isHidden = !showActionButton
		}
	}
	
	var actionButtonTitle: String = "Remove" {
		didSet {
			actionButton.setTitle(actionButtonTitle, for: .normal)
		}
	}
	
	@IBAction func buttonTapped(_ sender: Any) {
		buttonAction?()
	}
	
}

