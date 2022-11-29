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
	private let 	participantSegment = FRCDataSourceSegment<SeamailMessage>()
	private let 	waitListSegment = FRCDataSourceSegment<PostOpSeamailMessage>()
	private let 	managementSegment = FilteringDataSourceSegment()
	private let dataManager = SeamailDataManager.shared
	private let coreData = LocalCoreData.shared
	
	lazy var usernameTextCell: TextFieldCellModel = {
		let cell = TextFieldCellModel("Search for User")
		cell.showClearTextButton = true
//		cell.returnButtonHit = textFieldReturnHit
		return cell
	}()
	
	lazy var userSuggestionsCell: UserListCoreDataCellModel = {
		let cell = UserListCoreDataCellModel(withTitle: "Suggestions")
//		cell.selectionCallback = suggestedUserTappedAction
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
		}
		SeamailDataManager.shared.loadSeamailThread(thread: thread) { }
        CurrentUser.shared.tell(self, when: "loggedInUser") { observer, observed in
			observer.performKrakenSegue(.dismiss, sender: observer.threadModel)
        }
        
//        if let participants = threadModel?.participants, let currentUsername = CurrentUser.shared.loggedInUser?.username {
//        	let others = participants.compactMap { $0.username != currentUsername ? $0.username : nil }
//        	if others.count == 1, let otherPerson = others.first {
//        		title = "@\(otherPerson)"
//        	}
//        	else if others.count == 2 {
//        		let sorted = others.sorted()
//        		title = "@\(sorted[0]), @\(sorted[1])"
//        	}
//        	else {
//        		title = "\(participants.count) Member Chat "
//        	}
//        }
                
		compositeDataSource.register(with: collectionView, viewController: self)
		managementSegment.append(usernameTextCell)
		managementSegment.append(userSuggestionsCell)
		managementSegment.append(messageRecipientsCell)
		managementSegment.append(subjectCell)
		managementSegment.append(messageCell)
		managementSegment.append(openOrClosedCell)
		managementSegment.append(postButtonCell)

   		// Set up the FRCs for the messages in the thread and the messages in the send queue
   		var messagePredicate: NSPredicate
   		var opPredicate: NSPredicate
 		if let model = threadModel {
			messagePredicate = NSPredicate(format: "thread.id = %@", model.id as CVarArg)
			opPredicate = NSPredicate(format: "thread.id = %@ && operationState < 4", model.id as CVarArg)
		}
		else {
			messagePredicate = NSPredicate(value: false)
			opPredicate = messagePredicate
		}
   		messageSegment.activate(predicate: messagePredicate, sort: [ NSSortDescriptor(key: "id", ascending: true) ],
   				cellModelFactory: createMessageCellModel)
		messageSegment.loaderDelegate = self
   		queuedMsgSegment.activate(predicate: opPredicate, sort: [ NSSortDescriptor(key: "originalPostTime", ascending:true) ],
   				cellModelFactory: createMessageOpCellModel)
							
		// Next, the filter segment for the new message text field and button.
		newMessageSegment.append(postingCell)
		let buttonCell = ButtonCellModel(title: "Send", action: weakify(self, type(of: self).sendButtonHit))
		sendButtonCell = buttonCell
		CurrentUser.shared.tell(buttonCell, when: ["loggedInUser", "credentialedUsers"]) { observer, observed in
			if CurrentUser.shared.isMultiUser(), let currentUser = CurrentUser.shared.loggedInUser {
				let posterFont = UIFont(name:"Georgia-Italic", size: 14)
				let posterColor = UIColor.darkGray
				let textAttrs: [NSAttributedString.Key : Any] = [ .font : posterFont as Any, 
						.foregroundColor : posterColor ]
				observer.infoText = NSAttributedString(string: "Posting as: \(currentUser.username)", attributes: textAttrs)
			}
			else {
				observer.infoText = nil
			}
		}?.execute()
		newMessageSegment.append(sendButtonCell!)
		if let model = threadModel, TwitarrV3FezType(rawValue: model.fezType) == .open {
			let labelText = NSAttributedString(string: "This is an open chat. The creator can add or remove members at any time.", 
					attributes: [.font: UIFont.systemFont(ofSize: 17, symbolicTraits: .traitItalic), 
					.foregroundColor: UIColor(named: "Kraken Secondary Text") as Any])
			let labelCell = LabelCellModel(labelText)
			newMessageSegment.append(labelCell)
			
			if model.owner?.userID == CurrentUser.shared.loggedInUser?.userID {
				let manageMembersBtn = ButtonCellModel(title: "Manage Members", alignment: .center) {
					print("button tapped")
				}
				newMessageSegment.append(manageMembersBtn)
			}
		}

		// Put everything together in the composite data source
		compositeDataSource.register(with: collectionView, viewController: self)
		compositeDataSource.append(segment: messageSegment)
		compositeDataSource.append(segment: queuedMsgSegment)
		compositeDataSource.append(segment: newMessageSegment)
	}
    
    override func viewDidAppear(_ animated: Bool) {
    	super.viewDidAppear(animated)
		compositeDataSource.enableAnimations = true
	}

	func createMessageCellModel(_ model:SeamailMessage) -> BaseCellModel {
			return SeamailMessageCellModel(withModel: model, reuse: "SeamailMessageCell")
	}
	
	func createMessageOpCellModel(_ model:PostOpSeamailMessage) -> BaseCellModel {
			return SeamailMessageCellModel(withModel: model, reuse: "SeamailMessageCell")
	}
	
	func sendButtonHit() {
		if let messageText = postingCell.getText(), messageText.count > 0, let thread = threadModel {
			SeamailDataManager.shared.queueNewSeamailMessageOp(existingOp: nil, message: messageText,
					thread: thread, done: postQueued)
			isBusyPosting = true
			postingCell.editText = "X"
			postingCell.editText = ""
		}
	}
	
	func postQueued(_ post: PostOpSeamailMessage?) {
		
	}
	
}

