//
//  SeamailThreadCell.swift
//  Kraken
//
//  Created by Chall Fry on 5/12/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit
import CoreData

@objc protocol SeamailThreadCellBindingProtocol {
	var isInteractive: Bool { get set }
	var title: String { get set }
	var lastPostTime: Date? { get set }
	var userCount: String { get set }
	var messageCount: NSAttributedString { get set }
	var users: [MaybeUser]? { get set }
}

@objc class SeamailThreadCellModel: FetchedResultsCellModel, SeamailThreadCellBindingProtocol {
	override class var validReuseIDDict: [String: BaseCollectionViewCell.Type ] { 
		return [ "seamailThread" : SeamailThreadCell.self, "seamailLargeThread" : SeamailThreadCell.self ] 
	}

	// If false, the cell doesn't show text links, the like/reply/delete/edit buttons, nor does tapping the 
	// user thumbnail open a user profile panel.
	@objc dynamic var isInteractive: Bool = true
	
	@objc dynamic var title: String = ""
	@objc dynamic var lastPostTime: Date?
	@objc dynamic var userCount: String = ""
	@objc dynamic var messageCount: NSAttributedString = NSAttributedString()
	@objc dynamic var users: [MaybeUser]?
	
	@objc dynamic override var model: NSFetchRequestResult? {
		didSet {
			if let thread = model as? SeamailThread {
				threadModel = thread
			}
		}
	}
	@objc dynamic var threadModel: SeamailThread?
	
	override init(withModel: NSFetchRequestResult?, reuse: String, bindingWith: Protocol = SeamailThreadCellBindingProtocol.self) {
		super.init(withModel: withModel, reuse: reuse, bindingWith: bindingWith)
		if let thread = model as? SeamailThread {
			threadModel = thread
		}
		
		self.tell(self, when: "threadModel.subject") { observer, observed in
			if let thread = observer.threadModel {
				if thread.isPrivateEventType() {
					observer.title = thread.subject.isEmpty ? "<No Subject>" : "Event: \(thread.subject)"
				}
				else {
					observer.title = thread.subject.isEmpty ? "<No Subject>" : thread.subject
				}
			}
			else {
				observer.title = ""
			}
		}?.execute()
		
		self.tell(self, when: "threadModel.lastModTime") { observer, observed in
			observer.lastPostTime = observed.threadModel?.lastModTime
		}?.execute()
		
		self.tell(self, when: "threadModel.participants.count") { observer, observed in
			if let count = observed.threadModel?.participants.count {
				observer.userCount = "\(count) participants"
			}
			else {
				observer.userCount = ""
			}
		}?.execute()

		// Sets PostCountLabel: "X Messages, Y loaded, +Z Pending, W New". Rarely would all 4 clauses appear. 
		self.tell(self, when: "threadModel.messages.count") { observer, observed in
			observer.messageCount = observer.buildPostCountLabel(from: observed.threadModel)
		}?.execute()
		
		self.tell(self, when: "threadModel.participants") { observer, observed in
			observer.users = Array(observed.threadModel?.participants ?? Set<KrakenUser>())
		}?.execute()
	}
	
	// Chooses different cell layouts based on text size
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

	override func cellTapped(dataSource: KrakenDataSource?, vc: UIViewController?) {
		if isInteractive {
			dataSource?.performKrakenSegue(.showSeamailThread, sender: model)
		}
	}
	
	func buildPostCountLabel(from thread: SeamailThread?) -> NSAttributedString {
		let postCountText = NSMutableAttributedString()
		if let currentUser = CurrentUser.shared.loggedInUser, let thread = thread,
				let readCounts = thread.readCounts.first(where: { $0.user.userID == currentUser.userID }) {
			postCountText.append(NSMutableAttributedString(string: 
					"\(readCounts.postCount) message\(readCounts.postCount == 1 ? "" : "s")", 
					attributes: postCountTextAttributes()))
			if thread.messages.count < readCounts.postCount && NetworkGovernor.shared.connectionState != .canConnect {
				postCountText.append(NSAttributedString(string: ", \(thread.messages.count) loaded", 
						attributes: postCountTextAttributes()))
			}				
			if let ops = thread.opsAddingMessages {
				let addCountThisUser = ops.reduce(0) { $0 + ($1.author.username == currentUser.username ? 1 : 0) }
				if addCountThisUser > 0 {
					let pendingText = NSAttributedString(string:" (+\(addCountThisUser) pending)", 
							attributes: pendingPostsAttributes())
					postCountText.append(pendingText)
				}
			}
			if readCounts.postCount > readCounts.readCount {
				let numNewMsgs = readCounts.postCount - readCounts.readCount
				let newText = NSAttributedString(string:" \(numNewMsgs) New", attributes: newFlagAttributes())
				postCountText.append(newText)
			}
		}
		return postCountText
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
}

@objc class SeamailParticipantsCellModel: BaseCellModel, SeamailThreadCellBindingProtocol {
	override class var validReuseIDDict: [String: BaseCollectionViewCell.Type ] { 
		return [ "seamailUserList" : SeamailThreadCell.self ] 
	}

	// If false, the cell doesn't show text links, the like/reply/delete/edit buttons, nor does tapping the 
	// user thumbnail open a user profile panel.
	@objc dynamic var isInteractive: Bool = true
	
	@objc dynamic var title: String = "Participants:"
	@objc dynamic var lastPostTime: Date?
	@objc dynamic var userCount: String = ""
	@objc dynamic var messageCount: NSAttributedString = NSAttributedString()
	@objc dynamic var users: [MaybeUser]?
	
	init(withTitle: String) {
		super.init(bindingWith: SeamailThreadCellBindingProtocol.self)
		title = withTitle
	}
	
	// Chooses different cell layouts based on text size
	override func reuseID(traits: UITraitCollection) -> String {
		return "seamailUserList"
	}
}

@objc class SeamailThreadOpCellModel: FetchedResultsCellModel, SeamailThreadCellBindingProtocol {
	override class var validReuseIDDict: [String: BaseCollectionViewCell.Type ] { 
		return [ "seamailThread" : SeamailThreadCell.self, "seamailLargeThread" : SeamailThreadCell.self ] 
	}

	// If false, the cell doesn't show text links, the like/reply/delete/edit buttons, nor does tapping the 
	// user thumbnail open a user profile panel.
	@objc dynamic var isInteractive: Bool = true
	
	@objc dynamic var title: String = ""
	@objc dynamic var lastPostTime: Date?
	@objc dynamic var userCount: String = ""
	@objc dynamic var messageCount: NSAttributedString = NSAttributedString(string: "1 message")
	@objc dynamic var users: [MaybeUser]?
	
	@objc dynamic override var model: NSFetchRequestResult? {
		didSet {
			if let thread = model as? PostOpSeamailThread {
				threadModel = thread
			}
		}
	}
	@objc dynamic var threadModel: PostOpSeamailThread?
	
	override init(withModel: NSFetchRequestResult?, reuse: String, bindingWith: Protocol = SeamailThreadCellBindingProtocol.self) {
		super.init(withModel: withModel, reuse: reuse, bindingWith: bindingWith)
		if let thread = model as? PostOpSeamailThread {
			threadModel = thread
		}
		
		self.tell(self, when: "threadModel.subject") { observer, observed in
			if let thread = observer.threadModel {
				observer.title = thread.subject.isEmpty ? "<No Subject>" : thread.subject
			}
			else {
				observer.title = ""
			}
		}?.execute()	
				
		self.tell(self, when: "threadModel.recipients.count") { observer, observed in
			if let count = observed.threadModel?.recipients?.count {
				observer.userCount = "\(count) participants"
			}
			else {
				observer.userCount = ""
			}
		}?.execute()
		
		self.tell(self, when: "threadModel.recipients") { observer, observed in
			observer.users = Array(observed.threadModel?.recipients ?? Set<PotentialUser>())
		}?.execute()
	}
	
	// Chooses different cell layouts based on text size
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

	override func cellTapped(dataSource: KrakenDataSource?, vc: UIViewController?) {
		if isInteractive {
			dataSource?.performKrakenSegue(.showSeamailThread, sender: model)
		}
	}
}

@objc class SeamailThreadCell: BaseCollectionViewCell, SeamailThreadCellBindingProtocol {
	@IBOutlet var subjectLabel: UILabel!
	@IBOutlet var lastPostTimeLabel: UILabel!
	@IBOutlet var postCountLabel: UILabel!
	@IBOutlet var participantCountLabel: UILabel!
	@IBOutlet var usersView: UICollectionView!
	@IBOutlet var usersViewHeightConstraint: NSLayoutConstraint!

	var userCellDataSource = KrakenDataSource()
	var userCellSection = FilteringDataSourceSegment()

	private static let cellInfo = [ "seamailThread" : PrototypeCellInfo("SeamailThreadCell"),
			"seamailLargeThread" : PrototypeCellInfo("SeamailLargeThreadCell"),
			"seamailUserList" : PrototypeCellInfo("SeamailUserListCell"),]
	override class var validReuseIDDict: [ String: PrototypeCellInfo] { return SeamailThreadCell.cellInfo }
	
	var isInteractive: Bool = true
	
	@objc dynamic var readCounts: SeamailReadCount?
	@objc dynamic var thread: SeamailThread?
	
	var title: String = "" {
		didSet {
			subjectLabel.text = title			
		}
	}
	
	var lastPostTime: Date? {
		didSet {
			if lastPostTime == Date.distantFuture {
				lastPostTimeLabel.text = "In the near future"
			}
			else if let lastPostTime = lastPostTime {
				lastPostTimeLabel.text = StringUtilities.relativeTimeString(forDate: lastPostTime)
			}
			else {
				lastPostTimeLabel.text = ""
			}
		}
	}
	
	var userCount: String = "" {
		didSet {
			participantCountLabel.text = userCount 
		}
	}

	var messageCount: NSAttributedString = NSAttributedString() {
		didSet {
			postCountLabel.attributedText = messageCount 
		}
	}
	
	var users: [MaybeUser]? {
		didSet {
			userCellSection.allCellModels.removeAllObjects()
			let participantArray = users?.sorted { $0.username < $1.username } ?? []
			for user in participantArray {
				userCellSection.append(createUserCellModel(user.actualUser, name: user.username))
			}
		}
	}
	
	override func awakeFromNib() {
		super.awakeFromNib()
		
		// Font styling
		subjectLabel.styleFor(.body)
		lastPostTimeLabel.styleFor(.body)
		postCountLabel.styleFor(.body)
		participantCountLabel.styleFor(.body)

		// Update the relative post time every 10 seconds.
		NotificationCenter.default.addObserver(forName: RefreshTimers.TenSecUpdateNotification, object: nil,
				queue: nil) { [weak self] notification in
    		if let self = self, let lastPostTime = self.lastPostTime {
	    		self.lastPostTimeLabel.text = StringUtilities.relativeTimeString(forDate: lastPostTime)
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
			if self?.isInteractive == true, let model = model {
				self?.dataSource?.performKrakenSegue(.userProfile_User, sender: model)
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
