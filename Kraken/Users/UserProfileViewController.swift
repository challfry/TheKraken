//
//  UserProfileViewController.swift
//  Kraken
//
//  Created by Chall Fry on 4/13/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit
import CoreData


@objc class UserProfileViewController: BaseCollectionViewController {
	let dataSource = KrakenDataSource()
	
	var modelUserName : String?
	@objc dynamic var modelKrakenUser: KrakenUser?
	@objc dynamic var pendingFavoriteOp: PostOpUserRelation?
	@objc dynamic var pendingMuteOp: PostOpUserRelation?
	@objc dynamic var pendingBlockOp: PostOpUserRelation?

    override func viewDidLoad() {
        super.viewDidLoad()
        dataSource.collectionView = collectionView
        self.title = String("User: \(modelUserName ?? "")")

		collectionView.refreshControl = UIRefreshControl()
		collectionView.refreshControl?.addTarget(self, action: #selector(self.self.startRefresh), for: .valueChanged)
		setupCellModels()
		dataSource.register(with: collectionView, viewController: self)
	}
	
	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		if modelKrakenUser == nil, let userName = modelUserName {
	        modelKrakenUser = UserManager.shared.loadUserProfile(userName) { resultUser in
				if self.modelKrakenUser != resultUser {
					self.modelKrakenUser = resultUser
					self.updateCellModels(to: resultUser)
				}
			}
		}
		else if let krakenUser = modelKrakenUser {
			modelUserName = krakenUser.username
	        UserManager.shared.loadUserProfile(krakenUser) { resultUser in
				if self.modelKrakenUser != resultUser {
					self.modelKrakenUser = resultUser
					self.updateCellModels(to: resultUser)
				}
			}
		}
    }
    
    override func viewDidAppear(_ animated: Bool) {
    	super.viewDidAppear(animated)
		dataSource.enableAnimations = true
	}
    
    var lastRefreshTime: Date = Date()
	@objc func startRefresh() {
		guard Date().timeIntervalSince(lastRefreshTime) > 15.0 else { 
			collectionView.refreshControl?.endRefreshing()
			return 
		}
		
		if let userName = modelUserName {
	        modelKrakenUser = UserManager.shared.loadUserProfile(userName) { resultUser in
				if self.modelKrakenUser != resultUser {
					self.modelKrakenUser = resultUser
					self.updateCellModels(to: resultUser)
					self.collectionView.refreshControl?.endRefreshing()
				}
	        }
		}
    }
    
// MARK: Cell Models
	var avatarCell: ProfileAvatarCellModel?
	var welcomeMessageCell: LabelCellModel?
	var pronounCell: UserProfileSingleValueCellModel?
	var emailCell: UserProfileSingleValueCellModel?
    var homeLocationCell: UserProfileSingleValueCellModel?
    var roomNumberCell: UserProfileSingleValueCellModel?
    var mapRoomCell: ButtonCellModel?
    var currentLocationCell: UserProfileSingleValueCellModel?
    var dinnerTeamCell: UserProfileSingleValueCellModel?
	var aboutMessageCell: UserProfileSingleValueCellModel?
//	var authoredTweetsCell: ProfileDisclosureCellModel?
//	var mentionsCell: ProfileDisclosureCellModel?
    var sendSeamailCell: ProfileDisclosureCellModel?
    var editProfileCell: ProfileDisclosureCellModel?
    var profileCommentCell: ProfileCommentCellModel?
    
    // TODO: Add Change Password cell
    
    lazy var favoriteUserCell: ButtonCellModel = {
		let cell = ButtonCellModel(alignment: .left)
		cell.button1Action = { [weak self] in
			if let self = self, let currentUser = CurrentUser.shared.loggedInUser, let targetUser = self.modelKrakenUser {
				let currentFavorite = currentUser.favoriteUsers.contains(targetUser)
				CurrentUser.shared.setRelation(type: .favorite, forUser: targetUser, to: !currentFavorite)
			}
		}
		cell.button1Enabled = true
		
		CurrentUser.shared.tell(self, when: "loggedInUser") { observer, observed in 
			cell.shouldBeVisible = observed.isLoggedIn() && observed.loggedInUser?.userID != observer.modelKrakenUser?.userID
		}?.execute()
		
		CurrentUser.shared.tell(self, when: "loggedInUser.favoriteUsers") { observer, observed in 
			if let currentUser = CurrentUser.shared.loggedInUser, let targetUser = observer.modelKrakenUser {
				cell.button1Text = currentUser.favoriteUsers.contains(targetUser) ? "Remove Favorite" : "Add Favorite"
			}
		}?.execute()

		CurrentUser.shared.tell(self, when: "loggedInUser.postOps") { observer, observed in 
			if let currentUser = CurrentUser.shared.loggedInUser, let targetUser = observer.modelKrakenUser {
				observer.pendingFavoriteOp = currentUser.getPendingUserRelationOp(type: .favorite, forUser: targetUser,
						inContext: LocalCoreData.shared.mainThreadContext)
				if let op = observer.pendingFavoriteOp {
					cell.button2Enabled = true
					cell.button2Text = "Cancel"
					cell.button2Action = { 		
						PostOperationDataManager.shared.remove(op: op)
						observer.pendingFavoriteOp = nil
					}
				}
				else {
					cell.button2Enabled = false
					cell.button2Text = nil
				}
			}
		}?.execute()

		self.tell(cell, when: "pendingFavoriteOp.errorString") { observer, observed in
			if let op = observed.pendingFavoriteOp {
				observer.errorText = op.operationState != .callSuccess ? op.errorString : nil
			}
			else {
				observer.errorText = nil
			}
		}?.execute()

		return cell
    }()

    lazy var muteUserCell: ButtonCellModel = {
		let cell = ButtonCellModel(alignment: .left)
		cell.button1Action = showMuteUserAlert
		cell.button1Enabled = true
		
		CurrentUser.shared.tell(self, when: "loggedInUser") { observer, observed in 
			cell.shouldBeVisible = observed.loggedInUser?.username != observer.modelUserName
		}?.execute()
		
		CurrentUser.shared.tell(self, when: "loggedInUser.mutedUsers") { observer, observed in 
			if let currentUser = CurrentUser.shared.loggedInUser, let targetUser = observer.modelKrakenUser {
				cell.button1Text = currentUser.mutedUsers.contains(targetUser) ? "Unmute User" : "Mute User"
			}
		}?.execute()

		CurrentUser.shared.tell(self, when: "loggedInUser.postOps") { observer, observed in 
			if let currentUser = CurrentUser.shared.loggedInUser, let targetUser = observer.modelKrakenUser {
				observer.pendingMuteOp = currentUser.getPendingUserRelationOp(type: .mute, forUser: targetUser,
						inContext: LocalCoreData.shared.mainThreadContext)
				if let op = observer.pendingMuteOp {
					cell.button2Enabled = true
					cell.button2Text = "Cancel"
					cell.button2Action = { 		
						PostOperationDataManager.shared.remove(op: op)
						observer.pendingMuteOp = nil
					}
				}
				else {
					cell.button2Enabled = false
					cell.button2Text = nil
				}
			}
		}?.execute()

		self.tell(cell, when: "pendingMuteOp.errorString") { observer, observed in 
			if let op = observed.pendingMuteOp {
				observer.errorText = op.operationState != .callSuccess ? op.errorString : nil
			}
			else {
				observer.errorText = nil
			}
		}?.execute()

		return cell
    }()
    
    lazy var blockUserCell: ButtonCellModel = {
		let cell = ButtonCellModel(alignment: .left)
		cell.button1Action = showBlockUserAlert
		cell.button1Enabled = true
		
		CurrentUser.shared.tell(self, when: "loggedInUser") { observer, observed in 
			cell.shouldBeVisible = observed.loggedInUser?.username != observer.modelUserName
		}?.execute()
				
		CurrentUser.shared.tell(self, when: "loggedInUser.blockedUsers") { observer, observed in 
			if let currentUser = CurrentUser.shared.loggedInUser, let targetUser = observer.modelKrakenUser {
				cell.button1Text = currentUser.blockedUsers.contains(targetUser) ? "Unblock User" : "Block User"
			}
		}?.execute()
		
		CurrentUser.shared.tell(self, when: "loggedInUser.postOps") { observer, observed in 
			if let currentUser = CurrentUser.shared.loggedInUser, let targetUser = observer.modelKrakenUser {
				observer.pendingBlockOp = currentUser.getPendingUserRelationOp(type: .block, forUser: targetUser,
						inContext: LocalCoreData.shared.mainThreadContext)
				if let op = observer.pendingBlockOp {
					cell.button2Enabled = true
					cell.button2Text = "Cancel"
					cell.button2Action = { 		
						PostOperationDataManager.shared.remove(op: op)
						observer.pendingBlockOp = nil
					}
				}
				else {
					cell.button2Enabled = false
					cell.button2Text = nil
				}
			}
		}?.execute()
		
		self.tell(cell, when: "pendingBlockOp.errorString") { observer, observed in 
			if let op = observed.pendingBlockOp {
				observer.errorText = op.operationState != .callSuccess ? op.errorString : nil
			}
			else {
				observer.errorText = nil
			}
		}?.execute()

		return cell
    }()
    
    func setupCellModels() {

    	let section = dataSource.appendFilteringSegment(named: "UserProfile")
    	avatarCell = ProfileAvatarCellModel(user: modelKrakenUser)
    	welcomeMessageCell = LabelCellModel(modelKrakenUser?.profileMessage ?? "")
		pronounCell = UserProfileSingleValueCellModel(user: modelKrakenUser, mode: .pronouns)
		emailCell = UserProfileSingleValueCellModel(user: modelKrakenUser, mode: .email)
		homeLocationCell = UserProfileSingleValueCellModel(user: modelKrakenUser, mode: .homeLocation)
		roomNumberCell = UserProfileSingleValueCellModel(user: modelKrakenUser, mode: .roomNumber)
		mapRoomCell = ButtonCellModel(title: "Show Room On Map", alignment: .center, action: mapButtonTapped)
		currentLocationCell = UserProfileSingleValueCellModel(user: modelKrakenUser, mode: .currentLocation)
		dinnerTeamCell = UserProfileSingleValueCellModel(user: modelKrakenUser, mode: .dinnerTeam)
		aboutMessageCell = UserProfileSingleValueCellModel(user: modelKrakenUser, mode: .aboutMessage)

//		authoredTweetsCell = ProfileDisclosureCellModel(user: modelKrakenUser, mode:.authoredTweets, vc: self)
		sendSeamailCell = ProfileDisclosureCellModel(user: modelKrakenUser, mode:.sendSeamail, vc: self)		
		editProfileCell = ProfileDisclosureCellModel(user: modelKrakenUser, mode:.editOwnProfile, vc: self)		
		profileCommentCell = ProfileCommentCellModel(user: modelKrakenUser)
		
		self.tell(mapRoomCell!, when: "modelKrakenUser.roomNumber") { observer, observed in
			if let room = observed.modelKrakenUser?.roomNumber {
				observer.shouldBeVisible = DeckDataManager.shared.isValidRoom(name: room)
			} else {
				observer.shouldBeVisible = false
			}
		}?.execute()

    	section.append(avatarCell!)
		section.append(welcomeMessageCell!)
		section.append(pronounCell!)
		section.append(emailCell!)
		section.append(homeLocationCell!)
		section.append(roomNumberCell!)
		section.append(mapRoomCell!)
		section.append(currentLocationCell!)
		section.append(dinnerTeamCell!)
		section.append(aboutMessageCell!)
//		section.append(authoredTweetsCell!)
		section.append(sendSeamailCell!)		
		section.append(editProfileCell!)		
		section.append(profileCommentCell!)
		section.append(favoriteUserCell)
		section.append(muteUserCell)
		section.append(blockUserCell)
    }
    
    func updateCellModels(to newUser: KrakenUser?) {
		self.modelKrakenUser = newUser
    	avatarCell?.model = newUser
    	welcomeMessageCell?.labelText = NSAttributedString(string: newUser?.profileMessage ?? "")
    	pronounCell?.userModel = newUser
    	emailCell?.userModel = newUser
		homeLocationCell?.userModel = newUser
		roomNumberCell?.userModel = newUser
		currentLocationCell?.userModel = newUser
		dinnerTeamCell?.userModel = newUser
    	aboutMessageCell?.userModel = newUser
//		authoredTweetsCell?.userModel = newUser
		sendSeamailCell?.userModel = newUser
		editProfileCell?.userModel = newUser
		profileCommentCell?.userModel = newUser
	}
	
	func mapButtonTapped() {
		pushMapView()
	}
	
	func showMuteUserAlert() {
		// If the user hit the "Unmute" button we'll get here. No need for alert, just unmute.
		guard let currentUser = CurrentUser.shared.loggedInUser, let targetUser = modelKrakenUser else {
			return
		}
		if currentUser.mutedUsers.contains(targetUser) {
			CurrentUser.shared.setRelation(type: .mute, forUser: targetUser, to: false)
			return		
		}
	
		let message = "This will hide all content by user \"\(targetUser.username)\" from you. They won't know they're muted by you."
   		let alert = UIAlertController(title: "Mute User", message: message, preferredStyle: .alert) 
		alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: "Cancel action"), 
				style: .cancel, handler: nil))
		alert.addAction(UIAlertAction(title: NSLocalizedString("Mute", comment: "Default action"), 
				style: .destructive, handler: { action in
					CurrentUser.shared.setRelation(type: .mute, forUser: targetUser, to: true)
				}))
		present(alert, animated: true, completion: nil)
	}
	
	func showBlockUserAlert() {
		// If the user hit the "Unblock" button we'll get here. No need for alert, just unblock.
		guard let currentUser = CurrentUser.shared.loggedInUser, let targetUser = modelKrakenUser else {
			return
		}
		if currentUser.blockedUsers.contains(targetUser) {
			CurrentUser.shared.setRelation(type: .block, forUser: targetUser, to: false)
			return		
		}
	
		let message = "This will hide all content by user \"\(targetUser.username)\" from you, and hide all your content from them."
   		let alert = UIAlertController(title: "Block User", message: message, preferredStyle: .alert) 
		alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: "Cancel action"), 
				style: .cancel, handler: nil))
		alert.addAction(UIAlertAction(title: NSLocalizedString("Block", comment: "Default action"), 
				style: .destructive, handler: blockUserConfirmed))
		present(alert, animated: true, completion: nil)
	}
	
	func blockUserConfirmed(action: UIAlertAction) {
		if let targetUser = modelKrakenUser {
			CurrentUser.shared.setRelation(type: .block, forUser: targetUser, to: true)
		}
	}
    
// MARK: Navigation
	override var knownSegues : Set<GlobalKnownSegue> {
		Set<GlobalKnownSegue>([ .showUserTweets, .showUserMentions, .showRoomOnDeckMap, .editUserProfile ])
	}

    func pushUserTweetsView() {
    	if let username = modelUserName {
    		self.performKrakenSegue(.showUserTweets, sender: "\(username)")
		}
    }
    
    func pushForumMentionsView() {
    	if let username = modelUserName {
    		self.performKrakenSegue(.showUserMentions, sender: "@\(username)")
		}
    }
    
    func pushMapView() {
    	if let user = modelKrakenUser, let roomNumber = user.roomNumber {
			self.performKrakenSegue(.showRoomOnDeckMap, sender: roomNumber)
    	}
    }
    
    func pushSendSeamailView() {
    	var participants = Set<String>()
    	if let loggedInUser = CurrentUser.shared.loggedInUser {
			participants.insert(loggedInUser.username)
		}
		if let shownUser = modelKrakenUser {
			participants.insert(shownUser.username)
		}
		let packet = GlobalNavPacket(from: self, tab: .seamail, arguments: ["seamailThreadParticipants" : participants ])
    	if let appDel = UIApplication.shared.delegate as? AppDelegate {
    		appDel.globalNavigateTo(packet: packet)
		}
    }
    
    func pushEditProfileView() {
    	self.performKrakenSegue(.editUserProfile, sender: nil)
    }
    
	// This is the unwind segue handler for hte profile edit VC
	@IBAction func dismissingProfileEditVC(segue: UIStoryboardSegue) {
		
	}
	

}

// MARK: - Cells

@objc protocol ProfileAvatarCellProtocol: FetchedResultsBindingProtocol {
	var isInteractive: Bool { get set }
}

@objc class ProfileAvatarCellModel: FetchedResultsCellModel, ProfileAvatarCellProtocol {
	private static let validReuseIDs = [ "ProfileAvatarLeft" : ProfileAvatarCell.self ]
	override class var validReuseIDDict: [String: BaseCollectionViewCell.Type ] { return validReuseIDs }

	var isInteractive: Bool = true
	
	init(user: KrakenUser?) {
		super.init(withModel: user, reuse: "ProfileAvatarLeft", bindingWith: ProfileAvatarCellProtocol.self)
		model = user
	}
}

@objc class ProfileAvatarCell: BaseCollectionViewCell, ProfileAvatarCellProtocol {
	@IBOutlet var userNameLabel: UILabel!
	@IBOutlet var realNameLabel: UILabel!
	@IBOutlet var pronounsLabel: UILabel!
	@IBOutlet var userAvatar: UIImageView!
	@IBOutlet weak var favoriteButton: UIButton!
	@IBOutlet weak var favoritePendingLabel: UILabel!
	
	private static let cellInfo = [ "ProfileAvatarLeft" : PrototypeCellInfo("ProfileAvatarLeftCell") ]
	override class var validReuseIDDict: [ String: PrototypeCellInfo ] { return cellInfo }
	
	var isInteractive: Bool = true

	override func awakeFromNib() {
		favoritePendingLabel.isHidden = true

		// Set up gesture recognizer to detect taps on the (single) photo, and open the fullscreen photo overlay.
		let photoTap = UITapGestureRecognizer(target: self, action: #selector(ProfileAvatarCell.photoTapped(_:)))
	 	userAvatar.addGestureRecognizer(photoTap)
	}

	@objc func photoTapped(_ sender: UITapGestureRecognizer) {
		if let vc = viewController as? BaseCollectionViewController, let image = userAvatar.image {
			vc.showImageInOverlay(image: image)
		}
	}

	dynamic var model: NSFetchRequestResult? {
		didSet {
			clearObservations()
			if let userModel = model as? KrakenUser {
				userModel.tell(self, when: "displayName") { observer, observed in
					if observed.displayName == observed.username {
						observer.userNameLabel.text = String("@\(observed.displayName)")
					}
					else {
						observer.userNameLabel.text = String("\(observed.displayName) \n(@\(observed.username))")
					}
				}?.execute()
				userModel.tell(self, when: "realName") { observer, observed in
					observer.realNameLabel.text = observed.realName
				}?.execute()
				userModel.tell(self, when: "pronouns") { observer, observed in
					observer.pronounsLabel.text = observed.pronouns
				}?.execute()
				userModel.tell(self, when: [ "userImageName" ]) { observer, observed in
					observed.loadUserFullPhoto()
				}?.execute()
				userModel.tell(self, when: [ "fullPhoto", "thumbPhoto" ]) { observer, observed in
					if let fullPhoto = observed.fullPhoto {
						observer.userAvatar.image = fullPhoto
					}
					else if let thumbPhoto = observed.thumbPhoto {
						observer.userAvatar.image = thumbPhoto
					}
				}?.execute()
				
				CurrentUser.shared.tell(self, when: ["loggedInUser", "loggedInUser.postOps", 
						"loggedInUser.favoriteUsers"]) { observer, observed in
					var selectFavButton = false
					if let currentUser = observed.loggedInUser {
						selectFavButton = currentUser.favoriteUsers.contains(where: { $0.userID == userModel.userID })
								
						if let favOp = currentUser.getPendingUserRelationOp(type: .favorite, forUser: userModel, 
								inContext: LocalCoreData.shared.mainThreadContext) {
							selectFavButton = favOp.isActive
							observer.favoritePendingLabel.isHidden = false		
							observer.favoritePendingLabel.text = favOp.isActive ? "Favorite Pending" : "Un-favorite Pending"
						}
						else {
							observer.favoritePendingLabel.isHidden = true		
						}
						observer.favoriteButton.isSelected = selectFavButton						
					}
					else {
						observer.favoriteButton.isSelected = false
						observer.favoritePendingLabel.isHidden = true
					}
				}?.execute()
			}
			else {
				userNameLabel.text = ""
				realNameLabel.text = ""
				pronounsLabel.text = ""
				userAvatar.image = nil
				favoriteButton.isSelected = false
				favoritePendingLabel.isHidden = true
			}
		}
	}
	
	@IBAction func favoriteButtonHit(_ sender: Any) {
		guard isInteractive	else { return }
		if let userToFav = model as? KrakenUser {
			favoriteButton.isSelected = !favoriteButton.isSelected
			CurrentUser.shared.setRelation(type: .favorite, forUser: userToFav, to: favoriteButton.isSelected)
		}
	}
}

@objc class UserProfileSingleValueCellModel: BaseCellModel, SingleValueCellProtocol {
	private static let validReuseIDs = [ "SingleValue" : SingleValueCell.self ]
	override class var validReuseIDDict: [String: BaseCollectionViewCell.Type ] { return validReuseIDs }

	@objc dynamic var userModel: KrakenUser?
	dynamic var title: String?
	dynamic var value: String?

	enum DisplayMode: String {
		case pronouns = "pronouns"
		case email = "email"
		case roomNumber = "room #"
		case homeLocation = "hometown"
		case currentLocation = "last seen"
		case dinnerTeam = "dinner team"
		case aboutMessage = "About this user"
	}
	dynamic var displayMode: DisplayMode
	
	init(user: KrakenUser?, mode: DisplayMode) {
		displayMode = mode
		userModel = user
		title = displayMode.rawValue
		super.init(bindingWith: SingleValueCellProtocol.self)

		switch displayMode {
		case .pronouns:
			addObservation(self.tell(self, when: "userModel.pronouns") { observer, observed in
				observer.value = observed.userModel?.pronouns
				observer.shouldBeVisible = observed.userModel?.pronouns != nil
			}?.schedule())
		case .email:
			addObservation(self.tell(self, when: "userModel.emailAddress") { observer, observed in
				observer.value = observed.userModel?.emailAddress
				observer.shouldBeVisible = observed.userModel?.emailAddress != nil
			}?.schedule())
		case .roomNumber: 
			addObservation(self.tell(self, when: "userModel.roomNumber") { observer, observed in
				observer.value = observed.userModel?.roomNumber
				observer.shouldBeVisible = observed.userModel?.roomNumber != nil
			}?.schedule())
		case .homeLocation:
			addObservation(self.tell(self, when: "userModel.homeLocation") { observer, observed in
				observer.value = observed.userModel?.homeLocation
				observer.shouldBeVisible = observed.userModel?.homeLocation != nil
			}?.schedule())
		case .currentLocation:
			addObservation(self.tell(self, when: "userModel.currentLocation") { observer, observed in
				observer.value = observed.userModel?.currentLocation
				observer.shouldBeVisible = observed.userModel?.currentLocation != nil
			}?.schedule())
		case .dinnerTeam:
			addObservation(self.tell(self, when: "userModel.dinnerTeam") { observer, observed in
				observer.value = observed.userModel?.dinnerTeam
				observer.shouldBeVisible = observed.userModel?.dinnerTeam != nil
			}?.schedule())
		case .aboutMessage:
			addObservation(self.tell(self, when: "userModel.aboutMessage") { observer, observed in
				observer.value = observed.userModel?.aboutMessage
				observer.shouldBeVisible = observed.userModel?.aboutMessage != nil
			}?.schedule())
		}
	}
}

@objc class ProfileDisclosureCellModel: DisclosureCellModel {

	@objc dynamic var userModel: KrakenUser?
	var viewController: UserProfileViewController?

	enum DisplayMode {
		case authoredTweets
//		case mentions		
		case sendSeamail
		case editOwnProfile	
	}
	dynamic var displayMode: DisplayMode
	
	init(user: KrakenUser?, mode: DisplayMode, vc: UserProfileViewController) {
		displayMode = mode
		userModel = user
		viewController = vc
		super.init()

		switch displayMode {
		case .authoredTweets:
			self.tell(self, when: ["userModel.tweetMentions"]) { observer, observed in
				switch observed.userModel?.getAuthoredTweetCount() {
				case 0: observer.title = "No Tweets"
				case 1: observer.title = "1 Tweet"
				default: 
					if let num = observed.userModel?.getAuthoredTweetCount() {
						observer.title = "\(num) Tweets"
					}
					else {
						observer.title = "See Tweets"
					} 
				}
			}?.schedule()
			shouldBeVisible = true
//		case .mentions:
//			self.tell(self, when: "userModel.forumMentions") { observer, observed in
//				switch observed.userModel?.forumMentions {
//				case 0: observer.title = "No Mentions"
//				case 1: observer.title = "1 Mention"
//				default: 
//					if let num = observed.userModel?.forumMentions {
//						observer.title = "\(num) Mentions"
//					}
//					else {
//						observer.title = "See Mentions"
//					} 
//				}
//			}?.schedule()
//			shouldBeVisible = true
		case .sendSeamail:
			self.tell(self, when: "userModel.username") { observer, observed in
				observer.title = "Send Seamail to \(observed.userModel?.username ?? "user")"
				observer.shouldBeVisible = observed.userModel?.username != CurrentUser.shared.loggedInUser?.username &&
						observed.userModel?.username != nil
			}?.execute()
			CurrentUser.shared.tell(self, when: "loggedInUser") { observer, observed in
				observer.shouldBeVisible = observer.userModel?.username != observed.loggedInUser?.username
			}?.execute()
		case .editOwnProfile:
			title = "Edit your user profile"
			self.tell(self, when: "userModel") { observer, observed in
				if let loggedInUser = CurrentUser.shared.loggedInUser, let profileUser = observed.userModel {
					observer.shouldBeVisible = profileUser.username == loggedInUser.username
				}
				else {
					observer.shouldBeVisible = false
				}
			}
			CurrentUser.shared.tell(self, when: "loggedInUser") { observer, observed in
				if let loggedInUser = observed.loggedInUser, let profileUser = observer.userModel {
					observer.shouldBeVisible = profileUser.username == loggedInUser.username
				}
				else {
					observer.shouldBeVisible = false
				}
			}?.execute()
		}
	}
	
	override func cellTapped(dataSource: KrakenDataSource?, vc: UIViewController?) {
	
		// Trying it this way, but I think it's better if the cell launches segues itself (besides how I feel about segues).
		switch displayMode {
		case .authoredTweets: viewController?.pushUserTweetsView()
//		case .mentions: viewController?.pushForumMentionsView()
		case .sendSeamail: viewController?.pushSendSeamailView()
		case .editOwnProfile: viewController?.pushEditProfileView()
		}
	}
}


