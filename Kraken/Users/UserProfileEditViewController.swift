//
//  UserProfileEditViewController.swift
//  Kraken
//
//  Created by Chall Fry on 9/25/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit

@objc class UserProfileEditViewController: BaseCollectionViewController {
	var modelKrakenUser: LoggedInKrakenUser?
	@objc dynamic var editProfileOp: PostOpUserProfileEdit?
	
	let dataSource = KrakenDataSource()
	var avatarCell: ProfileAvatarCellModel?
	var displayNameCell: TextFieldCellModel?
	var realNameCell: TextFieldCellModel?
	var pronounsCell: TextFieldCellModel?
	var emailCell: TextFieldCellModel?
	var homeLocationCell: TextFieldCellModel?
	var roomNumberCell: TextFieldCellModel?
	
// MARK: Methods

    override func viewDidLoad() {
        super.viewDidLoad()
        title = String("Edit Profile")
        dataSource.collectionView = collectionView
		dataSource.register(with: collectionView, viewController: self)
		
		// Set the user once at load time; any login status changes cause the view to close.
		// This prevents editing this screen while logged out, and also logging in as someone else and having any
		// text entered in the fields apply to the new user.
		modelKrakenUser = CurrentUser.shared.loggedInUser
		CurrentUser.shared.tell(self, when: "loggedInUser") { observer, observed in
			self.performSegue(withIdentifier: "dismiss", sender: self)
		}
		
		modelKrakenUser?.tell(self, when: "postOps") { observer, observed in
			observer.editProfileOp = observed.getPendingProfileEditOp()
		}?.execute()

    	let section = dataSource.appendFilteringSegment(named: "UserProfile")
    	avatarCell = ProfileAvatarCellModel(user: modelKrakenUser)
    	let descriptionCell = LabelCellModel("All the fields below are optional. Anything you put in them can be seen by everyone.")
    	
		displayNameCell = TextFieldCellModel("Display Name")
		realNameCell = TextFieldCellModel("Real Name")
		pronounsCell = TextFieldCellModel("Preferred Pronouns")
		emailCell = TextFieldCellModel("Email")
		homeLocationCell = TextFieldCellModel("Where are you from?")
		roomNumberCell = TextFieldCellModel("Room Number")
	
		self.tell(self, when: "editProfileOp.displayName") { observer, observed in 
			observer.displayNameCell?.fieldText = observed.editProfileOp?.displayName ?? observer.modelKrakenUser?.displayName
		}?.execute()
		self.tell(self, when: "editProfileOp.realNameCell") { observer, observed in 
			observer.realNameCell?.fieldText = observed.editProfileOp?.realName ?? observer.modelKrakenUser?.realName
		}?.execute()
		self.tell(self, when: "editProfileOp.pronouns") { observer, observed in 
			observer.pronounsCell?.fieldText = observed.editProfileOp?.pronouns ?? observer.modelKrakenUser?.pronouns
		}?.execute()
		self.tell(self, when: "editProfileOp.email") { observer, observed in 
			observer.emailCell?.fieldText = observed.editProfileOp?.email ?? observer.modelKrakenUser?.emailAddress
		}?.execute()
		self.tell(self, when: "editProfileOp.displayName") { observer, observed in 
			observer.homeLocationCell?.fieldText = observed.editProfileOp?.homeLocation ?? observer.modelKrakenUser?.homeLocation
		}?.execute()
		self.tell(self, when: "editProfileOp.displayName") { observer, observed in 
			observer.roomNumberCell?.fieldText = observed.editProfileOp?.roomNumber ?? observer.modelKrakenUser?.roomNumber
		}?.execute()

		let saveButtonCell = ButtonCellModel(title: "Save", action: { 
			CurrentUser.shared.changeUserProfileFields(displayName: self.displayNameCell?.getText(),
					realName: self.realNameCell?.getText(), pronouns: self.pronounsCell?.getText(), 
					email: self.emailCell?.getText(), homeLocation: self.homeLocationCell?.getText(), 
					roomNumber: self.roomNumberCell?.getText())
		})

		section.append(avatarCell!)
		section.append(descriptionCell)
		section.append(displayNameCell!)
		section.append(realNameCell!)
		section.append(pronounsCell!)
		section.append(emailCell!)
		section.append(homeLocationCell!)
		section.append(roomNumberCell!)
		section.append(saveButtonCell)
	}
 
    override func viewDidAppear(_ animated: Bool) {
		dataSource.enableAnimations = true
	}
	
}
