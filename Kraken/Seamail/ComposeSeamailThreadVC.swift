//
//  ComposeSeamailThreadVC.swift
//  Kraken
//
//  Created by Chall Fry on 7/8/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit

@objc class ComposeSeamailThreadVC: BaseCollectionViewController, GlobalNavEnabled {
	// PostOp for thread creation
	var threadToEdit: PostOpSeamailThread?

	let dataManager = SeamailDataManager.shared
	let composeDataSource = KrakenDataSource()
 
 // Recipient Chooser textfield?
 // Recipient List smallUser cells?
	var usernameTextCell: TextFieldCellModel?
	var userSuggestionsCell: UserListCoreDataCellModel?
	var messageRecipientsCell: UserListCoreDataCellModel?
	@objc dynamic var subjectCell: TextViewCellModel?
	@objc dynamic var messageCell: TextViewCellModel?
	var postButtonCell: ButtonCellModel?
	var postStatusCell: OperationStatusCellModel?
	
	var usersInRecentThreads = Set<PossibleKrakenUser>()
	var usersInThread = Set<PossibleKrakenUser>()
	@objc dynamic var threadHasRecipients = false
	@objc dynamic var isBusyPosting = false
	
	
// MARK: Methods
	override func viewDidLoad() {
        super.viewDidLoad()
        title = "New Seamail"

        usersInRecentThreads = buildRecentsList()

		composeDataSource.register(with: collectionView, viewController: self)
		let composeSection = composeDataSource.appendFilteringSegment(named: "ComposeSection")
		usernameTextCell = composeSection.append(cell: TextFieldCellModel("Participants"))
		usernameTextCell?.showClearTextButton = true
		usernameTextCell?.returnButtonHit = textFieldReturnHit
		userSuggestionsCell = composeSection.append(cell: UserListCoreDataCellModel(withTitle: "Suggestions"))
		userSuggestionsCell?.selectionCallback = suggestedUserTappedAction
		messageRecipientsCell = composeSection.append(cell: UserListCoreDataCellModel(withTitle: "Users In Thread"))
		messageRecipientsCell?.selectionCallback = userInThreadTappedAction
		messageRecipientsCell?.usePredicate = false
		messageRecipientsCell?.source = "(besides you)"
    	messageRecipientsCell?.users = usersInThread  	

		subjectCell = TextViewCellModel("Subject:")
		composeSection.append(subjectCell!)
		
		messageCell = TextViewCellModel("Initial Message:")
		composeSection.append(messageCell!)
		
		postButtonCell = ButtonCellModel()
		postButtonCell!.setupButton(2, title:"Send", action: weakify(self, type(of: self).postAction))
		composeSection.append(postButtonCell!)

        let statusCell = OperationStatusCellModel()
        statusCell.shouldBeVisible = false
        statusCell.showSpinner = true
        statusCell.statusText = "Sending..."
        postStatusCell = statusCell
 		composeSection.append(postStatusCell!)
       
        // If we are editing an existing Post operation, fill in from the post 
        if let thread = threadToEdit {
        	if let participants = thread.recipients {
        		for user in participants {
        			if let actualUser = user.actualUser {
        				addUserToThread(user: actualUser)
        			}
        			else {
        				addUsernameToThread(username: user.username)
        			}
        		}
        	}
        	subjectCell?.editText = thread.subject
			messageCell?.editText = thread.text
        }
        
        // Let the userSuggestion cell know about changes made to the username text field
        usernameTextCell?.tell(userSuggestionsCell!, when: "editedText") { observer, observed in 
        	if let text = observed.getText(), !text.isEmpty {
        		observer.usePredicate = true
	        	observer.predicate = NSPredicate(format: "username CONTAINS[cd] %@", text)
	        	observer.source = "from partial string match"
			}
			else {
        		observer.usePredicate = false
	        	observer.users = self.usersInRecentThreads
	        	observer.source = self.usersInRecentThreads.count > 0 ? "from recent Seamail threads" : ""
			}
        }?.execute()
        
        // Enable the Send button iff all the fields are filled in and we're not already sending.
        self.tell(self, when: ["threadHasRecipients", "subjectCell.editedText", "messageCell.editedText",
        		"isBusyPosting"]) { observer, observed in
			if let subjectText = observed.subjectCell?.getText(), let messageText = observed.messageCell?.getText(),
					observed.threadHasRecipients, subjectText.count > 0, messageText.count > 0, !observed.isBusyPosting {
				observer.postButtonCell?.button2Enabled = true
			}
			else {
				observer.postButtonCell?.button2Enabled = false
			}
        }?.execute()
    }
    
    func addUserToThread(user: KrakenUser) {
    	guard user.username != CurrentUser.shared.loggedInUser?.username else { return }
    	let possUser = PossibleKrakenUser(user: user)
    	possUser.canBeRemoved = true
    	usersInThread.insert(possUser)
   		threadHasRecipients = usersInThread.count > 0
    	messageRecipientsCell?.users = usersInThread  	
    }
    
    func addUsernameToThread(username: String) {
    	guard username != CurrentUser.shared.loggedInUser?.username, !username.isEmpty else { return }
    	let possUser = PossibleKrakenUser(username: username)
    	possUser.canBeRemoved = true
    	usersInThread.insert(possUser)
   		threadHasRecipients = usersInThread.count > 0
    	messageRecipientsCell?.users = usersInThread  	
    }
    
    func removeUserFromThread(user: PossibleKrakenUser) {
 		usersInThread.remove(user)
		messageRecipientsCell?.users = usersInThread
   		threadHasRecipients = usersInThread.count > 0
    }
    
    // Builds a list of users the logged in user has had recent Seamails with, for populating the Suggestions
    // cell when there's nothing better to put there.
    func buildRecentsList() -> Set<PossibleKrakenUser> {
    	// Grab the 50 most recent seamail threads, scavenge them for usernames.
    	let request = NSFetchRequest<SeamailThread>(entityName: "SeamailThread")
    	request.sortDescriptors = [ NSSortDescriptor(key: "timestamp", ascending: false)]
    	request.predicate = NSPredicate(value: true)
    	request.fetchLimit = 50
    	let fetchedObjects = try? LocalCoreData.shared.mainThreadContext.fetch(request)
    
    	var recentThreadParticipants: Set<KrakenUser> = Set()
    	if let threads = fetchedObjects {
	    	for thread in threads {
	    		// We're not including users in 'large' Seamail chats; they're likely busy (always at top), and the user is 
	    		// much more likely to want to start a new chat with people they've been having smaller chats with.
	    		if thread.participants.count < 20 {
	    			recentThreadParticipants.formUnion(thread.participants)
				}
				if recentThreadParticipants.count >= 20 {
					break
				}
    		}
		}
		if let currentUser = CurrentUser.shared.loggedInUser {
			recentThreadParticipants.remove(currentUser)
		}
		
		let recentPossThreadParticipants = Set(recentThreadParticipants.map { return PossibleKrakenUser(user: $0) })
		return recentPossThreadParticipants
    }
    
// MARK: Actions
	func textFieldReturnHit(_ textString: String) {
		addUsernameToThread(username: textString)	
	}

	func suggestedUserTappedAction(user: PossibleKrakenUser, isSelected: Bool) {
		if isSelected {
			if let krakenUser = user.user {
				addUserToThread(user: krakenUser)
			}
			else {
				addUsernameToThread(username: user.username)
			}
		}
	}
    
	func userInThreadTappedAction(user: PossibleKrakenUser, isSelected: Bool) {
		if isSelected {
			removeUserFromThread(user: user)
		}
	}
	
    func postAction() {
		if let subjectText = subjectCell?.getText(), let messageText = messageCell?.getText(),
				subjectText.count > 0, messageText.count > 0, usersInThread.count > 0 {
			SeamailDataManager.shared.queueNewSeamailThreadOp(existingOp: threadToEdit, subject: subjectText, 
					message: messageText, recipients: usersInThread, done: postQueued)
			isBusyPosting = true
			postStatusCell?.shouldBeVisible	= true
		}
	}
	
	func postQueued(_ post: PostOpSeamailThread?) {
		
	}
	
// MARK: Navigation
	func globalNavigateTo(packet: GlobalNavPacket) {
		if let userNames = packet.arguments["seamailThreadParticipants"] as? Set<String>, 
				let currentUsername = CurrentUser.shared.loggedInUser?.username {
			for userName in userNames {
				if userName != currentUsername {
					addUsernameToThread(username: userName)
				}
			}
		}
	}
	
}
