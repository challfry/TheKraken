//
//  UserProfileViewController.swift
//  Kraken
//
//  Created by Chall Fry on 4/13/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit


@objc class UserProfileViewController: BaseCollectionViewController {
	let dataSource = KrakenDataSource()
	
	// The user name is what the VC is 'modeling', not the KrakenUser. This way, even if there's no user with that name,
	// the VC still appears and is responsible for displaying the error.
	var modelUserName : String?
	@objc dynamic fileprivate var modelKrakenUser: KrakenUser?

    override func viewDidLoad() {
        super.viewDidLoad()
        dataSource.collectionView = collectionView
        self.title = String("User: \(modelUserName ?? "")")
		knownSegues = Set([.showUserTweets, .showUserMentions, .showRoomOnDeckMap, .editUserProfile])

		collectionView.refreshControl = UIRefreshControl()
		collectionView.refreshControl?.addTarget(self, action: #selector(self.self.startRefresh), for: .valueChanged)

		if let userName = modelUserName {
	        modelKrakenUser = UserManager.shared.loadUserProfile(userName) { resultUser in
				if self.modelKrakenUser != resultUser {
					self.updateCellModels(to: resultUser)
				}
			}
		}
		
		setupCellModels()
		dataSource.register(with: collectionView, viewController: self)
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
	var emailCell: UserProfileSingleValueCellModel?
    var homeLocationCell: UserProfileSingleValueCellModel?
    var roomNumberCell: UserProfileSingleValueCellModel?
    var mapRoomCell: ButtonCellModel?
    var currentLocationCell: UserProfileSingleValueCellModel?
    var authoredTweetsCell: ProfileDisclosureCellModel?
    var mentionsCell: ProfileDisclosureCellModel?
    var sendSeamailCell: ProfileDisclosureCellModel?
    var editProfileCell: ProfileDisclosureCellModel?
    var profileCommentCell: ProfileCommentCellModel?
    
    lazy var blockUserCell: ButtonCellModel = {
		let cell = ButtonCellModel(alignment: .center)
		cell.button1Action = {
			self.showBlockUserAlert()
		}
		cell.button1Enabled = true
		
		CurrentUser.shared.tell(self, when: "loggedInUser") { observer, observed in 
			cell.shouldBeVisible = observed.isLoggedIn() && observed.loggedInUser?.username != observer.modelUserName
		}?.execute()
		
		CurrentUser.shared.tell(self, when: "loggedInUser.blockedUsers") { observer, observed in 
			if let currentUser = observed.loggedInUser, let viewingUser = observer.modelKrakenUser,
					currentUser.blockedUsers.contains(viewingUser) {
				cell.button1Text = "Unblock User"		
			}
			else {
				cell.button1Text = "Block User"
			}	
		}?.execute()

		return cell
    }()
    
    func setupCellModels() {

    	let section = dataSource.appendFilteringSegment(named: "UserProfile")
    	avatarCell = ProfileAvatarCellModel(user: modelKrakenUser)
		emailCell = UserProfileSingleValueCellModel(user: modelKrakenUser, mode: .email)
		homeLocationCell = UserProfileSingleValueCellModel(user: modelKrakenUser, mode: .homeLocation)
		roomNumberCell = UserProfileSingleValueCellModel(user: modelKrakenUser, mode: .roomNumber)
		mapRoomCell = ButtonCellModel(title: "Show Room On Map", action: mapButtonTapped, alignment: .center)
		
		currentLocationCell = UserProfileSingleValueCellModel(user: modelKrakenUser, mode: .currentLocation)
		authoredTweetsCell = ProfileDisclosureCellModel(user: modelKrakenUser, mode:.authoredTweets, vc: self)
		mentionsCell = ProfileDisclosureCellModel(user: modelKrakenUser, mode:.mentions, vc: self)
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
		section.append(emailCell!)
		section.append(homeLocationCell!)
		section.append(roomNumberCell!)
		section.append(mapRoomCell!)
		section.append(currentLocationCell!)
		section.append(authoredTweetsCell!)
		section.append(mentionsCell!)
		section.append(sendSeamailCell!)		
		section.append(editProfileCell!)		
		section.append(profileCommentCell!)
		section.append(blockUserCell)
    }
    
    func updateCellModels(to newUser: KrakenUser?) {
		self.modelKrakenUser = newUser
    	avatarCell?.model = newUser
    	emailCell?.userModel = newUser
		homeLocationCell?.userModel = newUser
		roomNumberCell?.userModel = newUser
		currentLocationCell?.userModel = newUser
		authoredTweetsCell?.userModel = newUser
		mentionsCell?.userModel = newUser
		sendSeamailCell?.userModel = newUser
		editProfileCell?.userModel = newUser
		profileCommentCell?.userModel = newUser
	}
	
	func mapButtonTapped() {
		pushMapView()
	}
	
	func showBlockUserAlert() {
		// If the user hit the "Unblock" button we'll get here. No need for alert, just unblock.
		if let curUser = CurrentUser.shared.loggedInUser, let userToBlock = modelKrakenUser,
				curUser.blockedUsers.contains(userToBlock) {
			curUser.setupBlockOnUser(userToBlock, isBlocked: false)
			return		
		}
	
		var message = "This will hide all posts by this user."
		if let user = modelUserName {
			message = "This will hide all posts by user \"\(user)\"."
		}
	
   		let alert = UIAlertController(title: "Block User", message: message, preferredStyle: .alert) 
		alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: "Cancel action"), 
				style: .cancel, handler: nil))
		alert.addAction(UIAlertAction(title: NSLocalizedString("Block", comment: "Default action"), 
				style: .destructive, handler: blockUserConfirmed))
		present(alert, animated: true, completion: nil)
	}
	
	func blockUserConfirmed(action: UIAlertAction) {
		if let userToBlock = modelKrakenUser {
			CurrentUser.shared.loggedInUser?.setupBlockOnUser(userToBlock, isBlocked: true)
		}
	}
    
    // MARK: Navigation
    func pushUserTweetsView() {
    	if let username = modelUserName {
    		self.performKrakenSegue(.showUserTweets, sender: "\(username)")
		}
    }
    
    func pushUserMentionsView() {
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
				userModel.tell(self, when: [ "fullPhoto", "thumbPhoto", "thumbPhotoData" ]) { observer, observed in
					observed.loadUserThumbnail()
					if let fullPhoto = observed.fullPhoto {
						observer.userAvatar.image = fullPhoto
					}
					else if let thumbPhoto = observed.thumbPhoto {
						observer.userAvatar.image = thumbPhoto
					}
				}?.execute()
				
				CurrentUser.shared.tell(self, when: ["loggedInUser", "loggedInUser.postOps.*",
						"loggedInUser.starredUsers.*", "loggedInUser.postOps.*.isFavorite"]) { observer, observed in
					var selectFavButton = false
					if let currentUser = observed.loggedInUser {
						selectFavButton = currentUser.starredUsers?.contains(where: { $0.username == userModel.username })
								?? false
								
						if let favOp = currentUser.getPendingUserFavoriteOp(forUser: userModel, 
								inContext: LocalCoreData.shared.mainThreadContext) {
							selectFavButton = favOp.isFavorite
							observer.favoritePendingLabel.isHidden = false		
							observer.favoritePendingLabel.text = favOp.isFavorite ? "Favorite Pending" : "Un-favorite Pending"
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
			CurrentUser.shared.setFavoriteUser(forUser: userToFav, to: favoriteButton.isSelected)
		}
	}
}

@objc class UserProfileSingleValueCellModel: BaseCellModel, SingleValueCellProtocol {
	private static let validReuseIDs = [ "SingleValue" : SingleValueCell.self ]
	override class var validReuseIDDict: [String: BaseCollectionViewCell.Type ] { return validReuseIDs }

	var userModel: KrakenUser?
	dynamic var title: String?
	dynamic var value: String?

	enum DisplayMode: String {
		case email = "email"
		case roomNumber = "room #"
		case homeLocation = "Hometown"
		case currentLocation = "Last seen"
	}
	dynamic var displayMode: DisplayMode
	
	init(user: KrakenUser?, mode: DisplayMode) {
		displayMode = mode
		userModel = user
		title = displayMode.rawValue
		super.init(bindingWith: SingleValueCellProtocol.self)

		if let user = userModel {
			switch displayMode {
			case .email:
				addObservation(user.tell(self, when: "emailAddress") { observer, observed in
					observer.value = observed.emailAddress
					observer.shouldBeVisible = observed.emailAddress != nil
				}?.schedule())
			case .roomNumber: 
				addObservation(user.tell(self, when: "roomNumber") { observer, observed in
					observer.value = observed.roomNumber
					observer.shouldBeVisible = observed.roomNumber != nil
				}?.schedule())
			case .homeLocation:
				addObservation(user.tell(self, when: "homeLocation") { observer, observed in
					observer.value = observed.homeLocation
					observer.shouldBeVisible = observed.homeLocation != nil
				}?.schedule())
			case .currentLocation:
				addObservation(user.tell(self, when: "currentLocation") { observer, observed in
					observer.value = observed.currentLocation
					observer.shouldBeVisible = observed.currentLocation != nil
				}?.schedule())
			}
		}
	}
}

@objc class ProfileDisclosureCellModel: DisclosureCellModel {

	var userModel: KrakenUser?
	var viewController: UserProfileViewController?

	enum DisplayMode {
		case authoredTweets
		case mentions		
		case sendSeamail
		case editOwnProfile	
	}
	dynamic var displayMode: DisplayMode
	
	init(user: KrakenUser?, mode: DisplayMode, vc: UserProfileViewController) {
		displayMode = mode
		userModel = user
		viewController = vc
		super.init()

		if let user = userModel {
			switch displayMode {
			case .authoredTweets:
				user.tell(self, when: "numberOfTweets") { observer, observed in
					if observed.numberOfTweets == 0 {
						observer.title = String("No Tweets")
					} 
					if observed.numberOfTweets == 1 {
						observer.title = String("1 Tweet")
					}
					else {
						observer.title = String("\(observed.numberOfTweets) Tweets")
					}
				}?.schedule()
				shouldBeVisible = true
			case .mentions:
				user.tell(self, when: "numberOfMentions") { observer, observed in
					if observed.numberOfMentions == 0 {
						observer.title = String("No Mentions")
					} 
					else if observed.numberOfMentions == 1 {
						observer.title = String("\(observed.numberOfMentions) Mention")
					}
					else {
						observer.title = String("\(observed.numberOfMentions) Mentions")
					}
				}?.schedule()
				shouldBeVisible = true
			case .sendSeamail:
				title = "Send Seamail to \(user.username)"
				CurrentUser.shared.tell(self, when: "loggedInUser") { observer, observed in
					self.shouldBeVisible = user.username != observed.loggedInUser?.username
				}?.execute()
			case .editOwnProfile:
				title = "Edit your user profile"
				CurrentUser.shared.tell(self, when: "loggedInUser") { observer, observed in
					if let loggedInUsername = observed.loggedInUser?.username {
						self.shouldBeVisible = self.userModel?.username == loggedInUsername
					}
					else {
						self.shouldBeVisible = false
					}
				}?.execute()
			}
		}
	}
	
	override func cellTapped(dataSource: KrakenDataSource?) {
	
		// Trying it this way, but I think it's better if the cell launches segues itself (besides how I feel about segues).
		switch displayMode {
		case .authoredTweets: viewController?.pushUserTweetsView()
		case .mentions: viewController?.pushUserMentionsView()
		case .sendSeamail: viewController?.pushSendSeamailView()
		case .editOwnProfile: viewController?.pushEditProfileView()
		}
	}
}


