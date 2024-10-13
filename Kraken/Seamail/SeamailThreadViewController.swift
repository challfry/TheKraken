//
//  SeamailThreadViewController.swift
//  Kraken
//
//  Created by Chall Fry on 5/15/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit
import CoreData
import Photos

class SeamailThreadViewController: BaseCollectionViewController {

	// Set by calling VC
	@objc dynamic var threadModel: SeamailThread?
	
	private let compositeDataSource = KrakenDataSource()
	private let 	headerSegment = FilteringDataSourceSegment()
	private let 	messageSegment = FRCDataSourceSegment<SeamailMessage>()
	private let 	queuedMsgSegment = FRCDataSourceSegment<PostOpSeamailMessage>()
	private let 	newMessageSegment = FilteringDataSourceSegment()
	private let dataManager = SeamailDataManager.shared
	private let coreData = LocalCoreData.shared
	
	@objc dynamic lazy var postingCell: TextViewCellModel =  {
		let cell = TextViewCellModel("")
		cell.labelText = "New Message"
		self.tell(cell, when: "threadModel.participants") { observer, observed in
			let isMember = observed.threadModel?.participants.first { $0.userID == CurrentUser.shared.loggedInUser?.userID } != nil
			observer.shouldBeVisible = isMember
		}?.execute()
		postingCell = cell
		return cell
	}()
	
	lazy var pictureCell: PhotoSelectionCellModel = {
		let cell = PhotoSelectionCellModel()
		cell.maxPhotos = 1
		cell.shouldBeVisible = false
		self.tell(cell, when: "threadModel") { observer, observed in
			if let model = observed.threadModel, let fezType = TwitarrV3FezType(rawValue: model.fezType), 
        			fezType != .open && fezType != .closed {
				observer.shouldBeVisible = true
			}
		}?.execute()
		return cell
	}()

	lazy var statusCell: PostOpStatusCellModel = {
		let cell = PostOpStatusCellModel()
		cell.shouldBeVisible = false
        cell.showSpinner = true
        cell.statusText = "Posting..."
        
        cell.cancelAction = { [weak cell, weak self] in
        	if let cell = cell, let op = cell.postOp {
        		PostOperationDataManager.shared.remove(op: op)
        		cell.postOp = nil
        	}
        	if let self = self {
        		self.isBusyPosting = false
        	}
        }
        return cell
	}()

	private var isBusyPosting: Bool = false
	private var postAuthor: String = ""

// MARK: Methods
    override func viewDidLoad() {
        super.viewDidLoad()
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
        
        // Set the view title
        if let model = threadModel, let fezType = TwitarrV3FezType(rawValue: model.fezType), 
        		let currentUsername = CurrentUser.shared.loggedInUser?.username {
        	if fezType == .open || fezType == .closed {
				let others = model.participants.compactMap { $0.username != currentUsername ? $0.username : nil }
				if others.count == 1, let otherPerson = others.first {
					title = "@\(otherPerson)"
				}
				else if others.count == 2 {
					let sorted = others.sorted()
					title = "@\(sorted[0]), @\(sorted[1])"
				}
				else {
					title = "\(model.participants.count) Member Chat "
				}
			}
			else {
				title = "\(fezType.label) LFG"
			}
        }
        
        // Header Segment: Owner, Time, Attendee Count, Location, Info. Participants OR attendees + waitlist.
        headerSegment.append(createTitleHeaderCell())
        headerSegment.append(createCanceledHeaderCell())
        headerSegment.append(createOwnerHeaderCell())
        headerSegment.append(createLocationHeaderCell())
        headerSegment.append(createTimeHeaderCell())
        headerSegment.append(createInfoHeaderCell())
        headerSegment.append(createAttendeeCountsCell())
        headerSegment.append(createParticipantsHeaderCell())
        headerSegment.append(createAttendeesHeaderCell())
        headerSegment.append(createWaitlistHeaderCell())
        headerSegment.append(createChatHeaderCell())
                
   		// Set up the FRCs for the messages in the thread and the messages in the send queue
		self.tell(self, when: "threadModel.participants") { observer, observed in
  			var messagePredicate: NSPredicate
   			var opPredicate: NSPredicate
			if let model = observed.threadModel, model.participants.first(where: { $0.userID == CurrentUser.shared.loggedInUser?.userID }) != nil {
				messagePredicate = NSPredicate(format: "thread.id = %@", model.id as CVarArg)
				opPredicate = NSPredicate(format: "thread.id = %@ && operationState < 4", model.id as CVarArg)
			}
			else {
				messagePredicate = NSPredicate(value: false)
				opPredicate = NSPredicate(value: false)
			}
			observer.messageSegment.activate(predicate: messagePredicate, sort: [ NSSortDescriptor(key: "id", ascending: true) ],
					cellModelFactory: observer.createMessageCellModel)
			observer.queuedMsgSegment.activate(predicate: opPredicate, sort: [ NSSortDescriptor(key: "originalPostTime", ascending:true) ],
					cellModelFactory: observer.createMessageOpCellModel)
		}?.execute()
		messageSegment.loaderDelegate = self
							
		// Next, the segment for the new message text field, send button, and join/leave/manage buttons.
		newMessageSegment.append(postingCell)
		newMessageSegment.append(pictureCell)
		newMessageSegment.append(createSendButtonCell())
        newMessageSegment.append(statusCell)
		newMessageSegment.append(createOpenChatInfoCell())
		newMessageSegment.append(createJoinLeaveManageCell())
		newMessageSegment.append(createEditLFGCell())
		newMessageSegment.append(createReportLFGCell())
		newMessageSegment.append(createCancelLFGCell())
		
		// Put everything together in the composite data source
		compositeDataSource.register(with: collectionView, viewController: self)
		compositeDataSource.append(segment: headerSegment)
		compositeDataSource.append(segment: messageSegment)
		compositeDataSource.append(segment: queuedMsgSegment)
		compositeDataSource.append(segment: newMessageSegment)
		
		// When the cells finish getting added to the CV, scroll the CV to the bottom cell.
		compositeDataSource.scheduleBatchUpdateCompletionBlock {
			let numSections = self.compositeDataSource.numberOfSections(in: self.collectionView)
			if numSections > 0 {
				self.collectionView.scrollToItem(at: IndexPath(row: 0, section: numSections - 1), at: .bottom, animated: false)
			}
		}
    }
    
    override func viewDidAppear(_ animated: Bool) {
    	super.viewDidAppear(animated)
		compositeDataSource.enableAnimations = true
	}

	func sendButtonHit() {
		if let messageText = postingCell.getText(), !messageText.isEmpty, let thread = threadModel {
			isBusyPosting = true
			let attachedPhoto = pictureCell.selectedPhotos.first
			ImageManager.shared.resizeImageForUpload(imageContainer: attachedPhoto, 
					progress: { (_ progress: Double?, _ error: Error?, _ stopPtr: UnsafeMutablePointer<ObjCBool>, _ info: [AnyHashable : Any]?) in
				if let error = error {
					self.statusCell.errorText = error.localizedDescription
				}
				else if let resultInCloud = info?[PHImageResultIsInCloudKey] as? NSNumber, resultInCloud.boolValue == true {
					self.statusCell.statusText = "Downloading full-sized photo from iCloud"
				}
			}, done: { (photoData, error) in
				if let err = error {
					self.statusCell.errorText = err.getCompleteError()
					self.isBusyPosting = false
				}
				else {
					SeamailDataManager.shared.queueNewSeamailMessageOp(existingOp: nil, message: messageText, photo: photoData,
							thread: thread, done: self.postQueued)
					self.postingCell.clearText()
					self.pictureCell.clearAllSelectedPhotos()
				}
			})
		}
	}
	
	func joinLeaveManageButtonHit() {
		guard let currentUser = CurrentUser.shared.loggedInUser, let thread = threadModel else {
			return
		}
		if let ownerID = thread.owner?.userID, ownerID == currentUser.userID {
			performKrakenSegue(.seamailManageMembers, sender: threadModel)
		}
		else if thread.participants.contains(where: { $0.userID == currentUser.userID }) {
			let alert = UIAlertController(title: "Leave LFG?", 
					message: "Are you sure you want to leave the LFG? You'll be giving up your spot--LFGs with limited space are first-come, first-served.", 
					preferredStyle: .actionSheet) 
			alert.addAction(UIAlertAction(title: "Leave", style: .default, handler: { _ in 
				SeamailDataManager.shared.removeUserFromChat(user: currentUser, thread: thread)
			}))
			alert.addAction(UIAlertAction(title: "Cancel", style: .default, handler: { _ in }))
			self.present(alert, animated: true, completion: nil)
		}
		else {
			SeamailDataManager.shared.addUserToChat(user: currentUser, thread: thread)
		}
	}
	
	func editLFGButtonHit() {
		performKrakenSegue(.lfgCreateEdit, sender: threadModel)
	}
	
	func reportLFGButtonHit() {
		guard let lfgModel = threadModel else { return } 
		performKrakenSegue(.reportContent, sender: lfgModel)
	}
	
	func cancelLFGButtonHit() {
		let message = "Cancelling the LFG will mark the LFG as not happening and notify all participants. The LFG won't be deleted; participants can still create and read posts."
   		let alert = UIAlertController(title: "Cancel LFG", message: message,  preferredStyle: .alert) 
		alert.addAction(UIAlertAction(title: NSLocalizedString("Do It", comment: "Cancel action"), 
				style: .destructive, handler: cancelLFGConfirmedHandler))
		alert.addAction(UIAlertAction(title: NSLocalizedString("Wait--Don't", comment: "Default action"), 
				style: .cancel, handler: nil))
		present(alert, animated: true, completion: nil)
	}
	
	func cancelLFGConfirmedHandler(_ action: UIAlertAction) {
		guard let lfgModel = threadModel else { return }
		SeamailDataManager.shared.markLFGCancelled(lfgModel)
	}
	
	func postQueued(_ post: PostOpSeamailMessage?) {
	}
	
// MARK: - Cells
	func createTitleHeaderCell() -> LabelCellModel {
		let cell = LabelCellModel("")
		self.tell(cell, when: ["threadModel.subject"]) { observer, observed in
			let labelText = NSMutableAttributedString()
			if let subject = observed.threadModel?.subject {
				labelText.append(NSAttributedString(string: subject, attributes: [.font: UIFont.systemFont(ofSize: 17, symbolicTraits: .traitBold)]))
			}
			observer.labelText = labelText
		}?.execute()
		cell.shouldBeVisible = true
		return cell
	}

	func createCanceledHeaderCell() -> LabelCellModel {
		let cell = LabelCellModel("This LFG has been canceled by its creator.", stringTraits: [.foregroundColor: UIColor(named: "Red Alert Text") as Any])
		self.tell(cell, when: ["threadModel.cancelled"]) { observer, observed in
			observer.shouldBeVisible = observed.threadModel?.cancelled == true
		}?.execute()
		return cell
	}

	func createOwnerHeaderCell() -> LabelCellModel {
		let cell = LabelCellModel("")
		self.tell(cell, when: ["threadModel.owner.username", "threadModel.owner.displayName"]) { observer, observed in
			let labelText = NSMutableAttributedString()
			if let owner = observed.threadModel?.owner {
				labelText.append(NSAttributedString(string: "Organizer: ", attributes: [.font: UIFont.systemFont(ofSize: 17, symbolicTraits: .traitBold)]))
				labelText.append(NSAttributedString(string: "\(owner.displayName) (@\(owner.username))", 
						attributes: [.font: UIFont.systemFont(ofSize: 17)]))
			}
			observer.labelText = labelText
		}?.execute()
		self.tell(cell, when: "threadModel.fezType") { observer, observed in
			observer.shouldBeVisible = !["open", "closed"].contains(observed.threadModel?.fezType)
		}?.execute()
		return cell
	}
	
	func createLocationHeaderCell() -> LabelCellModel {
		let cell = LabelCellModel("")
		self.tell(cell, when: ["threadModel.location"]) { observer, observed in
			let labelText = NSMutableAttributedString()
			if let location = observed.threadModel?.location {
				labelText.append(NSAttributedString(string: "Location: ", attributes: [.font: UIFont.systemFont(ofSize: 17, symbolicTraits: .traitBold)]))
				labelText.append(NSAttributedString(string: location, attributes: [.font: UIFont.systemFont(ofSize: 17)]))
			}
			observer.labelText = labelText
		}?.execute()
		self.tell(cell, when: "threadModel.fezType") { observer, observed in
			observer.shouldBeVisible = !["open", "closed"].contains(observed.threadModel?.fezType)
		}?.execute()
		return cell
	}
	
	func createTimeHeaderCell() -> LabelCellModel {
		let cell = LabelCellModel("")
		self.tell(cell, when: ["threadModel.startTime", "threadModel.endTime"]) { observer, observed in
			var labelText = NSAttributedString()
			if let thread = observed.threadModel, let startTime = thread.startTime {
				labelText = StringUtilities.eventTimeString(startTime: startTime, endTime: thread.endTime)
			}
			observer.labelText = labelText
		}?.execute()
		self.tell(cell, when: "threadModel.fezType") { observer, observed in
			observer.shouldBeVisible = !["open", "closed"].contains(observed.threadModel?.fezType)
		}?.execute()
		return cell
	}
	
	func createInfoHeaderCell() -> LabelCellModel {
		let cell = LabelCellModel("")
		self.tell(cell, when: ["threadModel.info"]) { observer, observed in
			let labelText = NSMutableAttributedString()
			if let info = observed.threadModel?.info {
				labelText.append(NSAttributedString(string: "Event Info: ", attributes: [.font: UIFont.systemFont(ofSize: 17, symbolicTraits: .traitBold)]))
				labelText.append(NSAttributedString(string: info, attributes: [.font: UIFont.systemFont(ofSize: 17)]))
			}
			observer.labelText = labelText
		}?.execute()
		self.tell(cell, when: "threadModel.fezType") { observer, observed in
			observer.shouldBeVisible = !["open", "closed"].contains(observed.threadModel?.fezType)
		}?.execute()
		return cell
	}
	
	func createAttendeeCountsCell() -> LabelCellModel {
		let cell = LabelCellModel("")
		self.tell(cell, when: ["threadModel.participantCount", "threadModel.maxParticipants"]) { observer, observed in
			let labelText = NSMutableAttributedString()
			if let model = observed.threadModel {
				labelText.append(NSAttributedString(string: "\(model.participantCount)/\(model.maxParticipants) attendees", attributes: [.font: UIFont.systemFont(ofSize: 17, symbolicTraits: .traitBold)]))
			}
			observer.labelText = labelText
		}?.execute()
		self.tell(cell, when: ["threadModel.fezType", "threadModel.participants"]) { observer, observed in
			let isMember = observed.threadModel?.participants.first { $0.userID == CurrentUser.shared.loggedInUser?.userID } != nil
			observer.shouldBeVisible = !["open", "closed"].contains(observed.threadModel?.fezType) && !isMember
		}?.execute()
		return cell
	}
	
	func createParticipantsHeaderCell() -> SeamailParticipantsCellModel {
		let cell = SeamailParticipantsCellModel(withTitle: "Participants:")
		self.tell(cell, when: ["threadModel.fezType", "threadModel.participants"]) { observer, observed in
			if let thread = observed.threadModel {
				observer.users = Array(thread.participants).sorted(by: { $0.username < $1.username } )
				observer.title = "\(thread.participantCount) participants"
				let isMember = thread.participants.first { $0.userID == CurrentUser.shared.loggedInUser?.userID } != nil
				observer.shouldBeVisible = ["open", "closed"].contains(thread.fezType) && isMember
			}
			else {
				observer.shouldBeVisible = false
			}
		}?.execute()
		return cell
	}
	
	func createAttendeesHeaderCell() -> SeamailParticipantsCellModel {
		let cell = SeamailParticipantsCellModel(withTitle: "Attendees:")
		self.tell(cell, when: ["threadModel.attendees"]) { observer, observed in
			observer.users = (observed.threadModel?.attendees.array as? [MaybeUser]) ?? []
			observer.title = "\(observed.threadModel?.attendees.count ?? 0)/\(observed.threadModel?.maxParticipants ?? 0) attendees:"
		}?.execute()
		self.tell(cell, when: ["threadModel.fezType", "threadModel.participants"]) { observer, observed in
			if let thread = observed.threadModel {
				let isMember = thread.participants.first { $0.userID == CurrentUser.shared.loggedInUser?.userID } != nil
				observer.shouldBeVisible = !["open", "closed"].contains(thread.fezType) && isMember
			}
			else {
				observer.shouldBeVisible = false
			}
		}?.execute()
		return cell
	}
	
	func createWaitlistHeaderCell() -> SeamailParticipantsCellModel {
		let cell = SeamailParticipantsCellModel(withTitle: "Wait List:")
		self.tell(cell, when: ["threadModel.waitList"]) { observer, observed in
			observer.users = (observed.threadModel?.waitList.array as? [MaybeUser]) ?? []
			observer.title = "\(observed.threadModel?.waitList.count ?? 0) on wait list:"
		}?.execute()
		self.tell(cell, when: ["threadModel.fezType", "threadModel.participants"]) { observer, observed in
			let isLFG = !["open", "closed"].contains(observed.threadModel?.fezType)
			let isMember = observed.threadModel?.participants.first { $0.userID == CurrentUser.shared.loggedInUser?.userID } != nil
			let hasWaitlist = observed.threadModel?.waitList.count ?? 0 > 0
			observer.shouldBeVisible = isLFG && hasWaitlist && isMember
		}?.execute()
		return cell
	}
	
	func createChatHeaderCell() -> LabelCellModel {
		let labelText = NSAttributedString(string: "Chat", attributes: [.font: UIFont.systemFont(ofSize: 17, symbolicTraits: .traitBold)])
		let cell = LabelCellModel(labelText)
		cell.bgColor = UIColor(named: "Info Title Background")
		self.tell(cell, when: "threadModel.participants") { observer, observed in
			let isMember = observed.threadModel?.participants.first { $0.userID == CurrentUser.shared.loggedInUser?.userID } != nil
			observer.shouldBeVisible = isMember
		}?.execute()
		return cell
	}

	// Gets called from within collectionView:cellForItemAt:
	func createMembersCellModel(_ model:SeamailThread) -> BaseCellModel {
		let cellModel = SeamailThreadCellModel(withModel: model, reuse: "seamailThread")
		return cellModel
	}

	func createMessageCellModel(_ model:SeamailMessage) -> BaseCellModel {
		return SeamailMessageCellModel(withModel: model, reuse: "SeamailMessageCell")
	}
	
	func createMessageOpCellModel(_ model:PostOpSeamailMessage) -> BaseCellModel {
		return SeamailMessageCellModel(withModel: model, reuse: "SeamailMessageCell")
	}
	
	func createNewPostEditCell() -> TextViewCellModel {
		let cell = TextViewCellModel("")
		cell.labelText = "New Message"
		self.tell(cell, when: "threadModel.participants") { observer, observed in
			let isMember = observed.threadModel?.participants.first { $0.userID == CurrentUser.shared.loggedInUser?.userID } != nil
			observer.shouldBeVisible = isMember
		}?.execute()
		postingCell = cell
		return cell
	}
	
//	func createAttachPhotoCell() -> PhotoSelectionCellModel {
//		let cell = PhotoSelectionCellModel()
//		cell.maxPhotos = 1
//		cell.shouldBeVisible = false
//        if let model = threadModel, let fezType = TwitarrV3FezType(rawValue: model.fezType), 
//        		fezType != .open && fezType != .closed {
//			cell.shouldBeVisible = true
//		}
//		return cell
//	}
	
	func createSendButtonCell() -> ButtonCellModel {
		let buttonCell = ButtonCellModel(title: "Send", action: weakify(self, type(of: self).sendButtonHit))
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
		self.tell(buttonCell, when: "threadModel.participants") { observer, observed in
			let isMember = observed.threadModel?.participants.first { $0.userID == CurrentUser.shared.loggedInUser?.userID } != nil
			observer.shouldBeVisible = isMember
		}?.execute()
		self.tell(buttonCell, when: "postingCell.editedText") { observer, observed in
			observer.button1Enabled = !(observed.postingCell.editedText?.isEmpty ?? true)
		}?.execute()
		return buttonCell
	}
	
	func createOpenChatInfoCell() -> LabelCellModel {
		let labelText = NSAttributedString(string: "This is an open chat. The creator can add or remove members at any time.", 
				attributes: [.font: UIFont.systemFont(ofSize: 17, symbolicTraits: .traitItalic), 
				.foregroundColor: UIColor(named: "Kraken Secondary Text") as Any])
		let cell = LabelCellModel(labelText)
		self.tell(cell, when: "postingCell.") { observer, observed in
			if let str = observed.threadModel?.fezType, let type = TwitarrV3FezType(rawValue: str) {
				observer.shouldBeVisible = type == .open
			}
			else {
				observer.shouldBeVisible = false
			}
		}?.execute()
		return cell
	}
	
	func createJoinLeaveManageCell() -> ButtonCellModel {
		let cell = ButtonCellModel(title: "Join this LFG", alignment: .center, action: weakify(self, type(of: self).joinLeaveManageButtonHit))
		self.tell(cell, when: ["threadModel.participants", "threadModel.owner.userID"]) { observer, observed in
			if observed.threadModel?.owner?.userID == CurrentUser.shared.loggedInUser?.userID {
				observer.button1Text = "Manage Members" 
			}
			else {
				let isMember = observed.threadModel?.participants.first { $0.userID == CurrentUser.shared.loggedInUser?.userID } != nil
				observer.button1Text = isMember ? "Leave this LFG" : "Join this LFG" 
			}
		}?.execute()
		self.tell(cell, when: "threadModel.fezType") { observer, observed in
			if let str = observed.threadModel?.fezType, let type = TwitarrV3FezType(rawValue: str) {
				observer.shouldBeVisible = type != .closed
			}
			else {
				observer.shouldBeVisible = false
			}
		}?.execute()
		return cell
	}
	
	func createEditLFGCell() -> ButtonCellModel {
		let cell = ButtonCellModel(title: "Edit LFG", alignment: .center, action: weakify(self, type(of: self).editLFGButtonHit))
		self.tell(cell, when: ["threadModel.fezType", "threadModel.owner"]) { observer, observed in
			if let str = observed.threadModel?.fezType, let type = TwitarrV3FezType(rawValue: str), ![.closed, .open].contains(type),
					let owner = observed.threadModel?.owner, owner.userID == CurrentUser.shared.loggedInUser?.userID {
				observer.shouldBeVisible = true
			}
			else {
				observer.shouldBeVisible = false
			}
		}?.execute()
		return cell
	}
	
	func createReportLFGCell() -> ButtonCellModel {
		let cell = ButtonCellModel(title: "Report this LFG", alignment: .center, action: weakify(self, type(of: self).reportLFGButtonHit))
		self.tell(cell, when: ["threadModel.fezType"]) { observer, observed in
			if let str = observed.threadModel?.fezType, let type = TwitarrV3FezType(rawValue: str), ![.closed, .open].contains(type) {
				observer.shouldBeVisible = true
			}
			else {
				observer.shouldBeVisible = false
			}
		}?.execute()
		return cell
	}
	
	func createCancelLFGCell() -> ButtonCellModel {
		let cell = ButtonCellModel(title: "Cancel this LFG", alignment: .center, action: weakify(self, type(of: self).cancelLFGButtonHit))
		self.tell(cell, when: ["threadModel.fezType", "threadModel.owner", "threadModel.cancelled"]) { observer, observed in
			if let str = observed.threadModel?.fezType, let type = TwitarrV3FezType(rawValue: str), ![.closed, .open].contains(type),
					let owner = observed.threadModel?.owner, owner.userID == CurrentUser.shared.loggedInUser?.userID,
					let cancelled = observed.threadModel?.cancelled, cancelled == false {
				observer.shouldBeVisible = true
			}
			else {
				observer.shouldBeVisible = false
			}
		}?.execute()
		return cell
	}
	
// MARK: Navigation
	override var knownSegues : Set<GlobalKnownSegue> {
		Set<GlobalKnownSegue>([ .dismiss, .seamailManageMembers, .lfgCreateEdit, .userProfile_User, .userProfile_Name, .reportContent,
				.fullScreenCamera, .cropCamera ])
	}

	// This is the unwind segue from the Manage Members view.
	@IBAction func dismissManageMembers(_ segue: UIStoryboardSegue) {
	}	
}

extension SeamailThreadViewController: FRCDataSourceLoaderDelegate {
	func userIsViewingCell(at: IndexPath) {
		threadModel?.markPostAsRead(index: at.row)
	}

}

