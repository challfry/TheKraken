//
//  UserProfileViewController.swift
//  Kraken
//
//  Created by Chall Fry on 4/13/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit


class UserProfileViewController: UIViewController {

	@IBOutlet var collectionView: UICollectionView!
	var cellModels = [BaseCollectionViewCell.BaseCellModel]()
	
	// The user name is what the VC is 'modeling', not the KrakenUser. This way, even if there's no user with that name,
	// the VC still appears and is responsible for displaying the error.
	var modelUserName : String?
	fileprivate var modelKrakenUser: KrakenUser?

    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = String("User: \(modelUserName ?? "")")

		if let layout = collectionView.collectionViewLayout as? UICollectionViewFlowLayout {
			layout.itemSize = UICollectionViewFlowLayout.automaticSize
			layout.estimatedItemSize = CGSize(width: 375, height: 300 )
			
			layout.minimumLineSpacing = 0
		}

		collectionView.refreshControl = UIRefreshControl()
		collectionView.refreshControl?.addTarget(self, action: #selector(self.self.startRefresh), for: .valueChanged)

		if let userName = modelUserName {
	        modelKrakenUser = UserManager.shared.loadUserProfile(userName)
		}
		
		setupCellModels()        
    }
    
	@objc func startRefresh() {
    }
    
    func setupCellModels() {
    
    	// Use different layouts here for different avatar aspect ratios.
		cellModels.append(UserProfileAvatarCell.CellModel(user: modelKrakenUser))
		
		if modelKrakenUser?.emailAddress != nil {
			cellModels.append(UserProfileSingleValueCell.CellModel(user: modelKrakenUser, mode: .email))
		}
		if modelKrakenUser?.homeLocation != nil {
			cellModels.append(UserProfileSingleValueCell.CellModel(user: modelKrakenUser, mode: .homeLocation))
		}
		if modelKrakenUser?.roomNumber != nil {
			cellModels.append(UserProfileSingleValueCell.CellModel(user: modelKrakenUser, mode: .roomNumber))
		}
		if modelKrakenUser?.currentLocation != nil {
			cellModels.append(UserProfileSingleValueCell.CellModel(user: modelKrakenUser, mode: .currentLocation))
		}
		if let numTweets = modelKrakenUser?.numberOfTweets, numTweets > 0 {
			let cell = UserProfileDisclosureCell.CellModel(user: modelKrakenUser, mode:.authoredTweets)
			cell.viewController = self
			cellModels.append(cell)
		}
		if let numMentions = modelKrakenUser?.numberOfMentions, numMentions > 0 {
			let cell = UserProfileDisclosureCell.CellModel(user: modelKrakenUser, mode:.mentions)
			cell.viewController = self
			cellModels.append(cell)
		}
//		if let currentUser = CurrentUser.shared.loggedInUser, currentUser.username != modelKrakenUser?.username {
			let cell = (UserProfileDisclosureCell.CellModel(user: modelKrakenUser, mode:.sendSeamail))
			cell.viewController = self
			cellModels.append(cell)
			cellModels.append(UserProfileCommentCell.CellModel(user: modelKrakenUser))
//		}
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

// Lumping all of these extensions together since they're indistinguishable from each other
extension UserProfileViewController: UICollectionViewDataSource, UICollectionViewDelegate,  UICollectionViewDelegateFlowLayout {

	func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
		return cellModels.count
	}
	    
	func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
		let cellModel = cellModels[indexPath.row]
		let cell = cellModel.makeCell(for: collectionView, indexPath: indexPath)
		return cell
	}

	func collectionView(_ collectionView: UICollectionView, didHighlightItemAt indexPath: IndexPath) {
		let cellModel = cellModels[indexPath.row]
		cellModel.cellTapped()
	}
}

class UserProfileAvatarCell: BaseCollectionViewCell {
	@IBOutlet var userNameLabel: UILabel!
	@IBOutlet var realNameLabel: UILabel!
	@IBOutlet var pronounsLabel: UILabel!
	@IBOutlet var userAvatar: UIImageView!
	
	class CellModel: BaseCellModel {
		typealias Cell = UserProfileAvatarCell
		var userModel: KrakenUser?
		
		init(user: KrakenUser?) {
			super.init()
			storyboardId = "UserProfileAvatarLeft"
			userModel = user
		}
	}
	
	override func setCellModel(newModel: BaseCellModel) {
		cellModel = newModel
		let model = newModel as? CellModel

		clearObservations()
		if let userModel = model?.userModel {
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

class UserProfileSingleValueCell: BaseCollectionViewCell {
	@IBOutlet var titleLabel: UILabel!
	@IBOutlet var valueLabel: UILabel!
	
	class CellModel: BaseCellModel {
		typealias Cell = UserProfileSingleValueCell
		var userModel: KrakenUser?
		enum DisplayMode: String {
			case email = "email"
			case roomNumber = "room #"
			case homeLocation = "Hometown"
			case currentLocation = "Last seen"
		}
		var displayMode: DisplayMode = .email
		
		init(user: KrakenUser?, mode: DisplayMode) {
			super.init()
			storyboardId = "UserProfileSingleValue"
			userModel = user
			displayMode = mode
		}
	}
	
	override func setCellModel(newModel: BaseCellModel) {
		cellModel = newModel
		let model = newModel as? CellModel

		clearObservations()
		if let cellModel = model, let userModel = cellModel.userModel {
			titleLabel.text = cellModel.displayMode.rawValue
			switch cellModel.displayMode {
			case .email:
				addObservation(userModel.tell(self, when: "emailAddress") { observer, observed in
					observer.valueLabel.text = observed.emailAddress
				}?.schedule())
			case .roomNumber: 
				addObservation(userModel.tell(self, when: "roomNumber") { observer, observed in
					observer.valueLabel.text = observed.roomNumber
				}?.schedule())
			case .homeLocation:
				addObservation(userModel.tell(self, when: "homeLocation") { observer, observed in
					observer.valueLabel.text = observed.homeLocation
				}?.schedule())
			case .currentLocation:
				addObservation(userModel.tell(self, when: "currentLocation") { observer, observed in
					observer.valueLabel.text = observed.currentLocation
				}?.schedule())
			}
		}
	}	
}



class UserProfileDisclosureCell: BaseCollectionViewCell {
	@IBOutlet var titleLabel: UILabel!

	class CellModel: BaseCellModel {
		typealias Cell = UserProfileDisclosureCell
		var userModel: KrakenUser?
		var viewController: UserProfileViewController?

		enum DisplayMode {
			case authoredTweets
			case mentions		
			case sendSeamail		
		}
		var displayMode: DisplayMode = .authoredTweets
		
		init(user: KrakenUser?, mode: DisplayMode) {
			super.init()
			storyboardId = "UserProfileDisclosure"
			userModel = user
			displayMode = mode
		}
		
		override func cellTapped() {
			switch displayMode {
			case .authoredTweets: viewController?.pushUserTweetsView()
			case .mentions: viewController?.pushUserMentionsView()
			case .sendSeamail: viewController?.pushSendSeamailView()
			}
		}
	}

	override func setCellModel(newModel: BaseCellModel) {
		cellModel = newModel

		clearObservations()
		if let model = newModel as? CellModel, let userModel = model.userModel {
			switch model.displayMode {
			case .authoredTweets:
					userModel.tell(self, when: "numberOfTweets") { observer, observed in
						observer.titleLabel.text = String("\(observed.numberOfTweets) Tweets")
					}?.schedule()
			case .mentions:
					userModel.tell(self, when: "numberOfMentions") { observer, observed in
						observer.titleLabel.text = String("\(observed.numberOfMentions) Mentions")
					}?.schedule()
			case .sendSeamail:
					titleLabel.text = "Send Seamail to \(userModel.username)"
			}
		}
	}
}

class UserProfileCommentCell: BaseCollectionViewCell {
	@IBOutlet var commentView: UITextView!
	@IBOutlet var saveButton: UIButton!

	class CellModel: BaseCellModel {
		typealias Cell = UserProfileCommentCell
		var userModel: KrakenUser?
		
		init(user: KrakenUser?) {
			super.init()
			storyboardId = "UserProfileComment"
			userModel = user
		}
	}

	override func setCellModel(newModel: BaseCellModel) {
		cellModel = newModel

		clearObservations()
		if let model = newModel as? CellModel, let userModel = model.userModel, let currentUser = CurrentUser.shared.loggedInUser {
			if let commentAndStar = currentUser.commentsAndStars?.first(where: { $0.commentedOnUser.username == userModel.username } ) {
				commentView.text = commentAndStar.comment
			}
			
//			userModel.tell(self, when: "numberOfTweets") { observer, observed in
//					observer.titleLabel.text = String("\(observed.numberOfTweets) Tweets")
//			}?.schedule()
		}
	}
	
	@IBAction func saveButtonTapped() {
		if let model = cellModel as? CellModel, let userModel = model.userModel {
			CurrentUser.shared.setUserComment(commentView.text, forUser: userModel)
		}
	}
}
