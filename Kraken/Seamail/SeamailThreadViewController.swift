//
//  SeamailThreadViewController.swift
//  Kraken
//
//  Created by Chall Fry on 5/15/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit
import CoreData

class SeamailThreadViewController: BaseCollectionViewController {

	var threadModel: SeamailThread?
	
	private let compositeDataSource = KrakenDataSource()
	private let 	messageSegment = FRCDataSourceSegment<SeamailMessage>()
	private let 	queuedMsgSegment = FRCDataSourceSegment<PostOpSeamailMessage>()
	private let 	newMessageSegment = FilteringDataSourceSegment()
	private let dataManager = SeamailDataManager.shared
	private let coreData = LocalCoreData.shared
	
	var postingCell = TextViewCellModel("")
	var sendButtonCell: ButtonCellModel?
	private var isBusyPosting: Bool = false
	private var postAuthor: String = ""

// MARK: Methods
    override func viewDidLoad() {
        super.viewDidLoad()
        knownSegues = [.dismiss]
        if let thread = threadModel {
	        SeamailDataManager.shared.loadSeamailThread(thread: thread) {
      		}
		}
        
        // Save the name of the logged in user at load time; if that user changes dismiss the view.
        // We *might* loosen this restriction so that if both prev and current user are in the thread
        // we could stay, but that's awful thin. Obviously, if we transition to logged out or to a user not
        // in this thread we can't show the thread.
        postAuthor = CurrentUser.shared.loggedInUser?.username ?? ""
        CurrentUser.shared.tell(self, when: "loggedInUser") { observer, observed in
        	if observer.postAuthor != CurrentUser.shared.loggedInUser?.username {
        		observer.performKrakenSegue(.dismiss, sender: observer.threadModel)
        	}
        }
        
        if let participants = threadModel?.participants, let currentUsername = CurrentUser.shared.loggedInUser?.username {
        	let others = participants.compactMap { $0.username != currentUsername ? $0.username : nil }
        	if others.count == 1, let otherPerson = others.first {
        		title = "@\(otherPerson)"
        	}
        	else if others.count == 2 {
        		let sorted = others.sorted()
        		title = "@\(sorted[0]), @\(sorted[1])"
        	}
        	else {
        		title = "\(participants.count) Seamonkey Chat "
        	}
        }
                
   		// Set up the FRCs for the messages in the thread and the messages in the send queue
   		var messagePredicate: NSPredicate
   		var opPredicate: NSPredicate
 		if let model = threadModel {
			messagePredicate = NSPredicate(format: "thread.id = '\(model.id)'")
			opPredicate = NSPredicate(format: "thread.id = '\(model.id)' && operationState < 4")
		}
		else {
			messagePredicate = NSPredicate(value: false)
			opPredicate = messagePredicate
		}
   		messageSegment.activate(predicate: messagePredicate, sort: [ NSSortDescriptor(key: "timestamp", ascending: true) ],
   				cellModelFactory: createMessageCellModel)
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

		// Put everything together in the composite data source
		compositeDataSource.register(with: collectionView, viewController: self)
		compositeDataSource.append(segment: messageSegment)
		compositeDataSource.append(segment: queuedMsgSegment)
		compositeDataSource.append(segment: newMessageSegment)
		
		// When the cells finish getting added to the CV, scroll the CV to the bottom cell.
		compositeDataSource.scheduleBatchUpdateCompletionBlock {
			self.collectionView.scrollToItem(at: IndexPath(row: 1, section: 2), at: .bottom, animated: false)
		}
    }
    
    override func viewDidAppear(_ animated: Bool) {
    	super.viewDidAppear(animated)
		compositeDataSource.enableAnimations = true
		threadModel?.markThreadAsRead()
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
