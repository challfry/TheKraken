//
//  ScrapbookViewController.swift
//  Kraken
//
//  Created by Chall Fry on 1/14/20.
//  Copyright © 2020 Chall Fry. All rights reserved.
//

import UIKit

class ScrapbookViewController: BaseCollectionViewController {

	let loginDataSource = KrakenDataSource()
	let loginSegment = LoginDataSourceSegment()

	let favoritesDataSource = KrakenDataSource()
	var tweetSegment = FRCDataSourceSegment<Reaction>()
	var forumSegment = FRCDataSourceSegment<ForumPost>()
	var userSegment = FRCDataSourceSegment<KrakenUser>()
	var eventSegment = FRCDataSourceSegment<Event>()
	var songSegment = FRCDataSourceSegment<KaraokeFavoriteSong>()

	override func viewDidLoad() {
		super.viewDidLoad()
		knownSegues = Set([])

		// Prep the login DS
		loginDataSource.viewController = self
        loginDataSource.append(segment: loginSegment)
        loginSegment.headerCellText = "The Scrapbook shows you all the things you have liked (💛). You'll need to log in to see it."

		// And put all the sections into the Favorites DS.
		favoritesDataSource.append(segment: tweetSegment)
		favoritesDataSource.append(segment: forumSegment)
		favoritesDataSource.append(segment: userSegment)
		favoritesDataSource.append(segment: eventSegment)
		favoritesDataSource.append(segment: songSegment)

		// Manually register the nib for the section header view
		let headerNib = UINib(nibName: "EventSectionHeaderView", bundle: nil)
		collectionView.register(headerNib, forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, 
				withReuseIdentifier: "EventSectionHeaderView")
		favoritesDataSource.buildSupplementaryView = createSectionHeaderView

		CurrentUser.shared.tell(self, when: "loggedInUser") { observer, observed in        		
			if let currentUser = observed.loggedInUser {
				observer.favoritesDataSource.register(with: observer.collectionView, viewController: self)

				observer.tweetSegment.activate(predicate: NSPredicate(format: "word == 'like' AND ANY users == %@", currentUser), 
						sort: [ NSSortDescriptor(key: "sourceTweet.timestamp", ascending: false)], 
						cellModelFactory: observer.createTwitarrCellModel)
				observer.forumSegment.activate(predicate: NSPredicate(format: "ANY likedByUsers == %@", currentUser), 
						sort: [ NSSortDescriptor(key: "timestamp", ascending: false)], 
						cellModelFactory: observer.createForumPostCellModel)
				observer.userSegment.activate(predicate: NSPredicate(format: "ANY starredBy == %@", currentUser), 
						sort: [ NSSortDescriptor(key: "displayName", ascending: true)], 
						cellModelFactory: observer.createFavoriteUserCellModel)
				observer.eventSegment.activate(predicate: NSPredicate(format: "ANY followedBy == %@", currentUser), 
						sort: [ NSSortDescriptor(key: "startTimestamp", ascending: false)], 
						cellModelFactory: observer.createEventCellModel)
				observer.songSegment.activate(predicate: NSPredicate(value: true), 
						sort: [ NSSortDescriptor(key: "songTitle", ascending: true)], 
						cellModelFactory: observer.createSongCellModel)
				if let layout = observer.collectionView.collectionViewLayout as? UICollectionViewFlowLayout {
					layout.headerReferenceSize = CGSize(width: observer.collectionView.frame.size.width, height: 21)
					layout.sectionHeadersPinToVisibleBounds = true
				}
			}
			else {
       			// If nobody's logged in, pop to root, show the login cells.
				observer.loginDataSource.register(with: observer.collectionView, viewController: observer)
				observer.navigationController?.popToViewController(observer, animated: false)
				if let layout = observer.collectionView.collectionViewLayout as? UICollectionViewFlowLayout {
					layout.headerReferenceSize = CGSize(width: 0, height: 0)
					layout.sectionHeadersPinToVisibleBounds = true
				}
			}
		}?.execute()
		
	}
	
    override func viewWillAppear(_ animated: Bool) {
		favoritesDataSource.enableAnimations = true
	}
	
// MARK: Cell Factories
	
	func createSectionHeaderView(_ cv: UICollectionView, _ kind: String, _ indexPath: IndexPath, 
			_ cellModel: BaseCellModel?) -> UICollectionReusableView {
		let newView = cv.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: "EventSectionHeaderView", 
				for: indexPath)
		if let headerView = newView as? EventSectionHeaderView {
			switch cellModel {
			case is TwitarrTweetCellModel: headerView.setTimeLabelText(to: "Favorite Tweets")
			case is ForumPostCellModel: headerView.setTimeLabelText(to: "Favorite Forum Posts")
			case is ProfileAvatarCellModel: headerView.setTimeLabelText(to: "Favorite Users")
			case is EventCellModel: headerView.setTimeLabelText(to: "Favorite Events")
			case is KaraokeFavoriteSongCellModel: headerView.setTimeLabelText(to: "Favorite Karaoke Songs")
			default: headerView.setTimeLabelText(to: "")
			}
		}
		return newView
	}

	// Gets called from within collectionView:cellForItemAt:. Creates cell models from FRC result objects.
	func createTwitarrCellModel(_ model: Reaction) -> BaseCellModel {
		let cellModel = TwitarrTweetCellModel(withModel: model.sourceTweet)
		cellModel.isInteractive = false
		return cellModel
	}
	
	func createForumPostCellModel(_ model: ForumPost) -> BaseCellModel {
		let cellModel = ForumPostCellModel(withModel: model)
		cellModel.viewController = self
		cellModel.isInteractive = false
		return cellModel
	}
	
	func createFavoriteUserCellModel(_ model: KrakenUser) -> BaseCellModel {
		let cellModel = ProfileAvatarCellModel(user: model)
		cellModel.isInteractive = false
		return cellModel
	}
	
	func createEventCellModel(_ model: Event) -> BaseCellModel {
		let cellModel =  EventCellModel(withModel: model)
		cellModel.isInteractive = false
		return cellModel
	}
	
	func createSongCellModel(_ model: KaraokeFavoriteSong) -> BaseCellModel {
		let cellModel =  KaraokeFavoriteSongCellModel(withModel: model)
		return cellModel
	}
}

// MARK: Karaoke Cell
@objc protocol KaraokeFavoriteSongBindingProtocol: FetchedResultsBindingProtocol {
}

class KaraokeFavoriteSongCellModel: FetchedResultsCellModel, KaraokeFavoriteSongBindingProtocol {
	override class var validReuseIDDict: [String: BaseCollectionViewCell.Type ] { 
		return [ "KaraokeFavoriteSongCell" : KaraokeFavoriteSongCell.self ] 
	}

	init(withModel: KaraokeFavoriteSong) {
		super.init(withModel: withModel, reuse: "KaraokeFavoriteSongCell", bindingWith: KaraokeFavoriteSongBindingProtocol.self)
	}
}

class KaraokeFavoriteSongCell: BaseCollectionViewCell, KaraokeFavoriteSongBindingProtocol {
	private static let cellInfo = [ "KaraokeFavoriteSongCell" : PrototypeCellInfo("KaraokeFavoriteSongCell") ]
	override class var validReuseIDDict: [ String: PrototypeCellInfo] { return KaraokeFavoriteSongCell.cellInfo }

	@IBOutlet weak var songNameLabel: UILabel!
	@IBOutlet weak var artistNameLabel: UILabel!
	@IBOutlet weak var favoriteButton: UIButton!

	var model: NSFetchRequestResult? {
		didSet {
			if let songModel = model as? KaraokeFavoriteSong {
				songNameLabel.text = songModel.songTitle
				artistNameLabel.text = songModel.artistName
				favoriteButton.isSelected = true
			}
		}
	}
}

