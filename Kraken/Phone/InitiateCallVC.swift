//
//  InitiateCallVC.swift
//  Kraken
//
//  Created by Chall Fry on 1/11/23.
//  Copyright © 2023 Chall Fry. All rights reserved.
//

import Foundation
import UIKit
import AVFoundation

@objc class InitiateCallVC: BaseCollectionViewController, GlobalNavEnabled {

	let compositeDataSource = KrakenDataSource()
	var 	userSearchSegment = FilteringDataSourceSegment()
	var 	matchingUsersSegment = FRCDataSourceSegment<KrakenUser>()
	var 	favoritesHeaderSegment = FilteringDataSourceSegment()
	var 	favoriteUsersSegment = FRCDataSourceSegment<KrakenUser>()

// MARK: Methods
	override func viewDidLoad() {
        super.viewDidLoad()
        title = "KrakenTalk"
        CurrentUser.shared.tell(self, when: "loggedInUser") { observer, observed in
//			observer.performKrakenSegue(GlobalKnownSegue.dismiss, sender: self)
			self.dismiss(animated: true)
        }

   		// Set up the FRCs for the user search matches and the recent calls
   		matchingUsersSegment.fetchRequest.fetchLimit = 10
		matchingUsersSegment.activate(predicate: NSPredicate(value: false), sort: [ NSSortDescriptor(key: "username", ascending: true) ],
   				cellModelFactory: createMatchingUserCell)
		var favoriteUsersPredicate = NSPredicate(value: false)
		if let currentUser = CurrentUser.shared.loggedInUser {
			favoriteUsersPredicate = NSPredicate(format: "SELF IN %@.favoriteUsers", currentUser as CVarArg)
		}
		favoriteUsersSegment.activate(predicate: favoriteUsersPredicate, sort: [ NSSortDescriptor(key: "username", ascending: true) ],
				cellModelFactory: createMatchingUserCell)

		// Let the matchingUsersSegment know about changes made to the username search field
		let userSearchCell = createUserSearchCell()
        userSearchCell.tell(matchingUsersSegment, when: "editedText") { observer, observed in 
        	if let text = observed.getText(), !text.isEmpty {
        		observer.changePredicate(to: NSPredicate(format: "username CONTAINS[cd] %@", text))
	        	
	        	// Ask the server for name completions
	        	UserManager.shared.autocorrectUserLookup(for: text, done: { _ in })
			}
			else {
 	        	observer.changePredicate(to: NSPredicate(value: false))
			}
        }?.execute()
		userSearchSegment.append(userSearchCell)
        userSearchSegment.append(LabelCellModel("Type in a partial username, then tap \"Call\" on the user you want to call", 
        		fontTraits: .traitItalic, stringTraits: [.foregroundColor: UIColor(named: "Kraken Secondary Text") as Any]))
        		
		//
		favoritesHeaderSegment.append(createFavoritesHeaderCell())


		// Put everything together in the composite data source
		compositeDataSource.register(with: collectionView, viewController: self)
		compositeDataSource.append(segment: userSearchSegment)
		compositeDataSource.append(segment: matchingUsersSegment)
		compositeDataSource.append(segment: favoritesHeaderSegment)
		compositeDataSource.append(segment: favoriteUsersSegment)
		
         CurrentUser.shared.updateUserRelations(type: .favorite)
	}

    override func viewDidAppear(_ animated: Bool) {
    	super.viewDidAppear(animated)
		compositeDataSource.enableAnimations = true

        if AVCaptureDevice.authorizationStatus(for: AVMediaType.audio) != .authorized {
			AVCaptureDevice.requestAccess(for: AVMediaType.audio) { granted in
            }
        }
	}

// MARK: Cells
	func createUserSearchCell() -> TextFieldCellModel {
		let cell = TextFieldCellModel("User To Call:")
		cell.showClearTextButton = true
		return cell
	}

	func createMatchingUserCell(_ model: KrakenUser) -> BaseCellModel {
		let cell = ParticipantCellModel(withModel: model, reuse: "ParticipantCell")
		cell.showActionButton = model.userID != CurrentUser.shared.loggedInUser?.userID
		cell.buttonAction = { [weak self] in self?.callUserTappedAction(cell: cell, user: model) }
		cell.actionButtonTitle = "Call"
		return cell
	}

	func createFavoritesHeaderCell() -> LabelCellModel {
		let labelText = NSAttributedString(string: "Favorites:", attributes: [.font: UIFont.systemFont(ofSize: 17, symbolicTraits: .traitBold)])
		let cell = LabelCellModel(labelText)
		cell.bgColor = UIColor(named: "Info Title Background")
		return cell
	}
	
	var phonecall: CurrentCallInfo?
	
// MARK: Actions
	func callUserTappedAction(cell: ParticipantCellModel, user: KrakenUser) {
//   		let alert = UIAlertController(title: "Call \(user.username)?", message: "", 
//   				preferredStyle: .alert) 
//		alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
//		alert.addAction(UIAlertAction(title: "Call", style: .default, handler: { _ in
			PhonecallDataManager.shared.requestCallTo(user: user) { phonecall in
				self.phonecall = phonecall
				self.phonecall?.tell(cell, when: "callError") { observer, observed in
					if let callError = observed.callError as? ServerError {
						observer.errorText = "\(self.getShortTime()) \(callError.getGeneralError())"
					}
					else if let errorText = observed.callError?.localizedDescription {
						observer.errorText = "\(self.getShortTime()) \(errorText)"
					}
					else {
						observer.errorText = nil
					}
				}
			}
//		}))
//		present(alert, animated: true, completion: nil)
	}
	
	func getShortTime() -> String {
		let dateFormatter = DateFormatter()
		dateFormatter.locale = Locale(identifier: "en_US")
		dateFormatter.dateStyle = .none
		dateFormatter.timeStyle = .short
		return dateFormatter.string(from: Date())
	}

// MARK: Navigation
	override var knownSegues : Set<GlobalKnownSegue> {
		Set<GlobalKnownSegue>([ .activePhoneCall, .userProfile_User, .userProfile_Name, .dismiss ])
	}
	
    @discardableResult func globalNavigateTo(packet: GlobalNavPacket) -> Bool {
		return false
	}
}
