//
//  UserProfileViewController.swift
//  Kraken
//
//  Created by Chall Fry on 4/13/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit


class UserProfileViewController: BaseCollectionViewController {
	let dataSource = KrakenDataSource()
	
	// The user name is what the VC is 'modeling', not the KrakenUser. This way, even if there's no user with that name,
	// the VC still appears and is responsible for displaying the error.
	var modelUserName : String?
	fileprivate var modelKrakenUser: KrakenUser?

    override func viewDidLoad() {
        super.viewDidLoad()
        dataSource.collectionView = collectionView
        self.title = String("User: \(modelUserName ?? "")")

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
    var currentLocationCell: UserProfileSingleValueCellModel?
    var authoredTweetsCell: ProfileDisclosureCellModel?
    var mentionsCell: ProfileDisclosureCellModel?
    var sendSeamailCell: ProfileDisclosureCellModel?
    var profileCommentCell: ProfileCommentCellModel?
    
    func setupCellModels() {

    	let section = dataSource.appendFilteringSegment(named: "UserProfile")
    	avatarCell = ProfileAvatarCellModel(user: modelKrakenUser)
		emailCell = UserProfileSingleValueCellModel(user: modelKrakenUser, mode: .email)
		homeLocationCell = UserProfileSingleValueCellModel(user: modelKrakenUser, mode: .homeLocation)
		roomNumberCell = UserProfileSingleValueCellModel(user: modelKrakenUser, mode: .roomNumber)
		currentLocationCell = UserProfileSingleValueCellModel(user: modelKrakenUser, mode: .currentLocation)
		authoredTweetsCell = ProfileDisclosureCellModel(user: modelKrakenUser, mode:.authoredTweets, vc: self)
		mentionsCell = ProfileDisclosureCellModel(user: modelKrakenUser, mode:.mentions, vc: self)
		sendSeamailCell = ProfileDisclosureCellModel(user: modelKrakenUser, mode:.sendSeamail, vc: self)		
		profileCommentCell = ProfileCommentCellModel(user: modelKrakenUser)

    	section.append(avatarCell!)
		section.append(emailCell!)
		section.append(homeLocationCell!)
		section.append(roomNumberCell!)
		section.append(currentLocationCell!)
		section.append(authoredTweetsCell!)
		section.append(mentionsCell!)
		section.append(sendSeamailCell!)		
		section.append(profileCommentCell!)
    }
    
    func updateCellModels(to newUser: KrakenUser?) {
		self.modelKrakenUser = newUser
    	avatarCell?.userModel = newUser
    	emailCell?.userModel = newUser
		homeLocationCell?.userModel = newUser
		roomNumberCell?.userModel = newUser
		currentLocationCell?.userModel = newUser
		authoredTweetsCell?.userModel = newUser
		mentionsCell?.userModel = newUser
		sendSeamailCell?.userModel = newUser
		profileCommentCell?.userModel = newUser
	}
    
    // MARK: - Navigation
	var filterForNextVC: String?
    func pushUserTweetsView() {
    	if let username = modelUserName {
	    	filterForNextVC = "\(username)"
    		self.performSegue(withIdentifier: "ShowUserTweets", sender: self)
		}
    }
    
    func pushUserMentionsView() {
    	if let username = modelUserName {
	    	filterForNextVC = "@\(username)"
    		self.performSegue(withIdentifier: "ShowUserMentions", sender: self)
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
		let packet = GlobalNavPacket(tab: .seamail, arguments: ["seamailThreadParticipants" : participants ])
    	RootTabBarViewController.shared?.globalNavigateTo(packet: packet)
    }

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
		if segue.identifier == "ShowUserMentions", let destVC = segue.destination as? TwitarrViewController {
			destVC.dataManager = TwitarrDataManager(filterString: filterForNextVC)
		}
		if segue.identifier == "ShowUserTweets", let destVC = segue.destination as? TwitarrViewController, 
				let filterString = filterForNextVC {
			destVC.dataManager = TwitarrDataManager(predicate: NSPredicate(format: "author.username == %@", filterString))
		}
    }
    

}

@objc protocol ProfileAvatarCellProtocol {
	var userModel: KrakenUser? { get set }
}

@objc class ProfileAvatarCellModel: BaseCellModel, ProfileAvatarCellProtocol {
	private static let validReuseIDs = [ "ProfileAvatarLeft" : ProfileAvatarCell.self ]
	override class var validReuseIDDict: [String: BaseCollectionViewCell.Type ] { return validReuseIDs }

	var userModel: KrakenUser?
	
	init(user: KrakenUser?) {
		super.init(bindingWith: ProfileAvatarCellProtocol.self)
		userModel = user
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
	
	override func awakeFromNib() {
		favoritePendingLabel.isHidden = true
	}

	dynamic var userModel: KrakenUser? {
		didSet {
			clearObservations()
			if let userModel = self.userModel {
				userModel.tell(self, when: "displayName") { observer, observed in
					observer.userNameLabel.text = String("@\(observed.displayName)")
				}?.execute()
				userModel.tell(self, when: "realName") { observer, observed in
					observer.realNameLabel.text = observed.realName
				}?.execute()
				userModel.tell(self, when: "pronouns") { observer, observed in
					observer.pronounsLabel.text = observed.pronouns
				}?.execute()
				userModel.tell(self, when: [ "fullPhoto", "thumbPhoto" ]) { observer, observed in
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
		if let userToFav = userModel {
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
						observer.title = String("\(observed.numberOfTweets) Tweets")
					}?.schedule()
					shouldBeVisible = true
			case .mentions:
					user.tell(self, when: "numberOfMentions") { observer, observed in
						observer.title = String("\(observed.numberOfMentions) Mentions")
					}?.schedule()
					shouldBeVisible = true
			case .sendSeamail:
					title = "Send Seamail to \(user.username)"
					shouldBeVisible = user.username != CurrentUser.shared.loggedInUser?.username
			}
		}
	}
	
	override func cellTapped() {
		switch displayMode {
		case .authoredTweets: viewController?.pushUserTweetsView()
		case .mentions: viewController?.pushUserMentionsView()
		case .sendSeamail: viewController?.pushSendSeamailView()
		}
	}
}


