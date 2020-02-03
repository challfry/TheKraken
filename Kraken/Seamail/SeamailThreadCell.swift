//
//  SeamailThreadCell.swift
//  Kraken
//
//  Created by Chall Fry on 5/12/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit
import CoreData

@objc protocol SeamailThreadCellBindingProtocol: FetchedResultsBindingProtocol {
	var isInteractive: Bool { get set }
}

@objc class SeamailThreadCellModel: FetchedResultsCellModel, SeamailThreadCellBindingProtocol {
	override class var validReuseIDDict: [String: BaseCollectionViewCell.Type ] { 
		return [ "seamailThread" : SeamailThreadCell.self, "seamailLargeThread" : SeamailThreadCell.self ] 
	}

	// If false, the cell doesn't show text links, the like/reply/delete/edit buttons, nor does tapping the 
	// user thumbnail open a user profile panel.
	@objc dynamic var isInteractive: Bool = true
	
	override init(withModel: NSFetchRequestResult?, reuse: String, bindingWith: Protocol = SeamailThreadCellBindingProtocol.self) {
		super.init(withModel: withModel, reuse: reuse, bindingWith: bindingWith)
	}
	
	override func reuseID(traits: UITraitCollection) -> String {
		let currentTextSize = traits.preferredContentSizeCategory
		if currentTextSize > UIContentSizeCategory.accessibilityLarge {
			return "seamailLargeThread"
		}

		if let threadModel = model as? SeamailThread {
			let sizingFont = UIFont.preferredFont(forTextStyle: .body)
			let subjectRect = threadModel.subject.boundingRect(with: CGSize(width: 1000, height: 100), 
					options: NSStringDrawingOptions.usesLineFragmentOrigin, 
					attributes: [NSAttributedString.Key.font: sizingFont], context: nil)
			if subjectRect.size.width < 280 {
				return "seamailThread"
			}
		}
		return "seamailLargeThread"
	}

	override func cellTapped(dataSource: KrakenDataSource?) {
		if isInteractive {
			dataSource?.performKrakenSegue(.showSeamailThread, sender: model)
		}
	}
	
}

class SeamailThreadCell: BaseCollectionViewCell, SeamailThreadCellBindingProtocol {
	@IBOutlet var subjectLabel: UILabel!
	@IBOutlet var lastPostTime: UILabel!
	@IBOutlet var postCountLabel: UILabel!
	@IBOutlet var participantCountLabel: UILabel!
	@IBOutlet var usersView: UICollectionView!
	@IBOutlet var usersViewHeightConstraint: NSLayoutConstraint!

	var userCellDataSource = KrakenDataSource()
	var userCellSection = FilteringDataSourceSegment()

	private static let cellInfo = [ "seamailThread" : PrototypeCellInfo("SeamailThreadCell"),
			"seamailLargeThread" : PrototypeCellInfo("SeamailLargeThreadCell"),]
	override class var validReuseIDDict: [ String: PrototypeCellInfo] { return SeamailThreadCell.cellInfo }
	
	var isInteractive: Bool = true

    var model: NSFetchRequestResult? {
		didSet {
			clearObservations()
			
			// Set the height of the in-cell CollectionView to be at least as tall as its cells.
			if let protoUser = CurrentUser.shared.loggedInUser {
				let protoCellModel = SmallUserCellModel(withModel: protoUser, reuse: "SmallUserCell")
				let protoCell = protoCellModel.makePrototypeCell(for: usersView, indexPath: IndexPath(row: 0, section: 0)) as? SmallUserCell
				if let newSize = protoCell?.calculateSize(), usersViewHeightConstraint.constant < newSize.height {
					usersViewHeightConstraint.constant = newSize.height
				}
			}

			userCellSection.allCellModels.removeAllObjects()
			if let thread = model as? SeamailThread {
				subjectLabel.text = thread.subject
				
				addObservation(thread.tell(self, when: ["messageCount", "messages.count", "opsAddingMessages.count", "fullyReadBy.count"]) { observer, observed in
					let postCountText = NSMutableAttributedString(string: "\(observed.messageCount) message\(observed.messageCount == 1 ? "" : "s")", 
							attributes: observer.postCountTextAttributes())
					if observed.messages.count < observed.messageCount {
						postCountText.append(NSAttributedString(string: ", \(observed.messages.count) loaded", 
								attributes: observer.postCountTextAttributes()))
					}
					if let currentUser = CurrentUser.shared.loggedInUser {
						if let ops = observed.opsAddingMessages {
							let addCountThisUser = ops.reduce(0) { $0 + ($1.author.username == currentUser.username ? 1 : 0) }
							if addCountThisUser > 0 {
								let pendingText = NSAttributedString(string:" (+\(addCountThisUser) pending)", 
										attributes: observer.pendingPostsAttributes())
								postCountText.append(pendingText)
							}
						}
						if !observed.fullyReadBy.contains(currentUser) {
							let newText = NSAttributedString(string:" New", attributes: observer.newFlagAttributes())
							postCountText.append(newText)
						}
					}
					observer.postCountLabel.attributedText = postCountText
				}?.execute())
				
				addObservation(thread.tell(self, when:"participants.count") { observer, observed in
					observer.participantCountLabel.text = "\(observed.participants.count) participants"
				}?.execute())
				
				addObservation(thread.tell(self, when:"timestamp") { observer, observed in
	    			let postDate: TimeInterval = TimeInterval(observed.timestamp) / 1000.0
	    			observer.lastPostTime.text = StringUtilities.relativeTimeString(forDate: Date(timeIntervalSince1970: postDate))
				}?.execute())
	    		
	    		let participantArray = thread.participants.sorted { $0.username < $1.username }
	    		for user in participantArray {
	    			userCellSection.append(createUserCellModel(user, name: user.username))
	    		}
	    		
	    		// Accessibility
	    		let groupElem = UIAccessibilityElement(accessibilityContainer: self)
	    		groupElem.isAccessibilityElement = true
	    		groupElem.accessibilityLabel = """
	    				Thread: \(thread.subject) Last Post: \(lastPostTime.text ?? "") \(postCountLabel.text ?? "")  \(participantCountLabel.text ?? "") 
	    				"""
				groupElem.accessibilityFrameInContainerSpace = subjectLabel.frame.union(postCountLabel.frame)
				accessibilityElements = [groupElem, usersView!]
				
			}
			else if let postOpThread = model as? PostOpSeamailThread {
				// A new thread the user created, waiting to be uploaded to the server
    			lastPostTime.text = "In the near future"
				postCountLabel.text = "1 message"			// A yet-to-be-posted thread can only have its initial msg.

				addObservation(postOpThread.tell(self, when:"subject") { observer, observed in
					observer.subjectLabel.text = observed.subject
				}?.execute())
				
				addObservation(postOpThread.tell(self, when:"recipients.count") { observer, observed in
					var participantCountStr = "unknown participants"
					if let participantCount = observed.recipients?.count {
						// Why +1? The PostOp doesn't include the sender in the userlist.
						participantCountStr = "\(participantCount + 1) participants"
					}
					observer.participantCountLabel.text = participantCountStr
				}?.execute())

				if let loggedInUser = CurrentUser.shared.loggedInUser {
					userCellSection.append(createUserCellModel(loggedInUser, name: loggedInUser.username))
				}
				if let participantArray = postOpThread.recipients?.sorted(by: { $0.username < $1.username }) {
		    		for user in participantArray {
		    			userCellSection.allCellModels.add(createUserCellModel(user.actualUser, name: user.username))
	    			}
				}
			}
		}
	}
	
	func postCountTextAttributes() -> [ NSAttributedString.Key : Any ] {
		let metrics = UIFontMetrics(forTextStyle: .body)
		let baseFont = UIFont.systemFont(ofSize: 15.0)
		let font = metrics.scaledFont(for: baseFont)
		let result: [NSAttributedString.Key : Any] = [ .font : font as Any,  .foregroundColor : UIColor(named: "Kraken Secondary Text") as Any ]
		return result
	}
	
	func pendingPostsAttributes() -> [ NSAttributedString.Key : Any ] {
		let metrics = UIFontMetrics(forTextStyle: .body)
		let baseFont = UIFont.systemFont(ofSize: 15.0)
		let font = metrics.scaledFont(for: baseFont)
		let result: [NSAttributedString.Key : Any] = [ .font : font as Any,  .foregroundColor : UIColor(named: "Kraken Secondary Text") as Any ]
		return result
	}
	
	func newFlagAttributes() -> [ NSAttributedString.Key : Any ] {
		let metrics = UIFontMetrics(forTextStyle: .body)
		let baseFont = UIFont.systemFont(ofSize: 15.0)
		let font = metrics.scaledFont(for: baseFont)
		let result: [NSAttributedString.Key : Any] = [ .font : font as Any,  .foregroundColor : UIColor(named: "Red Alert Text") as Any ]
		return result
	}
	
	override func awakeFromNib() {
		super.awakeFromNib()
		
		// Font styling
		subjectLabel.styleFor(.body)
		lastPostTime.styleFor(.body)
		postCountLabel.styleFor(.body)
		participantCountLabel.styleFor(.body)

		// Update the relative post time every 10 seconds.
		NotificationCenter.default.addObserver(forName: RefreshTimers.TenSecUpdateNotification, object: nil,
				queue: nil) { [weak self] notification in
    		if let self = self, let thread = self.model as? SeamailThread, !thread.isDeleted {
	    		let postDate: TimeInterval = TimeInterval(thread.timestamp) / 1000.0
	    		self.lastPostTime.text = StringUtilities.relativeTimeString(forDate: Date(timeIntervalSince1970: postDate))
			}
		}

		userCellDataSource.register(with: usersView, viewController: viewController as? BaseCollectionViewController)
		userCellDataSource.append(segment: userCellSection)
		usersView.backgroundColor = UIColor.clear
		if let layout = usersView.collectionViewLayout as? UICollectionViewFlowLayout {
			layout.itemSize = CGSize(width: 68, height: 68)
		}
				
		usersView.accessibilityLabel = "Participant List"	
	}
	
	func createUserCellModel(_ model:KrakenUser?, name: String) -> BaseCellModel {
		let cellModel = SmallUserCellModel(withModel: model, reuse: "SmallUserCell")
		cellModel.shouldBeVisible = true
		cellModel.username = name
		cellModel.selectionCallback = { [weak self] in
			if self?.isInteractive == true {
				self?.dataSource?.performKrakenSegue(.userProfile, sender: name)
			}
		}
		return cellModel
	}
    
	override var isHighlighted: Bool {
		didSet {
			if !isInteractive { return }
			standardHighlightHandler()
		}
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
