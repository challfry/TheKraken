//
//  LFGCell.swift
//  Kraken
//
//  Created by Chall Fry on 12/5/22.
//  Copyright © 2022 Chall Fry. All rights reserved.
//

import Foundation
import UIKit

@objc protocol LFGCellBindingProtocol: FetchedResultsBindingProtocol {
}

@objc class LFGCellModel: FetchedResultsCellModel, LFGCellBindingProtocol {
	override class var validReuseIDDict: [String: BaseCollectionViewCell.Type ] { return [ "LFGCell" : LFGCell.self ] }
		
	override init(withModel: NSFetchRequestResult?, reuse: String, bindingWith: Protocol = LFGCellBindingProtocol.self)
	{
		super.init(withModel: withModel, reuse: reuse, bindingWith: bindingWith)
	}
	
	override func cellTapped(dataSource: KrakenDataSource?, vc: UIViewController?) {
		dataSource?.performKrakenSegue(.showSeamailThread, sender: model)
	}
}

class LFGCell: BaseCollectionViewCell, LFGCellBindingProtocol {
	@IBOutlet var titleLabel: UILabel!
	@IBOutlet var cancelLabel: UILabel!
	@IBOutlet var timeLabel: UILabel!
	@IBOutlet var ownerLabel: UILabel!
	@IBOutlet var attendeesLabel: UILabel!
	@IBOutlet var categoryLabel: UILabel!
	@IBOutlet var numPostsLabel: UILabel!
	
	private static let cellInfo = [ "LFGCell" : PrototypeCellInfo("LFGCell") ]
	override class var validReuseIDDict: [ String: PrototypeCellInfo] { return LFGCell.cellInfo }
	
	dynamic var readCountObject: SeamailReadCount?
			
	var model: NSFetchRequestResult? {
		didSet {
			clearObservations()

			if let lfg = model as? SeamailThread {
	    		addObservation(lfg.tell(self, when: "subject") { observer, observed in
					observer.titleLabel.text = observed.subject
					observer.cellSizeChanged()
	    		}?.execute())
	    		addObservation(lfg.tell(self, when: "cancelled") { observer, observed in
					observer.cancelLabel.isHidden = !observed.cancelled
					observer.cellSizeChanged()
	    		}?.execute())
	    		addObservation(lfg.tell(self, when: ["startTime", "endTime"]) { observer, observed in
					observer.timeLabel.attributedText = observer.makeTimeString()
					observer.cellSizeChanged()
	    		}?.execute())

	    		addObservation(lfg.tell(self, when: "owner") { observer, observed in
					observer.ownerLabel.text = "by @\(observed.owner?.username ?? "unknown")"
	    		}?.execute())
	    		addObservation(lfg.tell(self, when: ["participantCount", "maxParticipants"]) { observer, observed in
					observer.attendeesLabel.text = "\(observed.participantCount)/\(observed.maxParticipants) attendees"
	    		}?.execute())

	    		addObservation(lfg.tell(self, when: ["fezType"]) { observer, observed in
					observer.categoryLabel.text = "\(observed.fezType)"
	    		}?.execute())
	    		lfg.getReadCounts { readCounts in
	    			guard let readCounts = readCounts else { 
						self.numPostsLabel.text = ""
	    				return 
					}
	    			self.readCountObject = readCounts
					self.addObservation(self.readCountObject?.tell(self, when: ["postCount", "viewedCount"]) { observer, observed in
						if let currentUser = CurrentUser.shared.loggedInUser, 
								observed.thread.participants.contains(where: { $0.userID == currentUser.userID }) {
							observer.numPostsLabel.attributedText = observer.buildPostCountLabel(from: lfg)
						}
						else {
							observer.numPostsLabel.text = ""
						}
					}?.execute())
				}
			}
			else if model == nil {
				titleLabel.text = ""
			}
		}
	}
	
	func makeTimeString() -> NSAttributedString {
		if let lfg = model as? SeamailThread, let startTime = lfg.startTime {
			return StringUtilities.eventTimeString(startTime: startTime, endTime: lfg.endTime, baseFont: timeLabel.font)
		}
		return NSAttributedString()
	}
	
	func buildPostCountLabel(from thread: SeamailThread) -> NSAttributedString {
		let postCountText = NSMutableAttributedString()
		if let currentUser = CurrentUser.shared.loggedInUser,
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
			if readCounts.postCount > readCounts.viewedCount {
				let numNewMsgs = readCounts.postCount - readCounts.viewedCount
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

