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

    override func viewDidLoad() {
        super.viewDidLoad()
                
   		// Set up the FRCs for the messages in the thread and the messages in the send queue
   		var messagePredicate: NSPredicate
 		if let model = threadModel {
			messagePredicate = NSPredicate(format: "thread.id = '\(model.id)'")
		}
		else {
			messagePredicate = NSPredicate(value: false)
		}
   		messageSegment.activate(predicate: messagePredicate, sort: [ NSSortDescriptor(key: "timestamp", ascending: true) ],
   				cellModelFactory: createMessageCellModel)
   		queuedMsgSegment.activate(predicate: messagePredicate, sort: [ NSSortDescriptor(key: "originalPostTime", ascending:true) ],
   				cellModelFactory: createMessageOpCellModel)
							
		// Next, the filter segment for the new message text field and button.
		newMessageSegment.append(postingCell)
		sendButtonCell = ButtonCellModel(title: "Send", action: weakify(self, type(of: self).sendButtonHit))
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
