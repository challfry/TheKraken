//
//  UserProfileViewController.swift
//  Kraken
//
//  Created by Chall Fry on 4/13/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit


class UserProfileViewController: BaseCollectionViewController {
	let dataSource = FilteringDataSource()
	
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

    	let section = dataSource.appendSection(named: "UserProfile")
    	section.append(UserProfileAvatarCellModel(user: modelKrakenUser))
		section.append(UserProfileSingleValueCellModel(user: modelKrakenUser, mode: .email))
		section.append(UserProfileSingleValueCellModel(user: modelKrakenUser, mode: .homeLocation))
		section.append(UserProfileSingleValueCellModel(user: modelKrakenUser, mode: .roomNumber))
		section.append(UserProfileSingleValueCellModel(user: modelKrakenUser, mode: .currentLocation))
		section.append(UserProfileDisclosureCellModel(user: modelKrakenUser, mode:.authoredTweets, vc: self))
		section.append(UserProfileDisclosureCellModel(user: modelKrakenUser, mode:.mentions, vc: self))
		section.append(UserProfileDisclosureCellModel(user: modelKrakenUser, mode:.sendSeamail, vc: self))		
		section.append(UserProfileCommentCellModel(user: modelKrakenUser))
    }

    
    // MARK: - Navigation
	var filterForNextVC: String?
    func pushUserTweetsView() {
    	if let username = modelUserName {
	    	filterForNextVC = "@\(username)"
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
		if segue.identifier == "ShowUserTweets", let destVC = segue.destination as? TwitarrViewController {
			destVC.dataManager = TwitarrDataManager(filterString: filterForNextVC)
		}
    }
    

}

@objc protocol UserProfileAvatarCellProtocol {
	var userModel: KrakenUser? { get set }
}

@objc class UserProfileAvatarCellModel: BaseCellModel, UserProfileAvatarCellProtocol {
	private static let validReuseIDs = [ "UserProfileAvatarLeft" : NibAndClass(UserProfileAvatarCell.self, nil)]
	override class var validReuseIDDict: [String: NibAndClass ] { return validReuseIDs }

	var userModel: KrakenUser?
	
	init(user: KrakenUser?) {
		super.init(bindingWith: UserProfileAvatarCellProtocol.self)
		userModel = user
	}
}

@objc class UserProfileAvatarCell: BaseCollectionViewCell, UserProfileAvatarCellProtocol {
	@IBOutlet var userNameLabel: UILabel!
	@IBOutlet var realNameLabel: UILabel!
	@IBOutlet var pronounsLabel: UILabel!
	@IBOutlet var userAvatar: UIImageView!

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

@objc protocol UserProfileSingleValueCellProtocol {
	var title: String? { get set }
	var value: String? { get set }
}

@objc class UserProfileSingleValueCellModel: BaseCellModel, UserProfileSingleValueCellProtocol {
	private static let validReuseIDs = [ "UserProfileSingleValue" : NibAndClass(UserProfileSingleValueCell.self,  nil)]
	override class var validReuseIDDict: [String: NibAndClass ] { return validReuseIDs }

	typealias Cell = UserProfileSingleValueCell
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
		super.init(bindingWith: UserProfileSingleValueCellProtocol.self)

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

class UserProfileSingleValueCell: BaseCollectionViewCell, UserProfileSingleValueCellProtocol {
	@IBOutlet var titleLabel: UILabel!
	@IBOutlet var valueLabel: UILabel!

	var title: String? {
		didSet { titleLabel.text = title }
	}
	var value: String? {
		didSet { valueLabel.text = value }
	}
}


@objc protocol UserProfileDisclosureCellProtocol {
	dynamic var title: String? { get set }
}

@objc class UserProfileDisclosureCellModel: BaseCellModel, UserProfileDisclosureCellProtocol {
	private static let validReuseIDs = [ "UserProfileDisclosureCell" : NibAndClass(UserProfileDisclosureCell.self, nil)]
	override class var validReuseIDDict: [String: NibAndClass ] { return validReuseIDs }

	var userModel: KrakenUser?
	dynamic var title: String?
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
		super.init(bindingWith: UserProfileDisclosureCellProtocol.self)

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

class UserProfileDisclosureCell: BaseCollectionViewCell, UserProfileDisclosureCellProtocol {
	@IBOutlet var titleLabel: UILabel!
	var title: String? {
		didSet { titleLabel.text = title }
	}
}

@objc protocol UserProfileCommentCellProtocol {
	dynamic var comment: String? { get set }
}

@objc class UserProfileCommentCellModel: BaseCellModel, UserProfileCommentCellProtocol {
	private static let validReuseIDs = [ "UserProfileCommentCell" : NibAndClass(UserProfileCommentCell.self, nil)]
	override class var validReuseIDDict: [String: NibAndClass ] { return validReuseIDs }

	var userModel: KrakenUser?
	dynamic var comment: String?
	
	init(user: KrakenUser?) {
		userModel = user
		super.init(bindingWith: UserProfileCommentCellProtocol.self)

//		clearObservations()
//		if let model = userModel as? CellModel, let userModel = model.userModel, let currentUser = CurrentUser.shared.loggedInUser {
//			if let commentAndStar = currentUser.commentsAndStars?.first(where: { $0.commentedOnUser.username == userModel.username } ) {
//				commentView.text = commentAndStar.comment
//			}
//		}
	}
	
}


class UserProfileCommentCell: BaseCollectionViewCell, UserProfileCommentCellProtocol {
	@IBOutlet var commentView: UITextView!
	@IBOutlet var saveButton: UIButton!
	dynamic var comment: String?
	
	@IBAction func saveButtonTapped() {
		if let model = cellModel as? UserProfileCommentCellModel, let userModel = model.userModel {
			CurrentUser.shared.setUserComment(commentView.text, forUser: userModel)
		}
	}
}
