//
//  ManageMembersVC.swift
//  Kraken
//
//  Created by Chall Fry on 11/27/22.
//  Copyright © 2022 Chall Fry. All rights reserved.
//

import UIKit
import CoreData

class ManageMembersVC: BaseCollectionViewController {

	var threadModel: SeamailThread?
	
	private let compositeDataSource = KrakenDataSource()
	private let 	participantLabelSegment = FilteringDataSourceSegment()
	private let 	participantSegment = FRCDataSourceSegment<KrakenUser>()
	private let 	waitListSegment = FRCDataSourceSegment<KrakenUser>()
	private let 	managementSegment = FilteringDataSourceSegment()
	private let 	userSuggestionSegment = FRCDataSourceSegment<KrakenUser>()
	private let dataManager = SeamailDataManager.shared
	private let coreData = LocalCoreData.shared
	
	lazy var usernameTextCell: TextFieldCellModel = {
		let cell = TextFieldCellModel("Search for User")
		cell.showClearTextButton = true
//		cell.returnButtonHit = textFieldReturnHit
		return cell
	}()
		
// MARK: Methods
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Manage Members"
        knownSegues = [.dismiss]
        guard let thread = threadModel else {
        	// Can't do anything--no fez to show
			performKrakenSegue(.dismiss, sender: threadModel)
			return
		}
		SeamailDataManager.shared.loadSeamailThread(thread: thread) { }
        CurrentUser.shared.tell(self, when: "loggedInUser") { observer, observed in
			observer.performKrakenSegue(.dismiss, sender: observer.threadModel)
        }
        
        participantLabelSegment.append(LabelCellModel("Participants:", fontTraits: .traitBold))
                        
   		// Set up the FRCs for the participants in the chat and the potential additions
   		let participantPredicate = NSPredicate(format: "seamailAttendee.id = %@", thread.id as CVarArg)
   		participantSegment.activate(predicate: participantPredicate, sort: [ NSSortDescriptor(key: "username", ascending: true) ],
   				cellModelFactory: createParticipantCellModel)
   		userSuggestionSegment.activate(predicate: NSPredicate(value: false), sort: [ NSSortDescriptor(key: "username", ascending: true) ],
   				cellModelFactory: createNewAdditionCellModel)
							
        // Let the userSuggestion cell know about changes made to the username text field
        usernameTextCell.tell(userSuggestionSegment, when: "editedText") { observer, observed in 
        	if let text = observed.getText(), !text.isEmpty {
        		observer.changePredicate(to: NSPredicate(format: "username CONTAINS[cd] %@", text))
	        	
	        	// Ask the server for name completions
	        	UserManager.shared.autocorrectUserLookup(for: text, done: { _ in })
			}
			else {
 	        	observer.changePredicate(to: NSPredicate(value: false))
			}
        }?.execute()
		managementSegment.append(usernameTextCell)
        managementSegment.append(LabelCellModel("Add users by searching for usernames, then tapping \"Add\" on the user to add", 
        		fontTraits: .traitItalic, stringTraits: [.foregroundColor: UIColor(named: "Kraken Secondary Text") as Any]))

		// Put everything together in the composite data source
		compositeDataSource.register(with: collectionView, viewController: self)
		compositeDataSource.append(segment: participantLabelSegment)
		compositeDataSource.append(segment: participantSegment)
//		compositeDataSource.append(segment: waitListSegment)
		compositeDataSource.append(segment: managementSegment)
		compositeDataSource.append(segment: userSuggestionSegment)
	}
    
    override func viewDidAppear(_ animated: Bool) {
    	super.viewDidAppear(animated)
		compositeDataSource.enableAnimations = true
	}

	func createParticipantCellModel(_ model: KrakenUser) -> BaseCellModel {
		let cell = ParticipantCellModel(withModel: model, reuse: "ParticipantCell")
		cell.showActionButton = model.userID != threadModel?.owner?.userID
		cell.buttonAction = { [weak self] in self?.removeUserTappedAction(user: model) }
		return cell
	}
	    
	func createNewAdditionCellModel(_ model: KrakenUser) -> BaseCellModel {
		let cell = ParticipantCellModel(withModel: model, reuse: "ParticipantCell")
		cell.actionButtonTitle = "Add"
		threadModel?.tell(cell, when: "participants") { observer, observed in
			observer.showActionButton = !(observed.participants.contains(where: { $0.userID == model.userID }))
		}?.execute()
		cell.buttonAction = { [weak self] in self?.addUserTappedAction(user: model) }
		return cell
	}
	    
// MARK: Actions
	func addUserTappedAction(user: KrakenUser) {
		if let thread = threadModel {	
			SeamailDataManager.shared.addUserToChat(user: user, thread: thread)
		}
	}
	
	func removeUserTappedAction(user: KrakenUser) {
		if let thread = threadModel {	
			SeamailDataManager.shared.removeUserFromChat(user: user, thread: thread)
		}
	}
	
}

extension ManageMembersVC: FRCDataSourceLoaderDelegate {
	func userIsViewingCell(at: IndexPath) {
	}
}
