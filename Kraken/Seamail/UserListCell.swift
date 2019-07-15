//
//  UserListCell.swift
//  Kraken
//
//  Created by Chall Fry on 7/9/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit

// For no-network conditions, users have to be able to create Seamail message threads without asking the server
// whether participant names are valid Twitarr users. We try to use local CD info, but that's incomplete.
// So, while being constructed, the participants in a thread are PossibleKrakenUsers.
class PossibleKrakenUser : NSObject, Comparable {
	var username: String = ""
	var user: KrakenUser?
	var canBeRemoved: Bool = false				// If true, shows delete icon
	
	static func < (lhs: PossibleKrakenUser, rhs: PossibleKrakenUser) -> Bool {
		return lhs.username < rhs.username
	}
	
	static func == (lhs: PossibleKrakenUser, rhs: PossibleKrakenUser) -> Bool {
		return lhs.username == rhs.username
	}
	
	public override func isEqual(_ other: (Any)?) -> Bool {
		guard let other = other as? PossibleKrakenUser else { return false }
		return self.username == other.username
	}

	public override var hash: Int {
		var hasher = Hasher()
		hasher.combine(username)
		return hasher.finalize()
	}
	
	init(user: KrakenUser) {
		self.user = user
		username = user.username
		super.init()
	}
	
	init(username: String) {
		self.username = username
		super.init()
	}
	
	override var debugDescription: String {
		var result = "PossibleKrakenUser hash:\(hash)"
		if let user = user {
			result.append("Real user: \(user.username)")
		}
		else if !username.isEmpty {
			result.append("Unknown user: \(username)")
		}
		else {
			result.append("No user attached")
		}
		return result
	}
	
}

@objc protocol UserListCellBindingProtocol {
	var title: String { get set }
	var source: String { get set }
	var users: Set<PossibleKrakenUser> { get set }
	var selectionCallback: ((PossibleKrakenUser, Bool) -> Void)? { get set }
}

@objc class UserListCoreDataCellModel: BaseCellModel, UserListCellBindingProtocol, NSFetchedResultsControllerDelegate {
	override class var validReuseIDDict: [String: BaseCollectionViewCell.Type ] { return [ "UserListCell" : UserListCell.self ] }

	dynamic var title: String
	dynamic var source: String
	dynamic var users: Set<PossibleKrakenUser> = Set()
	dynamic var selectionCallback: ((PossibleKrakenUser, Bool) -> Void)?
	
	// If UsePredicate is true, users will be set automatically by the FRC; be sure to actually give it a predicate.
	// If it's false, you have to give users a value yourself.
	var usePredicate: Bool = false {
		didSet {
			if usePredicate {
				controllerDidChangeContent(fetchedResults as! NSFetchedResultsController<NSFetchRequestResult>)
			}
		}
	}
	
	var fetchedResults: NSFetchedResultsController<KrakenUser>
	var predicate: NSPredicate? {
		didSet {
			let newPredicate = predicate ?? NSPredicate(value: false)
			fetchedResults.fetchRequest.predicate = newPredicate
			try? fetchedResults.performFetch()
			controllerDidChangeContent(fetchedResults as! NSFetchedResultsController<NSFetchRequestResult>)
		}
	}
	
	init(withTitle: String) {
		title = withTitle
		source = ""
 
 		let fetchRequest = NSFetchRequest<KrakenUser>(entityName: "KrakenUser")
		fetchRequest.predicate = NSPredicate(value: false)
		fetchRequest.sortDescriptors = [ NSSortDescriptor(key: "username", ascending: true)]
		fetchRequest.fetchBatchSize = 30
		fetchedResults = NSFetchedResultsController(fetchRequest: fetchRequest,
				managedObjectContext: LocalCoreData.shared.mainThreadContext, sectionNameKeyPath: nil, cacheName: nil)

		super.init(bindingWith: UserListCellBindingProtocol.self)
		
		try? fetchedResults.performFetch()
	}
	
	func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
		if usePredicate {
			users.removeAll()
			if let objects = fetchedResults.fetchedObjects {
				for user in objects {
					if user.username != CurrentUser.shared.loggedInUser?.username {
						users.insert(PossibleKrakenUser(user: user))
					}
				}
			}
		}
	}
}

class UserListCell: BaseCollectionViewCell, UserListCellBindingProtocol {
	@IBOutlet var titleLabel: UILabel!
	@IBOutlet var sourceLabel: UILabel!
	@IBOutlet var userCollection: UICollectionView!
	@IBOutlet var userCollectionHeightConstraint: NSLayoutConstraint!
	
	private static let cellInfo = [ "UserListCell" : PrototypeCellInfo("UserListCell") ]
	override class var validReuseIDDict: [ String: PrototypeCellInfo] { return UserListCell.cellInfo }

	var selectionCallback: ((PossibleKrakenUser, Bool) -> Void)?
	var title: String = "" {
		didSet {
			titleLabel.text = title
		}
	}
	var source: String = "" {
		didSet {
			sourceLabel.text = source
		}
	}

	var users: Set<PossibleKrakenUser> = Set() {
		didSet {
			// Any names in allCellModels that aren't in the new set of users get deleted. Don't delete everything
			// and re-insert, as the models probably have cells attached.
			let userNames = Set(users.map { $0.username })
			for index in (0..<userSection.allCellModels.count).reversed() {
				if let userInChat = (userSection.allCellModels[index] as? SmallUserCellModel)?.username, 
						!userNames.contains(userInChat) {
					userSection.delete(at: index)
				}
			}
			
			var sortedUsers = Array(users)
			sortedUsers.sort()
		
			// Why a while loop? We're mutating allCellModels, inserting elements.
			var newIndex = 0
			var existingIndex = 0
			while existingIndex < userSection.allCellModels.count, newIndex < sortedUsers.count {
				if let existingCellModel = userSection.allCellModels[existingIndex] as? SmallUserCellModel,
						let userInChat = existingCellModel.username {
					while newIndex < sortedUsers.count, sortedUsers[newIndex].username < userInChat {
						let cellModel = createUserCellModel(sortedUsers[newIndex])
						userSection.insert(cell: cellModel, at: existingIndex)
						newIndex += 1
						existingIndex += 1
					}
					if sortedUsers[newIndex].username == userInChat {
						newIndex += 1
					}
					existingIndex += 1
				}
			}
			while newIndex < sortedUsers.count {
				let cellModel = createUserCellModel(sortedUsers[newIndex])
				userSection.append(cell: cellModel)
				newIndex += 1
			}
			
			//
//			CollectionViewLog.debug("User section: ", ["entries" : self.userSection.allCellModels])
//			CollectionViewLog.debug("Users: ", ["users" : self.users])
		}
	}

	var userListDataSource = FilteringDataSource()
	var userSection = FilteringDataSourceSection()

	override func awakeFromNib() {
        super.awakeFromNib()
		userListDataSource.enableAnimations = true

		userListDataSource.register(with: userCollection, viewController: viewController as? BaseCollectionViewController)
		userListDataSource.appendSection(section: userSection)
		if let layout = userCollection.collectionViewLayout as? UICollectionViewFlowLayout {
			layout.itemSize = CGSize(width: 68, height: 68)
		}
 
		// Set the height of the in-cell CollectionView to be at least as tall as its cells.
		if userCollectionHeightConstraint.constant < 70, let protoUser = CurrentUser.shared.loggedInUser {
			let protoCellModel = SmallUserCellModel(withModel: protoUser, reuse: "SmallUserCell")
			let protoCell = protoCellModel.makePrototypeCell(for: userCollection, indexPath: IndexPath(row: 0, section: 0)) as? SmallUserCell
			if let newSize = protoCell?.calculateSize() {
				userCollectionHeightConstraint.constant = newSize.height + 2
			}
		}

		setupGestureRecognizer()		
   }

	func createUserCellModel(_ model:PossibleKrakenUser) -> SmallUserCellModel {
		let cellModel = SmallUserCellModel(withModel: nil, reuse: "SmallUserCell")
		if let newUserToChat = model.user {
			cellModel.model = newUserToChat
		}
		else {
			cellModel.username = model.username
		}
		cellModel.shouldBeVisible = true
		cellModel.showDeleteIcon = model.canBeRemoved
		cellModel.selectionCallback = { [weak self] isSelected in
			self?.selectionCallback?(model, isSelected)
		}
		return cellModel
	}

}

