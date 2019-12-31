//
//  ForumsThreadCell.swift
//  Kraken
//
//  Created by Chall Fry on 12/3/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit

@objc protocol ForumsThreadBindingProtocol: FetchedResultsBindingProtocol {
	var isInteractive: Bool { get set }
	var thread: ForumThread? { get set }
	var readCount: ForumReadCount? { get set }
}

@objc class ForumsThreadCellModel: FetchedResultsCellModel, ForumsThreadBindingProtocol {
	override class var validReuseIDDict: [String: BaseCollectionViewCell.Type ] { 
		return [ "ForumsThreadCell" : ForumsThreadCell.self ] 
	}
	
	@objc dynamic var thread: ForumThread?
	@objc dynamic var readCount: ForumReadCount?			// The current user's read count object for this thread.

	// If false, the cell doesn't show text links and isn't selectable.
	@objc dynamic var isInteractive: Bool = true
	
	init(with model: ForumThread) {
		super.init(withModel: model, reuse: "ForumsThreadCell", bindingWith: ForumsThreadBindingProtocol.self)
		thread = model
		
		CurrentUser.shared.tell(self, when: "loggedInUser") { observer, observed in 
			if let curUsername = observed.loggedInUser?.username {
				observer.readCount = observer.thread?.readCount.first { $0.user.username == curUsername }
			}
			else {
				observer.readCount = nil
			}
		}?.execute()
		
	}
	
	init(with model: ForumReadCount) {
		super.init(withModel: model, reuse: "ForumsThreadCell", bindingWith: ForumsThreadBindingProtocol.self)
		readCount = model
		thread = model.forumThread

		CurrentUser.shared.tell(self, when: "loggedInUser") { observer, observed in 
			if let curUsername = observed.loggedInUser?.username {
				observer.readCount = observer.thread?.readCount.first { $0.user.username == curUsername }
			}
			else {
				observer.readCount = nil
			}
		}
	}
}


class ForumsThreadCell: BaseCollectionViewCell, ForumsThreadBindingProtocol {
	private static let cellInfo = [ "ForumsThreadCell" : PrototypeCellInfo("ForumsThreadCell") ]
	override class var validReuseIDDict: [ String: PrototypeCellInfo] { return ForumsThreadCell.cellInfo }
	
	@IBOutlet weak var subjectLabel: UILabel!
	@IBOutlet weak var postCountLabel: UILabel!
	@IBOutlet weak var lastPosterLabel: UILabel!
	@IBOutlet weak var lastPostTimeLabel: UILabel!
	@IBOutlet weak var stickyIcon: UIImageView!
	@IBOutlet weak var lockedIcon: UIImageView!
	@IBOutlet weak var favoriteButton: UIButton!
	
	var isInteractive: Bool = true
	
	override func awakeFromNib() {
		super.awakeFromNib()
		setupGestureRecognizer()
			
		// Font styling
		subjectLabel.styleFor(.body)
		lastPosterLabel.styleFor(.body)
		postCountLabel.styleFor(.body)
		lastPostTimeLabel.styleFor(.body)

		// Update the relative post time every 10 seconds.
		NotificationCenter.default.addObserver(forName: RefreshTimers.TenSecUpdateNotification, object: nil,
				queue: nil) { [weak self] notification in
			if let self = self {
				self.updatePostTime()
			}
		}
	}
	
	var model: NSFetchRequestResult? 

    var thread: ForumThread? {
		didSet {
    		clearObservations()
			if let thread = thread {
				addObservation(thread.tell(self, when: "subject") { observer, observed in
					observer.subjectLabel.text = observed.subject
				}?.execute())

				addObservation(thread.tell(self, when: "postCount") { observer, observed in
					if observed.postCount == 1 {
						observer.postCountLabel.text = "1 post"
					}
					else {
						observer.postCountLabel.text = "\(observed.postCount) posts"
					}
				}?.execute())

				addObservation(thread.tell(self, when: "lastPoster.displayName") { observer, observed in
					observer.lastPosterLabel.text = "Last Post: \(observed.lastPoster.displayName)"
				}?.execute())
				
				addObservation(thread.tell(self, when: "locked") { observer, observed in
					observer.lockedIcon.isHidden = !observed.locked
				}?.execute())
				
				addObservation(thread.tell(self, when: "sticky") { observer, observed in
					observer.stickyIcon.isHidden = !observed.sticky
				}?.execute())
								
				updatePostTime()
			}
		}
	}
	
	var readCountObservation: EBNObservation?
	var readCount: ForumReadCount? {
		didSet {
			if let rc = readCount {
				if let rco = readCountObservation {
					rco.stopObservations()
				}
				readCountObservation = rc.tell(self, when: "isFavorite") { observer, observed in
					observer.favoriteButton.isSelected = observed.isFavorite
				}?.execute()
			}
			else {
				favoriteButton.isSelected = false
			}
		}
	}
	
	func updatePostTime() {
		if let thread = thread {
			let postDate: TimeInterval = TimeInterval(thread.lastPostTime) / 1000.0
			self.lastPostTimeLabel.text = StringUtilities.relativeTimeString(forDate: Date(timeIntervalSince1970: postDate))
		}
	}
	
	var highlightAnimation: UIViewPropertyAnimator?
	override var isHighlighted: Bool {
		didSet {
			if !isInteractive { return }
			if let oldAnim = highlightAnimation {
				oldAnim.stopAnimation(true)
			}
			let anim = UIViewPropertyAnimator(duration: 0.2, curve: .easeInOut) {
				self.contentView.backgroundColor = self.isHighlighted ? UIColor(named: "Cell Background Selected") : 
						UIColor(named: "Cell Background")
			}
			anim.isUserInteractionEnabled = true
			anim.isInterruptible = true
			anim.startAnimation()
			highlightAnimation = anim
		}
	}
	
	override var isSelected: Bool {
		didSet {
			if isSelected, isInteractive, let threadModel = thread {
				dataSource?.performKrakenSegue(.showForumThread, sender: threadModel)
			}
		}
	}
	
	@IBAction func favoriteButtonHit() {
 		guard isInteractive else { return }
		if let thread = thread {
			// FIXME: Still not sure what to do in the case where the user, once logged in, already likes the thread.
			// When nobody is logged in we still enable and show the Like button. Tapping it opens the login panel, 
			// with a successAction that performs the like action.
			if CurrentUser.shared.isLoggedIn() {
				thread.setForumFavoriteStatus(to: !favoriteButton.isSelected)
			}
			else if let vc = viewController as? BaseCollectionViewController {
				let seguePackage = LoginSegueWithAction(promptText: "In order to like this forum thread, you'll need to log in first.",
						loginSuccessAction: { thread.setForumFavoriteStatus(to: !self.favoriteButton.isSelected) }, 
						loginFailureAction: nil)
				vc.performKrakenSegue(.modalLogin, sender: seguePackage)
			}
		}
	}
	
	override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
		// need to call super if it's not our recognizer
		if gestureRecognizer != customGR {
			return super.gestureRecognizerShouldBegin(gestureRecognizer)
		}
		
		let hitPoint = gestureRecognizer.location(in: favoriteButton)
		if favoriteButton.point(inside:hitPoint, with: nil) {
			return false
		}		
		
		return super.gestureRecognizerShouldBegin(gestureRecognizer)
	}
}
