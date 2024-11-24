//
//  ComposePersonalEventVC.swift
//  Kraken
//
//  Created by Chall Fry on 10/24/24.
//  Copyright © 2024 Chall Fry. All rights reserved.
//

import UIKit
import CoreData

@objc class ComposePersonalEventVC: BaseCollectionViewController {

	// If editing an existing personal event
	var eventModel: SeamailThread?
	// If editing an event op
	var opToEdit: PostOpLFGCreate?
	
	let composeDataSource = KrakenDataSource()

	@objc dynamic var isBusyPosting = false
	@objc dynamic var makeGroupChat = false
	var defaultUserSuggestions = Set<PossibleKrakenUser>()
	var defaultUserSuggestionsPrompt = ""
	var usersInThread = Set<PossibleKrakenUser>()

// Basic info cells
	@objc dynamic lazy var titleCell: TextViewCellModel = TextViewCellModel("Title")
	@objc dynamic lazy var infoCell: TextViewCellModel = TextViewCellModel("Event Info")
	@objc dynamic lazy var locationCell: TextViewCellModel = TextViewCellModel("Location")

	lazy var defaultLocationsCell: PopupCellModel = {
		let menuItems = [
				"Atrium, Deck 1, Midship",
				"Rolling Stone Lounge, Deck 2, Midship",
				"Billboard Onboard, Deck 2, Forward",
				"Pinnacle Bar, Deck 2, Midship",
				"Explorer's Lounge, Deck 2, Aft",
				"Lower Main Dining Room, Deck 2, Aft",
				"Ocean Bar, Deck 3, Midship",
				"Upper Main Dining Room, Deck 3, Aft",
				"Lido Bar (Midship), Deck 9, Midship",
				"Sea View Bar, Deck 9, Midship",
				"Lido Pool Area, Deck 9, Midship",
				"Lido Market, Deck 9, Aft",
				"Sea View Pool Area, Deck 9, Aft",
				"High Score, Deck 10, Midship",
				"Hang 10, Deck 10, Forward",
				"Crow's Nest (Ten Forward), Deck 11, Forward",
				"Sports Deck, Deck 11, Aft",	
				"Sun Deck, Deck 12, Forward",	
				]
	 	let cellModel = PopupCellModel(title: "Common Locations:", menuPrompt: "Autofill Location Field With:", menuItems: menuItems,
	 			singleSelectionMode: false)
		cellModel.buttonTitle = "Select Location"
		return cellModel
	}()

// Time cells
	lazy var startDateCell: DatePickerCellModel = DatePickerCellModel(title: "Start Time:")
	lazy var eventDurationCell: PopupCellModel = {
		let menuItems = ["30 Min", "45 Min", "1 Hour", "1:30", "2 Hours", "3 Hours", "4 Hours"]
	 	return PopupCellModel(title: "Duration:", menuPrompt: "How long will your event last?", menuItems: menuItems)
	}()

// Participant cells
	@objc dynamic lazy var inviteOthersCell: SwitchCellModel = SwitchCellModel(labelText: "Invite Others To Event")
	var addUserExplanationCell: LabelCellModel = 
			LabelCellModel("Inviting other Twitarr users to your event makes the event show up on their calendars. It also creates a Seamail chat for all of you.",
						   fontTraits: .traitItalic, stringTraits: [.foregroundColor: UIColor(named: "Kraken Secondary Text") as Any])
	lazy var usernameTextCell: TextFieldCellModel = {
		let cell = TextFieldCellModel("Search for Invitees:")
		cell.showClearTextButton = true
		cell.returnButtonHit = textFieldReturnHit
		cell.purpose = .username
		cell.placeholderText = "Enter username"
		return cell
	}()
	lazy var userSuggestionsCell: UserListCoreDataCellModel = {
		let cell = UserListCoreDataCellModel(withTitle: "Invitee Suggestions")
		cell.selectionCallback = suggestedUserTappedAction
		return cell
	}()
	lazy var inviteesCell: UserListCoreDataCellModel = {
		let cell = UserListCoreDataCellModel(withTitle: "Invitees")
		cell.selectionCallback = userInThreadTappedAction
		cell.usePredicate = false
		cell.source = "(besides you)"
    	cell.users = usersInThread 
    	return cell		
	}()
	
// Posting cells
	lazy var postButtonCell: ButtonCellModel = {
		let buttonCell = ButtonCellModel()
		let title = eventModel != nil || opToEdit != nil ? "Update Event" : "Create Event"
		buttonCell.setupButton(2, title: title, action: weakify(self, type(of: self).postAction))
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


// MARK: - Methods
	override func viewDidLoad() {
        super.viewDidLoad()
        title = "Personal Event"

  		CurrentUser.shared.updateUserRelations(type: .favorite)

		composeDataSource.register(with: collectionView, viewController: self)
		let composeSection = composeDataSource.appendFilteringSegment(named: "ComposeSection")
		composeSection.append(titleCell)
		composeSection.append(infoCell)
		composeSection.append(locationCell)
		composeSection.append(defaultLocationsCell)
		composeSection.append(startDateCell)
		composeSection.append(eventDurationCell)
		composeSection.append(inviteOthersCell)
		composeSection.append(addUserExplanationCell)
		composeSection.append(usernameTextCell)
		composeSection.append(userSuggestionsCell)
		composeSection.append(inviteesCell)
		composeSection.append(postButtonCell)
		composeSection.append(postStatusCell)
				
        // If we are editing an existing Personal Event, fill in fields
		let userID = CurrentUser.shared.loggedInUser?.userID
		if let eventModel {
			titleCell.editText = eventModel.subject
			infoCell.editText = eventModel.info
			locationCell.editText = eventModel.location
			if let startTime = eventModel.startTime {
				startDateCell.selectedDate = startTime
				if let endTime = eventModel.endTime {
					switch endTime.timeIntervalSince(startTime) / 60 {
					case ...30: eventDurationCell.selectedMenuItem = 0
					case ...45: eventDurationCell.selectedMenuItem = 1
					case ...60: eventDurationCell.selectedMenuItem = 2
					case ...90: eventDurationCell.selectedMenuItem = 3
					case ...120: eventDurationCell.selectedMenuItem = 4
					case ...180: eventDurationCell.selectedMenuItem = 5
					case ...240: eventDurationCell.selectedMenuItem = 6
					default: eventDurationCell.selectedMenuItem = 7
					}
				}
			}
			inviteOthersCell.shouldBeVisible = false
			inviteOthersCell.switchState = eventModel.fezType == "privateEvent"
			let userSet: Set<PossibleKrakenUser> = .init(eventModel.attendees.compactMap({ 
				if let user = $0 as? KrakenUser {
					let result = PossibleKrakenUser(user: user)
					result.canBeRemoved = user.userID != userID
					return result
				}
				return nil
			}))
			inviteesCell.users = userSet
        }
        else if let eventOp = opToEdit {
        	// Same idea for post op
			titleCell.editText = eventOp.title
			infoCell.editText = eventOp.info
			locationCell.editText = eventOp.location
			startDateCell.selectedDate = eventOp.startTime
			switch eventOp.endTime.timeIntervalSince(eventOp.startTime) / 60 {
				case ...30: eventDurationCell.selectedMenuItem = 0
				case ...45: eventDurationCell.selectedMenuItem = 1
				case ...60: eventDurationCell.selectedMenuItem = 2
				case ...90: eventDurationCell.selectedMenuItem = 3
				case ...120: eventDurationCell.selectedMenuItem = 4
				case ...180: eventDurationCell.selectedMenuItem = 5
				case ...240: eventDurationCell.selectedMenuItem = 6
				default: eventDurationCell.selectedMenuItem = 7
			}
			inviteOthersCell.switchState = eventOp.lfgType == "privateEvent"
			var userSet: Set<PossibleKrakenUser> = []
			if let participants = eventOp.participants {
				userSet = .init(participants.map { 
					var result: PossibleKrakenUser
					if let user = $0.actualUser {
						result = .init(user: user)
						result.canBeRemoved = user.userID != userID
					}
					else {
						result = .init(username: $0.username)
						result.canBeRemoved = true
					}
					return result
				})
			}
			inviteesCell.users = userSet
        }

		// Show the user invite cells iff the invite toggle is on.
		inviteOthersCell.switchStateChanged = { [weak self] in
			self?.setPersonalPrivateState()
		}
		setPersonalPrivateState()

		//
		CurrentUser.shared.tell(self, when: "loggedInUser.favoriteUsers.*") { observer, observed in
			observer.buildUserSuggestions()
		}?.execute()

		// If multiple users are authed, show who we're posting as in the Post cell
		CurrentUser.shared.tell(postButtonCell, when: ["loggedInUser", "credentialedUsers"]) { observer, observed in
			if CurrentUser.shared.isMultiUser(), let currentUser = CurrentUser.shared.loggedInUser {
				let posterFont = UIFont(name:"Georgia-Italic", size: 14)
				let posterColor = UIColor.darkGray
				let textAttrs: [NSAttributedString.Key : Any] = [ .font : posterFont as Any, 
						.foregroundColor : posterColor ]
				observer.infoText = NSAttributedString(string: "Creating Event as: \(currentUser.username)", attributes: textAttrs)
			}
			else {
				observer.infoText = NSAttributedString?.none
			}
		}?.execute()
 		
 		// Selecting a location in the Default Locations popup cell fills in the text in the Location cell.
 		defaultLocationsCell.tell(locationCell, when: "selectedMenuItem") { observer, observed in
			observer.editedText = nil
			observer.editText = nil
			observer.editText = observed.selectedMenuTitle()
		}
		        
        // Let the userSuggestion cell know about changes made to the username text field
        usernameTextCell.tell(self, when: "editedText") { observer, observed in 
        	if let text = observed.getText(), !text.isEmpty {
        		observer.userSuggestionsCell.usePredicate = true
	        	observer.userSuggestionsCell.predicate = NSPredicate(format: "username CONTAINS[cd] %@", text)
	        	observer.userSuggestionsCell.source = "from partial string match"
	        	
	        	// Ask the server for name completions
	        	UserManager.shared.autocorrectUserLookup(for: text, done: self.userCompletionsCompletion)
			}
			else {
        		observer.userSuggestionsCell.usePredicate = false
	        	observer.userSuggestionsCell.users = observer.defaultUserSuggestions
	        	observer.userSuggestionsCell.source = observer.defaultUserSuggestionsPrompt
			}
        }?.execute()
        
        // Enable the Send button iff all the fields are filled in and we're not already sending.
        self.tell(self, when: ["titleCell.editedText", "infoCell.editedText",
        		"isBusyPosting"]) { observer, observed in
			if let titleText = observed.titleCell.getText(), !titleText.isEmpty,
					let infoText = observed.infoCell.getText(), !infoText.isEmpty,
					!observed.isBusyPosting {
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
	}
	
	func setPersonalPrivateState() {
		let showUserMgmtCells = eventModel == nil && inviteOthersCell.switchState
		addUserExplanationCell.shouldBeVisible = showUserMgmtCells
		usernameTextCell.shouldBeVisible = showUserMgmtCells
		userSuggestionsCell.shouldBeVisible = showUserMgmtCells
		inviteesCell.shouldBeVisible = showUserMgmtCells
		if eventModel != nil {
			self.title = "Update Event"
		}
		else {
			self.title = inviteOthersCell.switchState ? "Private Event" : "Personal Event"
		}
		UIView.animate(withDuration: 0.3) {
			self.collectionView.layoutIfNeeded()
		}
	}

    // Builds a list of users the logged in user has had recent Seamails with, for populating the Suggestions
    // cell when there's nothing better to put there.
    func buildUserSuggestions() {
		if let currentUser =  CurrentUser.shared.loggedInUser, !currentUser.favoriteUsers.isEmpty {
			defaultUserSuggestions = Set(currentUser.favoriteUsers.map { .init(user: $0) })
			defaultUserSuggestionsPrompt = "From your favorites"
			return
		}
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
		
		defaultUserSuggestions = Set(recentThreadParticipants.map { return PossibleKrakenUser(user: $0) })
		defaultUserSuggestionsPrompt = defaultUserSuggestions.isEmpty ? "" : "From recent Seamails"
    }
    
// MARK: - User Actions
	func textFieldReturnHit(_ textString: String) {
		addUsernameToEvent(username: textString)	
	}

	// When the server call completes we need to re-set the predicate. If we were using a fetchedResultsController,
    // we wouldn't need to do this (the FRC informs us of new results automatically)
    func userCompletionsCompletion(for: String?) {
    	let pred = userSuggestionsCell.predicate
		userSuggestionsCell.predicate = nil
    	userSuggestionsCell.predicate = pred
    }
    
	func suggestedUserTappedAction(user: PossibleKrakenUser) {
		if let krakenUser = user.user {
			addUserToEvent(user: krakenUser)
		}
		else {
			addUsernameToEvent(username: user.username)
		}
	}
	
	func userInThreadTappedAction(user: PossibleKrakenUser) {
		removeUserFromThread(user: user)
	}
	
	func addUserToEvent(user: KrakenUser) {
    	guard user.username != CurrentUser.shared.loggedInUser?.username else { return }
    	let possUser = PossibleKrakenUser(user: user)
    	possUser.canBeRemoved = true
    	usersInThread.insert(possUser)
    	inviteesCell.users = usersInThread  	
    }
    
    func addUsernameToEvent(username: String) {
    	guard username != CurrentUser.shared.loggedInUser?.username, !username.isEmpty else { return }
    	let possUser = PossibleKrakenUser(username: username)
    	possUser.canBeRemoved = true
    	usersInThread.insert(possUser)
    	inviteesCell.users = usersInThread  	
    }
    
    func removeUserFromThread(user: PossibleKrakenUser) {
 		usersInThread.remove(user)
		inviteesCell.users = usersInThread
    }


    func postAction() {
    	let startTime = startDateCell.selectedDate
		let locationText = locationCell.getText() ?? ""
		guard let titleText = titleCell.getText(), !titleText.isEmpty,
				let infoText = infoCell.getText(), !infoText.isEmpty else {
			postStatusCell.shouldBeVisible = true
			var errorString = ""
			if titleCell.getText() == nil || titleCell.getText()?.isEmpty == true { errorString.append("Event needs a title\n") }
			if infoCell.getText() == nil || infoCell.getText()?.isEmpty == true { errorString.append("Info field cannot be empty\n") }
			if locationCell.getText() == nil || locationCell.getText()?.isEmpty == true { errorString.append("Location field cannot be empty\n") }
			postStatusCell.setErrorState(errorString: errorString)
			return	
		}
		let lfgType: TwitarrV3FezType = inviteOthersCell.switchState ? .privateEvent : .personalEvent
		var duration: Int
		switch eventDurationCell.selectedMenuItem {
			case 0: duration = 30
			case 1: duration = 45
			case 2: duration = 60
			case 3: duration = 90
			case 4: duration = 120
			case 5: duration = 180
			case 6: duration = 240
			default: duration = 60
		}
		let endTime = Calendar(identifier: .gregorian).date(byAdding: .minute, value: duration, to: startTime) ?? startTime + TimeInterval(duration * 60)
		SeamailDataManager.shared.queueNewLFGOp(existingOp: self.opToEdit, existingLFG: self.eventModel, 
				lfgType: lfgType, title: titleText, info: infoText, location: locationText, startTime: startTime, endTime: endTime, 
				minCapacity: 0, maxCapacity: 0, participants: usersInThread, done: postQueued)
//		isBusyPosting = true
		postStatusCell.shouldBeVisible = true
	}
	
	func postQueued(_ post: PostOpLFGCreate?) {
    	if let post = post {
	    	postStatusCell.postOp = post
    	
    		// If we can connect to the server, wait until we succeed/fail the network call. Else, we 'succeed' as soon
    		// as we queue up the post. Either way, 2 sec timer, then dismiss the compose view.
 		   	post.tell(self, when: "operationState") { observer, observed in 
				if observed.operationState == .callSuccess || NetworkGovernor.shared.connectionState != .canConnect {
    				DispatchQueue.main.asyncAfter(deadline: .now() + DispatchTimeInterval.seconds(2)) {
						self.performSegue(withIdentifier: "dismissingCreateEvent", sender: nil)
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

}
