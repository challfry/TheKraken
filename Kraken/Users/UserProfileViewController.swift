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
	        modelKrakenUser = UserManager.shared.loadUserProfile(userName)
		}
		
		setupCellModels()
		collectionView.dataSource = dataSource      
		collectionView.delegate = dataSource      
    }
    
    override func viewDidAppear(_ animated: Bool) {
		dataSource.enableAnimations = true
	}
    
	@objc func startRefresh() {
    }
    
    func setupCellModels() {

    	let section = dataSource.appendFilteringSegment(named: "UserProfile")
    	section.append(ProfileAvatarCellModel(user: modelKrakenUser))
		section.append(UserProfileSingleValueCellModel(user: modelKrakenUser, mode: .email))
		section.append(UserProfileSingleValueCellModel(user: modelKrakenUser, mode: .homeLocation))
		section.append(UserProfileSingleValueCellModel(user: modelKrakenUser, mode: .roomNumber))
		section.append(UserProfileSingleValueCellModel(user: modelKrakenUser, mode: .currentLocation))
		section.append(ProfileDisclosureCellModel(user: modelKrakenUser, mode:.authoredTweets, vc: self))
		section.append(ProfileDisclosureCellModel(user: modelKrakenUser, mode:.mentions, vc: self))
		section.append(ProfileDisclosureCellModel(user: modelKrakenUser, mode:.sendSeamail, vc: self))		
		section.append(ProfileCommentCellModel(user: modelKrakenUser))
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

	private static let cellInfo = [ "ProfileAvatarLeft" : PrototypeCellInfo("ProfileAvatarLeftCell") ]
	override class var validReuseIDDict: [ String: PrototypeCellInfo ] { return cellInfo }

	dynamic var userModel: KrakenUser? {
		didSet {
//			clearObservations()
			if let userModel = self.userModel {
				userModel.tell(self, when: "displayName") { observer, observed in
					observer.userNameLabel.text = String("@\(observed.displayName)")
				}?.schedule()
				userModel.tell(self, when: "realName") { observer, observed in
					observer.realNameLabel.text = observed.realName
				}?.schedule()
				userModel.tell(self, when: "pronouns") { observer, observed in
					observer.pronounsLabel.text = observed.pronouns
				}?.schedule()
				userModel.tell(self, when: [ "fullPhoto", "thumbPhoto" ]) { observer, observed in
					if let fullPhoto = observed.fullPhoto {
						observer.userAvatar.image = fullPhoto
					}
					else if let thumbPhoto = observed.thumbPhoto {
						observer.userAvatar.image = thumbPhoto
					}
				}?.schedule()
			}
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
			case .mentions:
					user.tell(self, when: "numberOfMentions") { observer, observed in
						observer.title = String("\(observed.numberOfMentions) Mentions")
					}?.schedule()
			case .sendSeamail:
					title = "Send Seamail to \(user.username)"
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

@objc protocol ProfileCommentCellProtocol {
	dynamic var comment: String? { get set }
}

@objc class ProfileCommentCellModel: BaseCellModel, ProfileCommentCellProtocol {
	private static let validReuseIDs = [ "ProfileComment" : ProfileCommentCell.self ]
	override class var validReuseIDDict: [String: BaseCollectionViewCell.Type ] { return validReuseIDs }

	var userModel: KrakenUser?
	dynamic var comment: String?
	
	init(user: KrakenUser?) {
		userModel = user
		super.init(bindingWith: ProfileCommentCellProtocol.self)

//		clearObservations()
//		if let model = userModel as? CellModel, let userModel = model.userModel, let currentUser = CurrentUser.shared.loggedInUser {
//			if let commentAndStar = currentUser.commentsAndStars?.first(where: { $0.commentedOnUser.username == userModel.username } ) {
//				commentView.text = commentAndStar.comment
//			}
//		}
	}
	
}


class ProfileCommentCell: BaseCollectionViewCell, ProfileCommentCellProtocol {
	@IBOutlet var commentView: UITextView!
	@IBOutlet var saveButton: UIButton!
	private static let cellInfo = [ "ProfileComment"  : PrototypeCellInfo("ProfileCommentCell") ]
	override class var validReuseIDDict: [ String: PrototypeCellInfo ] { return cellInfo }
	
	dynamic var comment: String?

	@IBAction func saveButtonTapped() {
		if let model = cellModel as? ProfileCommentCellModel, let userModel = model.userModel {
			CurrentUser.shared.setUserComment(commentView.text, forUser: userModel) {}
		}
	}
}
