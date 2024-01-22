//
//  CreateLFGViewController.swift
//  Kraken
//
//  Created by Chall Fry on 2/1/23.
//  Copyright © 2023 Chall Fry. All rights reserved.
//

import Foundation

class CreateLFGViewController: BaseCollectionViewController {

	var lfgModel: SeamailThread?
	var opToEdit: PostOpLFGCreate?

	let dataManager = SeamailDataManager.shared
	let composeDataSource = KrakenDataSource()
	
	@objc dynamic var isBusyPosting = false

	@objc dynamic lazy var titleCell: TextViewCellModel = TextViewCellModel("Title")
	@objc dynamic lazy var locationCell: TextViewCellModel = TextViewCellModel("Location")
	@objc dynamic lazy var infoCell: TextViewCellModel = TextViewCellModel("Event Info")
	@objc dynamic lazy var attendeeCountsCell: AttendeeCountsCellModel = AttendeeCountsCellModel()
	
	lazy var defaultLocationsCell: PopupCellModel = {
		let menuItems = [
				"Atrium, Deck 1, Midship",
				"B.B. King's, Deck 2, Midship",
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
				"Crow's Nest (Ten Forward), Deck 10, Forward",
				"Shuffleboard Court, Deck 10, Midship",
				"EXC, Deck 10, Forward",
				"Sports Deck, Deck 11, Forward",	
				]
	 	let cellModel = PopupCellModel(title: "Common Locations:", menuPrompt: "Autofill Location Field With:", menuItems: menuItems,
	 			singleSelectionMode: false)
		cellModel.buttonTitle = "Select Location"
		return cellModel
	}()
	
	lazy var eventTypeCell: PopupCellModel = {
		let menuItems = ["Activity", "Dining", "Gaming", "Meetup", "Music", "Ashore", "Other"]
	 	return PopupCellModel(title: "Type of Event:", menuPrompt: "Choose event type", menuItems: menuItems)
	}()
	
	lazy var startDateCell: DatePickerCellModel = DatePickerCellModel(title: "Start Time:")

	lazy var eventDurationCell: PopupCellModel = {
		let menuItems = ["30 Min", "45 Min", "1 Hour", "1:30", "2 Hours", "3 Hours", "4 Hours"]
	 	return PopupCellModel(title: "Duration:", menuPrompt: "How long will your event last?", menuItems: menuItems)
	}()
	
	lazy var postButtonCell: ButtonCellModel = {
		let buttonCell = ButtonCellModel()
		var title = "Create"
		if lfgModel != nil {
			title = "Update"
		}
		else if opToEdit != nil {
			title = "Edit"
		}
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
        
        SeamailDataManager.shared.tell(cell, when: "lastError") { observer, observed in
        	observer.errorText = observed.lastError?.errorString
        }
        return cell
	}()
		
// MARK: - Methods
	override func viewDidLoad() {
        super.viewDidLoad()

		composeDataSource.register(with: collectionView, viewController: self)
		let composeSection = composeDataSource.appendFilteringSegment(named: "ComposeSection")
		composeSection.append(titleCell)
		composeSection.append(infoCell)
		composeSection.append(locationCell)
		composeSection.append(defaultLocationsCell)
		composeSection.append(eventTypeCell)
		composeSection.append(startDateCell)
		composeSection.append(eventDurationCell)
		composeSection.append(attendeeCountsCell)
		composeSection.append(postButtonCell)
		composeSection.append(postStatusCell)
		
		defaultLocationsCell.tell(locationCell, when: "selectedMenuItem") { observer, observed in
			observer.editText = observed.selectedMenuTitle()
		}
	}
	
	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
        title = "Create LFG"
		if let model = self.lfgModel {
			title = "Update LFG"
			// Populate UI with initial values from LFG
			titleCell.editText = model.subject
			infoCell.editText = model.info
			locationCell.editText = model.location
			switch TwitarrV3FezType(rawValue: model.fezType) {
				case .activity: eventTypeCell.selectedMenuItem = 0
				case .dining: eventTypeCell.selectedMenuItem = 1
				case .gaming: eventTypeCell.selectedMenuItem = 2
				case .meetup: eventTypeCell.selectedMenuItem = 3
				case .music: eventTypeCell.selectedMenuItem = 4
				case .shore: eventTypeCell.selectedMenuItem = 5
				case .other: eventTypeCell.selectedMenuItem = 6
				default: eventTypeCell.selectedMenuItem = 0
			}
			if let startTime = model.startTime {
				startDateCell.selectedDate = startTime
				let duration = (model.endTime?.timeIntervalSince(startTime) ?? 1800) / 60
				switch duration {
					case ..<40: eventDurationCell.selectedMenuItem = 0
					case 40..<55: eventDurationCell.selectedMenuItem = 1
					case 55..<75: eventDurationCell.selectedMenuItem = 2
					case 75..<105: eventDurationCell.selectedMenuItem = 3
					case 105..<165: eventDurationCell.selectedMenuItem = 4
					case 165..<225: eventDurationCell.selectedMenuItem = 5
					case 225...: eventDurationCell.selectedMenuItem = 6
					default: eventDurationCell.selectedMenuItem = 0
				}
			}
			attendeeCountsCell.minAttendees = model.minParticipants
			attendeeCountsCell.maxAttendees = model.maxParticipants
		}
		else if let op = self.opToEdit {
			title = "Edit LFG"
			
			op.setOperationState(.notReadyToSend)
			titleCell.editText = op.title
			infoCell.editText = op.info
			locationCell.editText = op.location
			switch TwitarrV3FezType(rawValue: op.lfgType) {
				case .activity: eventTypeCell.selectedMenuItem = 0
				case .dining: eventTypeCell.selectedMenuItem = 1
				case .gaming: eventTypeCell.selectedMenuItem = 2
				case .meetup: eventTypeCell.selectedMenuItem = 3
				case .music: eventTypeCell.selectedMenuItem = 4
				case .shore: eventTypeCell.selectedMenuItem = 5
				case .other: eventTypeCell.selectedMenuItem = 6
				default: eventTypeCell.selectedMenuItem = 0
			}
			startDateCell.selectedDate = op.startTime
			let duration = op.endTime.timeIntervalSince(op.startTime) / 60.0
			switch duration {
				case ..<40: eventDurationCell.selectedMenuItem = 0
				case 40..<55: eventDurationCell.selectedMenuItem = 1
				case 55..<75: eventDurationCell.selectedMenuItem = 2
				case 75..<105: eventDurationCell.selectedMenuItem = 3
				case 105..<165: eventDurationCell.selectedMenuItem = 4
				case 165..<225: eventDurationCell.selectedMenuItem = 5
				case 225...: eventDurationCell.selectedMenuItem = 6
				default: eventDurationCell.selectedMenuItem = 0
			}
			attendeeCountsCell.minAttendees = op.minCapacity
			attendeeCountsCell.maxAttendees = op.maxCapacity
		}
	}
	
	override func viewDidDisappear(_ animated: Bool) {
		super.viewDidDisappear(animated)
		if let op = self.opToEdit {
			// Whether we committed edits to the op or not, mark the op ready to send again.
			op.setOperationState(.readyToSend)
		}
	}
	
// MARK: Actions

    func postAction() {
    	let startTime = startDateCell.selectedDate
		guard let titleText = titleCell.getText(), !titleText.isEmpty,
				let infoText = infoCell.getText(), !infoText.isEmpty,
				let locationText = locationCell.getText(), !locationText.isEmpty,
				startTime > cruiseCurrentDate() else {
			postStatusCell.shouldBeVisible = true
			var errorString = ""
			if titleCell.getText() == nil || titleCell.getText()?.isEmpty == true { errorString.append("LFG needs a title\n") }
			if infoCell.getText() == nil || infoCell.getText()?.isEmpty == true { errorString.append("Info field cannot be empty\n") }
			if locationCell.getText() == nil || locationCell.getText()?.isEmpty == true { errorString.append("Location field cannot be empty\n") }
			if startTime <= cruiseCurrentDate() { errorString.append("LFG cannot start in the past\n") }
			postStatusCell.setErrorState(errorString: errorString)
			return	
		}
		var lfgType: TwitarrV3FezType
		switch eventTypeCell.selectedMenuTitle() {
			case "Activity": lfgType = .activity
			case "Dining": lfgType = .dining
			case "Gaming": lfgType = .gaming 
			case "Meetup": lfgType = .meetup 
			case "Music": lfgType = .music 
			case "Ashore": lfgType = .shore 
			case "Other": lfgType = .other
			
			// Open, Closed should not happen
			default: lfgType = .other
		}
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
		let endTime = Calendar(identifier: .gregorian).date(byAdding: .minute, value: duration, to: startTime) ?? startTime
		let minAttendees = attendeeCountsCell.minAttendees
		let maxAttendees = attendeeCountsCell.maxAttendees
		SeamailDataManager.shared.queueNewLFGOp(existingOp: self.opToEdit, existingLFG: self.lfgModel, 
				lfgType: lfgType, title: titleText, info: infoText, location: locationText, startTime: startTime, endTime: endTime, 
				minCapacity: minAttendees, maxCapacity: maxAttendees, done: postQueued)
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
}
