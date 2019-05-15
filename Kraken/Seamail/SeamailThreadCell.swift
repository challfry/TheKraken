//
//  SeamailThreadCell.swift
//  Kraken
//
//  Created by Chall Fry on 5/12/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit
import CoreData

class SeamailThreadCell: BaseCollectionViewCell {
	@IBOutlet var subjectLabel: UILabel!
	@IBOutlet var lastPostTime: UILabel!
	@IBOutlet var postCountLabel: UILabel!
	@IBOutlet var participantCountLabel: UILabel!
	@IBOutlet var usersView: UICollectionView!
	@IBOutlet var usersViewHeightConstraint: NSLayoutConstraint!

	var frcDataSource = FetchedResultsControllerDataSource<KrakenUser, SmallUserCell>()

	private static let cellInfo = [ "seamailThread" : PrototypeCellInfo("SeamailThreadCell") ]
	override class var validReuseIDDict: [ String: PrototypeCellInfo] { return SeamailThreadCell.cellInfo }

	private static var prototypeCell: SeamailThreadCell =
		UINib(nibName: "SeamailThreadCell", bundle: nil).instantiate(withOwner: nil, options: nil)[0] as! SeamailThreadCell
	static func makePrototypeCell(for collectionView: UICollectionView, indexPath: IndexPath) -> SeamailThreadCell? {
		let cell = SeamailThreadCell.prototypeCell
		return cell
	}
	
	var threadModel: SeamailThread? {
		didSet {
		
			let fetchRequest = NSFetchRequest<KrakenUser>(entityName: "KrakenUser")
			fetchRequest.predicate = NSPredicate(value: false)
			fetchRequest.sortDescriptors = [ NSSortDescriptor(key: "username", ascending: true)]
			let frc = NSFetchedResultsController(fetchRequest: fetchRequest,
					managedObjectContext: LocalCoreData.shared.mainThreadContext, sectionNameKeyPath: nil, cacheName: nil)
			frcDataSource.setup(collectionView: usersView, frc: frc, vc: viewController, setupCell: setupUserCell, reuseID: "SmallUserCell")
	
			if let thread = threadModel {
				subjectLabel.text = thread.subject
				postCountLabel.text = "\(thread.messages.count) messages"
				participantCountLabel.text = "\(thread.participants.count) participants"
				
				frcDataSource.frc?.fetchRequest.predicate = NSPredicate(format: "ANY seamailParticipant.id == %@", thread.id)

				if let protoCell = SmallUserCell.makePrototypeCell(reuseID: "SmallUserCell"), let protoUser = thread.participants.first {
					setupUserCell(protoCell, protoUser)
					let newSize = protoCell.calculateSize()
					if usersViewHeightConstraint.constant < newSize.height {
						usersViewHeightConstraint.constant = newSize.height
					}
				}
			}
			else {
				frcDataSource.frc?.fetchRequest.predicate = NSPredicate(value: false)
			}
			try? frcDataSource.frc?.performFetch()
		}
	}
	
	override func awakeFromNib() {
		super.awakeFromNib()

		usersView.register(UINib(nibName: "SmallUserCell", bundle: nil), forCellWithReuseIdentifier: "SmallUserCell")
		usersView.dataSource = frcDataSource
		usersView.delegate = frcDataSource
		if let layout = usersView.collectionViewLayout as? UICollectionViewFlowLayout {
			layout.itemSize = CGSize(width: 68, height: 68)
		}
				
	}
	
	func setupUserCell(_ cell:UICollectionViewCell, _ model:KrakenUser) {
		guard let userCell = cell as? SmallUserCell else { return }
		userCell.userModel = model
	}

	override var isSelected: Bool {
		didSet {
			if isSelected {
			}

		}
	}
}


class SmallUserCell: BaseCollectionViewCell {
	@IBOutlet var imageView: UIImageView!
	@IBOutlet var usernameLabel: UILabel!
	
	private static let cellInfo = [ "SmallUserCell" : PrototypeCellInfo("SmallUserCell") ]
	override class var validReuseIDDict: [ String: PrototypeCellInfo] { return SmallUserCell.cellInfo }

	private static var prototypeCell: SmallUserCell =
		UINib(nibName: "SmallUserCell", bundle: nil).instantiate(withOwner: nil, options: nil)[0] as! SmallUserCell
	static func makePrototypeCell(for collectionView: UICollectionView, indexPath: IndexPath) -> SmallUserCell? {
		let cell = SmallUserCell.prototypeCell
		return cell
	}
	
	var userModel: KrakenUser? {
		didSet {
			if let user = userModel {
	    		user.loadUserThumbnail()
	    		user.tell(self, when:"thumbPhoto") { observer, observed in
					observer.imageView.image = observed.thumbPhoto
	    		}?.schedule()
	    		
	    		usernameLabel.text = "@\(user.username)"
			}

		}
	}
	
	override func awakeFromNib() {
		super.awakeFromNib()
		fullWidth = false
	}
	
	override var isSelected: Bool {
		didSet {
			if isSelected {
				viewController?.performSegue(withIdentifier: "UserProfile", sender: userModel?.username)
			}
		}
	}
		
}
