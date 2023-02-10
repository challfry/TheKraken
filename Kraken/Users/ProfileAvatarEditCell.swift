//
//  ProfileAvatarEditCell.swift
//  Kraken
//
//  Created by Chall Fry on 10/25/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit
import MobileCoreServices
import UniformTypeIdentifiers

@objc protocol ProfileAvatarEditCellProtocol {
	var userModel: KrakenUser? { get set }
}

@objc class ProfileAvatarEditCellModel: BaseCellModel, ProfileAvatarEditCellProtocol {
	private static let validReuseIDs = [ "ProfileAvatarEditCell" : ProfileAvatarEditCell.self ]
	override class var validReuseIDDict: [String: BaseCollectionViewCell.Type ] { return validReuseIDs }

	var userModel: KrakenUser?
	
	init(user: KrakenUser?) {
		super.init(bindingWith: ProfileAvatarEditCellProtocol.self)
		userModel = user
	}
}

@objc class ProfileAvatarEditCell: BaseCollectionViewCell, ProfileAvatarEditCellProtocol {
	@IBOutlet weak var avatarImageView: UIImageView!
	@IBOutlet weak var usernameLabel: UILabel!
	
	// I'd like to enable/disable this button as appropriate, but we don't seem to have a way of knowing
	// when the user avatar is already the identicon (that is, no custom avatar is set).
	@IBOutlet weak var deleteCustomAvatarButton: UIButton!
	
	private static let cellInfo = [ "ProfileAvatarEditCell" : PrototypeCellInfo("ProfileAvatarEditCell") ]
	override class var validReuseIDDict: [ String: PrototypeCellInfo ] { return cellInfo }

	var userModel: KrakenUser? {
		didSet {
			clearObservations()
			if let userModel = self.userModel {
				userModel.tell(self, when: "displayName") { observer, observed in
					if observed.displayName == observed.username {
						observer.usernameLabel.text = String("@\(observed.displayName)")
					}
					else {
						observer.usernameLabel.text = String("\(observed.displayName) \n(@\(observed.username))")
					}
				}?.execute()

				userModel.tell(self, when: [ "userImageName" ]) { observer, observed in
					observed.loadUserFullPhoto()
				}?.execute()
				userModel.tell(self, when: [ "fullPhoto", "thumbPhoto" ]) { observer, observed in
					if let fullPhoto = observed.fullPhoto {
						observer.avatarImageView.image = fullPhoto
					}
					else if let thumbPhoto = observed.thumbPhoto {
						observer.avatarImageView.image = thumbPhoto
					}
				}?.execute()
			}
			else {
				usernameLabel.text = ""
				avatarImageView.image = nil
			}
		}
	}
	
	override func awakeFromNib() {
		// Set up gesture recognizer to detect taps on the (single) photo, and open the fullscreen photo overlay.
		let photoTap = UITapGestureRecognizer(target: self, action: #selector(ProfileAvatarEditCell.photoTapped(_:)))
	 	avatarImageView.addGestureRecognizer(photoTap)
	}
	
	@objc func photoTapped(_ sender: UITapGestureRecognizer) {
		if let vc = viewController as? BaseCollectionViewController, let image = avatarImageView.image {
			vc.showImageInOverlay(image: image)
		}
	}

	@IBAction func cameraButtonTapped(_ sender: Any) {
		if Settings.shared.useFullscreenCameraViewfinder {
			self.dataSource?.performKrakenSegue(.fullScreenCamera, sender: self)
		}
		else {
			self.dataSource?.performKrakenSegue(.cropCamera, sender: self)
		}
	}
	
	@IBAction func findPhotoInLibraryButtonTapped(_ sender: Any) {
		if UIImagePickerController.isSourceTypeAvailable(.savedPhotosAlbum) {
			let picker = UIImagePickerController()
			picker.delegate = self
			picker.allowsEditing = true
			picker.mediaTypes = [UTType.image.identifier]
			viewController?.present(picker, animated: true)
		}
	}	
	
	@IBAction func deleteAvatarButtonTapped(_ sender: Any) {
   		let alert = UIAlertController(title: "Delete Avatar Image", 
   				message: "If you have a custom image, this will remove it and go back to a default identicon.", 
   				preferredStyle: .alert) 
		alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: "Cancel action"), 
				style: .cancel, handler: nil))
		alert.addAction(UIAlertAction(title: NSLocalizedString("Delete", comment: "Default action"), 
				style: .destructive, handler: confirmDeleteAvatarImage))
		
		viewController?.present(alert, animated: true, completion: nil)
	}
	
	func confirmDeleteAvatarImage(_ action: UIAlertAction) {
		if let user = userModel as? LoggedInKrakenUser {
			user.setUserProfilePhoto(photoData: nil, mimeType: "")
		}
	}
}

extension ProfileAvatarEditCell: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
	
	func imagePickerController(_ picker: UIImagePickerController, 
				didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
		if let pickedImage = info[.editedImage] as? UIImage ?? info[.originalImage] as? UIImage,
				let vc = viewController as? UserProfileEditViewController {
			let photoContainer = PhotoDataType.image(pickedImage)
			vc.prepareImageForUpload(photoContainer: photoContainer)
		}
		
		viewController?.dismiss(animated: true, completion: nil)
	}

	func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
		viewController?.dismiss(animated: true, completion: nil)
	}

}
