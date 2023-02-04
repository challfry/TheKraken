//
//  ComposeSeamailThreadVC.swift
//  Kraken
//
//  Created by Chall Fry on 7/8/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit
import CoreData

@objc class ComposeSeamailThreadVC: BaseCollectionViewController, GlobalNavEnabled {
	// PostOp for thread creation
	var threadToEdit: PostOpSeamailThread?

	let dataManager = SeamailDataManager.shared
	let composeDataSource = KrakenDataSource()
 
 // Recipient Chooser textfield?
 // Recipient List smallUser cells?
	lazy var usernameTextCell: TextFieldCellModel = {
		let cell = TextFieldCellModel("Participants")
		cell.showClearTextButton = true
		cell.returnButtonHit = textFieldReturnHit
		return cell
	}()
	
	lazy var userSuggestionsCell: UserListCoreDataCellModel = {
		let cell = UserListCoreDataCellModel(withTitle: "Suggestions")
		cell.selectionCallback = suggestedUserTappedAction
		return cell
	}()
	
	lazy var messageRecipientsCell: UserListCoreDataCellModel = {
		let cell = UserListCoreDataCellModel(withTitle: "Users In Thread")
		cell.selectionCallback = userInThreadTappedAction
		cell.usePredicate = false
		cell.source = "(besides you)"
    	cell.users = usersInThread 
    	return cell		
	}()
	
	@objc dynamic lazy var subjectCell: TextViewCellModel = TextViewCellModel("Subject:")
	@objc dynamic lazy var messageCell: TextViewCellModel = TextViewCellModel("Initial Message:")

	lazy var openOrClosedCell = SwitchCellModel(labelText: "Make this an open chat so you can add or remove users later")
	
	lazy var postButtonCell: ButtonCellModel = {
		let buttonCell = ButtonCellModel()
		buttonCell.setupButton(2, title:"Send", action: weakify(self, type(of: self).postAction))
		return buttonCell
	}()

	lazy var postStatusCell: PostOpStatusCellModel = {
		let cell = PostOpStatusCellModel()
		cell.shouldBeVisible = false
        cell.showSpinner = true
        cell.statusText = "Sending..."
        
        cell.cancelAction = { [weak cell, weak self] in
        	if let cell = cell, let op = cell.postOp {
        		PostOperationDataManager.shared.remove(op: op)
        		cell.postOp = nil
        	}
        	if let self = self {
        //		self.setPostingState(false)
        	}
        }
        return cell
	}()
	
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
		composeSection.append(usernameTextCell)
		composeSection.append(userSuggestionsCell)
		composeSection.append(messageRecipientsCell)
		composeSection.append(subjectCell)
		composeSection.append(messageCell)
		composeSection.append(openOrClosedCell)
		composeSection.append(postButtonCell)
		
		CurrentUser.shared.tell(postButtonCell, when: ["loggedInUser", "credentialedUsers"]) { observer, observed in
			if CurrentUser.shared.isMultiUser(), let currentUser = CurrentUser.shared.loggedInUser {
				let posterFont = UIFont(name:"Georgia-Italic", size: 14)
				let posterColor = UIColor.darkGray
				let textAttrs: [NSAttributedString.Key : Any] = [ .font : posterFont as Any, 
						.foregroundColor : posterColor ]
				observer.infoText = NSAttributedString(string: "Posting as: \(currentUser.username)", attributes: textAttrs)
			}
			else {
				observer.infoText = NSAttributedString?.none
			}
		}?.execute()

 		composeSection.append(postStatusCell)
       
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
        	subjectCell.editText = thread.subject
			messageCell.editText = thread.text
        }
        
        // Let the userSuggestion cell know about changes made to the username text field
        usernameTextCell.tell(userSuggestionsCell, when: "editedText") { observer, observed in 
        	if let text = observed.getText(), !text.isEmpty {
        		observer.usePredicate = true
	        	observer.predicate = NSPredicate(format: "username CONTAINS[cd] %@", text)
	        	observer.source = "from partial string match"
	        	
	        	// Ask the server for name completions
	        	UserManager.shared.autocorrectUserLookup(for: text, done: self.userCompletionsCompletion)
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
			if let subjectText = observed.subjectCell.getText(), let messageText = observed.messageCell.getText(),
					observed.threadHasRecipients, subjectText.count > 0, messageText.count > 0, !observed.isBusyPosting {
				observer.postButtonCell.button2Enabled = true
			}
			else {
				observer.postButtonCell.button2Enabled = false
			}
        }?.execute()
    }
    
    override func viewDidAppear(_ animated: Bool) {
    	super.viewDidAppear(animated)
		composeDataSource.enableAnimations = true
		UserManager.shared.clearRecentAutocorrectSearches()
	}
    
    // When the server call completes we need to re-set the predicate. If we were using a fetchedResultsController,
    // we wouldn't need to do this (the FRC informs us of new results automatically)
    func userCompletionsCompletion(for: String?) {
    	let pred = userSuggestionsCell.predicate
		userSuggestionsCell.predicate = nil
    	userSuggestionsCell.predicate = pred
    }
    
    func addUserToThread(user: KrakenUser) {
    	guard user.username != CurrentUser.shared.loggedInUser?.username else { return }
    	let possUser = PossibleKrakenUser(user: user)
    	possUser.canBeRemoved = true
    	usersInThread.insert(possUser)
   		threadHasRecipients = usersInThread.count > 0
    	messageRecipientsCell.users = usersInThread  	
    }
    
    func addUsernameToThread(username: String) {
    	guard username != CurrentUser.shared.loggedInUser?.username, !username.isEmpty else { return }
    	let possUser = PossibleKrakenUser(username: username)
    	possUser.canBeRemoved = true
    	usersInThread.insert(possUser)
   		threadHasRecipients = usersInThread.count > 0
    	messageRecipientsCell.users = usersInThread  	
    }
    
    func removeUserFromThread(user: PossibleKrakenUser) {
 		usersInThread.remove(user)
		messageRecipientsCell.users = usersInThread
   		threadHasRecipients = usersInThread.count > 0
    }
    
    // Builds a list of users the logged in user has had recent Seamails with, for populating the Suggestions
    // cell when there's nothing better to put there.
    func buildRecentsList() -> Set<PossibleKrakenUser> {
    	// Grab the 50 most recent seamail threads, scavenge them for usernames.
    	let request = NSFetchRequest<SeamailThread>(entityName: "SeamailThread")
    	request.sortDescriptors = [ NSSortDescriptor(key: "lastModTime", ascending: false)]
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

	func suggestedUserTappedAction(user: PossibleKrakenUser) {
		if let krakenUser = user.user {
			addUserToThread(user: krakenUser)
		}
		else {
			addUsernameToThread(username: user.username)
		}
	}
    
	func userInThreadTappedAction(user: PossibleKrakenUser) {
		removeUserFromThread(user: user)
	}
	
    func postAction() {
		if let subjectText = subjectCell.getText(), let messageText = messageCell.getText(),
				subjectText.count > 0, messageText.count > 0, usersInThread.count > 0 {
			SeamailDataManager.shared.queueNewSeamailThreadOp(existingOp: threadToEdit, subject: subjectText, 
					message: messageText, recipients: usersInThread, makeOpen: openOrClosedCell.switchState, done: postQueued)
			isBusyPosting = true
			postStatusCell.shouldBeVisible = true
		}
	}
	
	func postQueued(_ post: PostOpSeamailThread?) {
    	if let post = post {
	    	postStatusCell.postOp = post
    	
    		// If we can connect to the server, wait until we succeed/fail the network call. Else, we 'succeed' as soon
    		// as we queue up the post. Either way, 2 sec timer, then dismiss the compose view.
 		   	post.tell(self, when: "operationState") { observer, observed in 
				if observed.operationState == .callSuccess || NetworkGovernor.shared.connectionState != .canConnect {
    				DispatchQueue.main.asyncAfter(deadline: .now() + DispatchTimeInterval.seconds(2)) {
						self.performSegue(withIdentifier: "dismissingPostingView", sender: nil)
    				}
    			}
    			else if observed.operationState == .serverError {
    				// If we get a server error, the user may have to modify the post so that it can work.
					observer.isBusyPosting = false
    			}
			}?.execute()
    	}
    	else {
			isBusyPosting = false
    	}

	}
	
// MARK: Navigation
	func globalNavigateTo(packet: GlobalNavPacket) -> Bool {
		if let userNames = packet.arguments["seamailThreadParticipants"] as? Set<String>, 
				let currentUsername = CurrentUser.shared.loggedInUser?.username {
			for userName in userNames {
				if userName != currentUsername {
					addUsernameToThread(username: userName)
				}
			}
		}
		return true
	}
	
}
