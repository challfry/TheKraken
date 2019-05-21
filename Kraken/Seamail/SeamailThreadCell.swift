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
			fetchRequest.fetchBatchSize = 30
			let frc = NSFetchedResultsController(fetchRequest: fetchRequest,
					managedObjectContext: LocalCoreData.shared.mainThreadContext, sectionNameKeyPath: nil, cacheName: nil)
			frcDataSource.setup(collectionView: usersView, frc: frc, setupCell: setupUserCell, reuseID: "SmallUserCell")
	
			if let thread = threadModel {
				subjectLabel.text = thread.subject
				postCountLabel.text = "\(thread.messages.count) messages"
				participantCountLabel.text = "\(thread.participants.count) participants"
	    		let postDate: TimeInterval = TimeInterval(thread.timestamp) / 1000.0
	    		lastPostTime.text = StringUtilities.relativeTimeString(forDate: Date(timeIntervalSince1970: postDate))
				
				frcDataSource.frc?.fetchRequest.predicate = NSPredicate(format: "ANY seamailParticipant.id == %@", thread.id)

				// Set the height of the in-cell CollectionView to be at least as tall as its cells.
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
		usersView.backgroundColor = UIColor.clear
		if let layout = usersView.collectionViewLayout as? UICollectionViewFlowLayout {
			layout.itemSize = CGSize(width: 68, height: 68)
		}
		
		setupGestureRecognizer()		
	}
	
	func setupUserCell(_ cell:UICollectionViewCell, _ model:KrakenUser) {
		guard let userCell = cell as? SmallUserCell else { return }
		userCell.userModel = model
		userCell.viewController	= viewController
	}

	override var isSelected: Bool {
		didSet {
			if isSelected {
				viewController?.performSegue(withIdentifier: "ShowSeamailThread", sender: threadModel)
			}
		}
	}
	
	var highlightAnimation: UIViewPropertyAnimator?
	override var isHighlighted: Bool {
		didSet {
			if let oldAnim = highlightAnimation {
				oldAnim.stopAnimation(true)
			}
			let anim = UIViewPropertyAnimator(duration: 0.2, curve: .easeInOut) {
				self.contentView.backgroundColor = self.isHighlighted ? UIColor(white:0.97, alpha: 1.0) : UIColor.white
			}
			anim.isUserInteractionEnabled = true
			anim.isInterruptible = true
			anim.startAnimation()
			highlightAnimation = anim
		}
	}
		
	var customGR: UILongPressGestureRecognizer?
}

extension SeamailThreadCell: UIGestureRecognizerDelegate {

	func setupGestureRecognizer() {	
		let tapper = UILongPressGestureRecognizer(target: self, action: #selector(SeamailThreadCell.usersViewTapped))
		tapper.minimumPressDuration = 0.2
		tapper.numberOfTouchesRequired = 1
		tapper.numberOfTapsRequired = 0
		tapper.allowableMovement = 10.0
		tapper.delegate = self
		tapper.name = "SeamailThreadCell Long Press"
		addGestureRecognizer(tapper)
		customGR = tapper
	}

	override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
		// need to call super if it's not our recognizer
		if gestureRecognizer != customGR {
			return super.gestureRecognizerShouldBegin(gestureRecognizer)
		}
		let hitPoint = gestureRecognizer.location(in: self)
		if !point(inside:hitPoint, with: nil) {
			return false
		}
		let usersViewPoint = gestureRecognizer.location(in: usersView)
		if let _ = usersView.indexPathForItem(at: usersViewPoint) {
			return false
		}
		
		return true
	}

	@objc func usersViewTapped(_ sender: UILongPressGestureRecognizer) {
		if sender.state == .began {
			isHighlighted = point(inside:sender.location(in: self), with: nil)
		}
		else if sender.state == .changed {
			isHighlighted = point(inside:sender.location(in: self), with: nil)
		}
		else if sender.state == .ended {
			if (isHighlighted) {
				isSelected = true
			}
			isHighlighted = false
		}
		else if sender.state == .cancelled {
			isHighlighted = false	
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
		
	var highlightAnimation: UIViewPropertyAnimator?
	override var isHighlighted: Bool {
		didSet {
			if let oldAnim = highlightAnimation {
				oldAnim.stopAnimation(true)
			}
			let anim = UIViewPropertyAnimator(duration: 0.2, curve: .easeInOut) {
				self.contentView.backgroundColor = self.isHighlighted ? UIColor(white:0.9, alpha: 1.0) : UIColor.white
			}
			anim.isUserInteractionEnabled = true
			anim.isInterruptible = true
			anim.startAnimation()
			highlightAnimation = anim
		}
	}
}
