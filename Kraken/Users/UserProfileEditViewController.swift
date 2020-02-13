//
//  UserProfileEditViewController.swift
//  Kraken
//
//  Created by Chall Fry on 9/25/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit
import Photos

@objc class UserProfileEditViewController: BaseCollectionViewController {
	var modelKrakenUser: LoggedInKrakenUser?
	@objc dynamic var editProfileOp: PostOpUserProfileEdit?
	@objc dynamic var editPhotoOp: PostOpUserPhoto?
	
	let dataSource = KrakenDataSource()
	var avatarCell: ProfileAvatarEditCellModel?
	var avatarUpdateStatusCell = PostOpStatusCellModel()
	var displayNameCell: TextFieldCellModel = {
		let cell = TextFieldCellModel("Display Name", purpose: .normal)
		CurrentUser.shared.tell(cell, when: "lastError.fieldErrors.display_name") { observer, observed in 
			if let errors = (observed.lastError as? ServerError)?.fieldErrors?["display_name"] {
				observer.errorText = errors[0]
			}
			else {
				observer.errorText = nil
			}
		}		
		return cell
	}()
	var realNameCell = TextFieldCellModel("Real Name", purpose: .normal)
	var pronounsCell = TextFieldCellModel("Preferred Pronouns")
	var emailCell: TextFieldCellModel = {
		let cell = TextFieldCellModel("Email", purpose: .email)
		CurrentUser.shared.tell(cell, when: "lastError.fieldErrors.email") { observer, observed in 
			if let errors = (observed.lastError as? ServerError)?.fieldErrors?["email"] {
				observer.errorText = errors[0]
			}
			else {
				observer.errorText = nil
			}
		}		
		return cell
	}()
	var homeLocationCell = TextFieldCellModel("Where are you from?", purpose: .normal)
	var roomNumberCell: TextFieldCellModel = {
		let cell  = TextFieldCellModel("Room Number", purpose: .roomNumber)
		CurrentUser.shared.tell(cell, when: "lastError.fieldErrors.room_number") { observer, observed in 
			if let errors = (observed.lastError as? ServerError)?.fieldErrors?["room_number"] {
				observer.errorText = errors[0]
			}
			else {
				observer.errorText = nil
			}
		}		
		return cell
	}()
	var profileUpdateStatusCell = PostOpStatusCellModel()
	
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
			observer.performKrakenSegue(.dismiss, sender: self)
		}
		
    	let section = dataSource.appendFilteringSegment(named: "UserProfile")
    	avatarCell = ProfileAvatarEditCellModel(user: modelKrakenUser)
    	let descriptionCell = LabelCellModel("All the fields below are optional. Anything you put in them can be seen by everyone.")
    		
		self.tell(self, when: "editProfileOp.displayName") { observer, observed in 
			observer.displayNameCell.fieldText = observed.editProfileOp?.displayName ?? observer.modelKrakenUser?.displayName
		}?.execute()
		self.tell(self, when: "editProfileOp.realNameCell") { observer, observed in 
			observer.realNameCell.fieldText = observed.editProfileOp?.realName ?? observer.modelKrakenUser?.realName
		}?.execute()
		self.tell(self, when: "editProfileOp.pronouns") { observer, observed in 
			observer.pronounsCell.fieldText = observed.editProfileOp?.pronouns ?? observer.modelKrakenUser?.pronouns
		}?.execute()
		self.tell(self, when: "editProfileOp.email") { observer, observed in 
			observer.emailCell.fieldText = observed.editProfileOp?.email ?? observer.modelKrakenUser?.emailAddress
		}?.execute()
		self.tell(self, when: "editProfileOp.displayName") { observer, observed in 
			observer.homeLocationCell.fieldText = observed.editProfileOp?.homeLocation ?? observer.modelKrakenUser?.homeLocation
		}?.execute()
		self.tell(self, when: "editProfileOp.displayName") { observer, observed in 
			observer.roomNumberCell.fieldText = observed.editProfileOp?.roomNumber ?? observer.modelKrakenUser?.roomNumber
		}?.execute()

		let saveButtonCell = ButtonCellModel(title: "Save", action: { 
			CurrentUser.shared.changeUserProfileFields(displayName: self.displayNameCell.getText(),
					realName: self.realNameCell.getText(), pronouns: self.pronounsCell.getText(), 
					email: self.emailCell.getText(), homeLocation: self.homeLocationCell.getText(), 
					roomNumber: self.roomNumberCell.getText())
		})
		
		// Debug
//		avatarUpdateStatusCell?.debugLogEnabler = "avatarUpdateStatusCell"

		section.append(avatarCell!)
		section.append(avatarUpdateStatusCell)
		section.append(descriptionCell)
		section.append(displayNameCell)
		section.append(realNameCell)
		section.append(pronounsCell)
		section.append(emailCell)
		section.append(homeLocationCell)
		section.append(roomNumberCell)
		section.append(saveButtonCell)
		section.append(profileUpdateStatusCell)
		

		// This makes the editProfileOp property always match any profile operation in progress.
		modelKrakenUser?.tell(self, when: "postOps") { observer, observed in
			observer.editProfileOp = observed.getPendingProfileEditOp()
			observer.editPhotoOp = observed.getPendingPhotoEditOp()
			observer.avatarUpdateStatusCell.postOp = observer.editPhotoOp
			observer.profileUpdateStatusCell.postOp = observer.editProfileOp
		}?.execute()

		knownSegues = Set([.fullScreenCamera, .cropCamera, .dismiss])
	}
 
    override func viewDidAppear(_ animated: Bool) {
    	super.viewDidAppear(animated)
		dataSource.enableAnimations = true
		CurrentUser.shared.clearErrors()
	}
	
	override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
		if let segueID = prepareGlobalSegue(for: segue, sender: sender) {
			
			// Override default camera behavior when we're the source, so the camera starts in selfie mode.
			switch segueID {
			case .fullScreenCamera, .cropCamera: 
				if let destVC = segue.destination as? CameraViewController {
					destVC.selfieMode = true
				}
			default: break 
			}
		}
	}
	
	// This is the handler for the CameraViewController's unwind segue. Pull the captured photo out of the
	// source VC to get the photo that was taken.
	@IBAction func dismissingCamera(_ segue: UIStoryboardSegue) {
		guard let sourceVC = segue.source as? CameraViewController else { return }
		if let photoContainer = sourceVC.capturedPhoto {
			prepareImageForUpload(photoContainer: photoContainer)
		}
	}	
	
    func imageiCloudDownloadProgress(_ progress: Double?, _ error: Error?, _ stopPtr: UnsafeMutablePointer<ObjCBool>, 
    		_ info: [AnyHashable : Any]?) {
		if let error = error {
			self.avatarUpdateStatusCell.errorText = error.localizedDescription
		}
		else if let resultInCloud = info?[PHImageResultIsInCloudKey] as? NSNumber, resultInCloud.boolValue == true {
			self.avatarUpdateStatusCell.statusText = "Downloading full-sized photo from iCloud"
		}
	}
	
	func prepareImageForUpload(photoContainer: PhotoDataType) {
		ImageManager.shared.resizeImageForUpload(imageContainer: photoContainer, 
				progress: imageiCloudDownloadProgress) { jpegData, mimeType, error in 
			if let err = error {
				self.avatarUpdateStatusCell.errorText = err.getErrorString()
			}
			else if let data = jpegData, let user = self.modelKrakenUser {
				user.setUserProfilePhoto(photoData: data, mimeType: mimeType ?? "image/jpeg")
			}
		}
	}
}

