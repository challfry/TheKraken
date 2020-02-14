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
	var gameSegment = FRCDataSourceSegment<GameListFavorite>()

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
		favoritesDataSource.append(segment: gameSegment)

		CurrentUser.shared.tell(self, when: "loggedInUser") { observer, observed in        		
			if let currentUser = observed.loggedInUser {
				observer.favoritesDataSource.register(with: observer.collectionView, viewController: self)

				// Register the nib for the section header view
				observer.favoritesDataSource.registerSectionHeaderClass(newClass: ScrapbookSectionHeaderView.self)

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
				observer.gameSegment.activate(predicate: NSPredicate(value: true), 
						sort: [ NSSortDescriptor(key: "gameName", ascending: true)], 
						cellModelFactory: observer.createGameCellModel)
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
		super.viewWillAppear(animated)
		favoritesDataSource.enableAnimations = true
	}
	
// MARK: Cell Factories
	
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
	
	func createGameCellModel(_ fav: GameListFavorite) -> BaseCellModel {
		let cellModel = BoardGameCellModel()
		GamesDataManager.shared.loadGamesFile {
			cellModel.model = GamesDataManager.shared.findGame(named: fav.gameName)
		}
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

class ScrapbookSectionHeaderView: BaseCollectionSupplementaryView {
	@IBOutlet var sectionLabel: UILabel!
	
	override class var nib: UINib? {
		return  UINib(nibName: "ScrapbookSectionHeaderView", bundle: nil)
	}
	override class var reuseID: String { return "ScrapbookSectionHeaderView" }

	override func awakeFromNib() {
		super.awakeFromNib()

		// Font styling
		sectionLabel.styleFor(.body)
	}

	override func setup(cellModel: BaseCellModel) {
		switch cellModel {
		case is TwitarrTweetCellModel: sectionLabel.text = "Favorite Twitarr Posts"
		case is ForumsThreadCellModel: sectionLabel.text = "Favorite Forums"
		case is ForumPostCellModel: sectionLabel.text = "Favorite Forum Posts"
		case is EventCellModel: sectionLabel.text = "Favorite Events"
		case is ProfileAvatarCellModel: sectionLabel.text = "Favorite Users"
		case is KaraokeFavoriteSongCellModel: sectionLabel.text = "Favorite Karaoke Songs"
		case is BoardGameCellModel: sectionLabel.text = "Favorite Board Games"
		default: sectionLabel.text = "Favorites"
		}
	}
}
