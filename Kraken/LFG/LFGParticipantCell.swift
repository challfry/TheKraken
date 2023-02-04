//
//  LFGParticipantCell.swift
//  Kraken
//
//  Created by Chall Fry on 12/5/22.
//  Copyright © 2022 Chall Fry. All rights reserved.
//

import Foundation
import UIKit
import CoreData

@objc protocol ParticipantCellBindingProtocol: FetchedResultsBindingProtocol {
	dynamic var showActionButton: Bool { get set } 
	dynamic var actionButtonTitle: String { get set }
	dynamic var errorText: String? { get set }
	dynamic var buttonAction: (() -> Void)? { get set } 
//	dynamic var avatarButtonAction: (() -> Void)? { get set } 
}

@objc class ParticipantCellModel: FetchedResultsCellModel, ParticipantCellBindingProtocol {
	override class var validReuseIDDict: [String: BaseCollectionViewCell.Type ] { return [ "ParticipantCell" : ParticipantCell.self ] }
	dynamic var selectionCallback: (() -> Void)? 
	dynamic var showActionButton: Bool = false
	dynamic var actionButtonTitle: String = "Remove"
	dynamic var errorText: String?
	dynamic var buttonAction: (() -> Void)?
//	dynamic var avatarButtonAction: (() -> Void)?
		
	override init(withModel: NSFetchRequestResult?, reuse: String, bindingWith: Protocol = ParticipantCellBindingProtocol.self)
	{
		super.init(withModel: withModel, reuse: reuse, bindingWith: bindingWith)
	}
}

class ParticipantCell: BaseCollectionViewCell, ParticipantCellBindingProtocol {
	@IBOutlet var imageButton: UIButton!
	@IBOutlet var usernameLabel: UILabel!
	@IBOutlet var actionButton: UIButton!
	@IBOutlet var errorLabel: UILabel!
	
	dynamic var buttonAction: (() -> Void)?
	
	private static let cellInfo = [ "ParticipantCell" : PrototypeCellInfo("LFGParticipantCell") ]
	override class var validReuseIDDict: [ String: PrototypeCellInfo] { return ParticipantCell.cellInfo }
			
	var model: NSFetchRequestResult? {
		didSet {
			clearObservations()

			imageButton.setTitle("", for: .normal)
			if let user = model as? KrakenUser {
	    		addObservation(user.tell(self, when:"thumbPhoto") { observer, observed in
					observed.loadUserThumbnail()
					observer.imageButton.setBackgroundImage(observed.thumbPhoto, for: .normal)
	    		}?.execute())
	    		addObservation(user.tell(self, when:"username") { observer, observed in
					observer.usernameLabel.text = observed.username
	    		}?.execute())
			}
			else if model == nil {
				imageButton.setBackgroundImage(UIImage(named: "UnknownUser"), for: .normal)
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
	
	var errorText: String? {
		didSet {
			errorLabel.text = errorText
			cellSizeChanged()
		}
	}
	
	@IBAction func buttonTapped(_ sender: Any) {
		buttonAction?()
	}

	@IBAction func avatarButtonAction(_ sender: Any) {
		if let modeledUser = model as? KrakenUser, let vc = viewController as? BaseCollectionViewController {
			vc.performKrakenSegue(.userProfile_User, sender: modeledUser)
		}
	}
	
	
	
}

