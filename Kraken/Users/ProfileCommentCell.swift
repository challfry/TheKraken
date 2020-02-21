//
//  ProfileCommentCell.swift
//  Kraken
//
//  Created by Chall Fry on 9/24/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit

@objc protocol ProfileCommentCellProtocol {
	dynamic var comment: String? { get set }
	dynamic var commentOp: PostOpUserComment? { get set }
}

@objc class ProfileCommentCellModel: BaseCellModel, ProfileCommentCellProtocol {
	private static let validReuseIDs = [ "ProfileComment" : ProfileCommentCell.self ]
	override class var validReuseIDDict: [String: BaseCollectionViewCell.Type ] { return validReuseIDs }

	dynamic var comment: String?
	dynamic var commentOp: PostOpUserComment? 
	
	var editedComment: String? 				// Contains edits made by the cell
	
	@objc dynamic var userModel: KrakenUser? 

	init(user: KrakenUser?) {
		userModel = user
		super.init(bindingWith: ProfileCommentCellProtocol.self)
		
		self.tell(self, when: ["userModel", "userModel.commentOps.*"]) { observer, observed in 
			observer.updateBindingVars()
		}?.execute()
		
		CurrentUser.shared.tell(self, when: "loggedInUser") { observer, observed in 
			observer.updateBindingVars()
		}
		
	}
	
	func updateBindingVars() {
		if let userModel = userModel, let currentUser = CurrentUser.shared.loggedInUser {
			// We're only visible if we're logged in, and then we're only visible when looking at some else's profile.
			shouldBeVisible = userModel.username != currentUser.username

			// Show the existing user comment, if there is one.
			if let userComment = currentUser.userComments?.first(where: { $0.commentedOnUser.username == userModel.username } ) {
				comment = userComment.comment
			}
			else {
				comment = nil
			}

			commentOp = (currentUser.postOps?.first { 
				if let commentTypeOp = $0 as? PostOpUserComment {
					return commentTypeOp.userCommentedOn?.username == userModel.username
				}
				return false
			}) as? PostOpUserComment
		}
		else {
			commentOp = nil
			comment = nil
			shouldBeVisible = false
		}
	}
	
}


class ProfileCommentCell: BaseCollectionViewCell, ProfileCommentCellProtocol, UITextViewDelegate {
	@IBOutlet var personalCommentTitle: UILabel!
	@IBOutlet weak var saveButton: UIButton!
	@IBOutlet weak var commentView: UITextView!
	@IBOutlet weak var commentViewHeightConstraint: NSLayoutConstraint!
	@IBOutlet weak var postOpView: UIView!
	@IBOutlet var 		postOpHeightConstraint: NSLayoutConstraint!
	@IBOutlet weak var 	statusLabel: UILabel!
	@IBOutlet var postOpReviseButton: UIButton!
	@IBOutlet weak var 	postOpCancelButton: UIButton!
	
	private static let cellInfo = [ "ProfileComment"  : PrototypeCellInfo("ProfileCommentCell") ]
	override class var validReuseIDDict: [ String: PrototypeCellInfo ] { return cellInfo }
	
	override func awakeFromNib() {
		postOpView.isHidden = false
		postOpHeightConstraint.constant = 0
		postOpHeightConstraint.isActive = true
		super.awakeFromNib()
		
		personalCommentTitle.styleFor(.body)
		saveButton.styleFor(.body)
		commentView.styleFor(.body)
		statusLabel.styleFor(.body)
		postOpCancelButton.styleFor(.body)
		postOpReviseButton.styleFor(.body)
	}
	
	var comment: String? {
		didSet {
			setupCell()
		}
	}

	var commentOp: PostOpUserComment? {
		didSet {
			setupCell()
		}
	}
		
	func setupCell() {
		var hasEditedComment: Bool = false
		if let model = cellModel as? ProfileCommentCellModel, model.editedComment != nil, model.editedComment != model.comment{
			hasEditedComment = true
			commentView.text = model.editedComment
		}
		else {
			commentView.text = comment
		}
		
		var hidePostOpView: Bool = true
		if let op = commentOp {
			hidePostOpView = false
			commentView.isEditable = false
			saveButton.isEnabled = false
			commentView.text = op.comment
			
			// If this is a new cell with no editing, but there's a pending change that existed when this cell was built,
			// set editedComment so revise will work correctly if the user hits it.
			if !hasEditedComment, let model = cellModel as? ProfileCommentCellModel {
				model.editedComment = op.comment
			}
		}
		else {
			commentView.isEditable = true
			saveButton.isEnabled = hasEditedComment
		}
		
		if hidePostOpView != self.postOpHeightConstraint.isActive {
			animateIfNotPrototype(withDuration: 0.3) {
				self.postOpHeightConstraint.isActive = hidePostOpView
				self.layoutIfNeeded()
				self.cellSizeChanged()
			}
		}		
	}
	
// MARK: Actions	
	@IBAction func saveButtonTapped() {
		if let model = cellModel as? ProfileCommentCellModel, let userModel = model.userModel {
			CurrentUser.shared.setUserComment(commentView.text, forUser: userModel)
		}
	}
	
	// 'Cancel' deletes the pending postOp and clears edits, leaving the user comment in the state the server last gave us.
	@IBAction func cancelEditOp(_ sender: Any) {
		if let op = commentOp {
			CurrentUser.shared.cancelUserCommentOp(op)
			if let model = cellModel as? ProfileCommentCellModel {
				model.editedComment = nil
			}
		}
	}
	
	// 'Revise' deletes the pending postOp and sets the text view to what had been in the op, so the user can easily 
	// hit save again and re-queue the postOp.
	@IBAction func reviseEditOp(_ sender: Any) {
		if let op = commentOp {
			CurrentUser.shared.cancelUserCommentOp(op)
		}
	}
	
	
	func textViewDidBeginEditing(_ textView: UITextView) {
		if let vc = viewController as? BaseCollectionViewController {
			vc.textViewBecameActive(textView, inCell: self)
		}
	}
	
	func textViewDidEndEditing(_ textView: UITextView) {
		if let vc = viewController as? BaseCollectionViewController {
			vc.textViewResignedActive(textView, inCell: self)
		}
	}
	
	func textViewDidChange(_ textView: UITextView) {
		if let model = cellModel as? ProfileCommentCellModel {
			model.editedComment = commentView.text
			saveButton.isEnabled = model.editedComment != model.comment
			let newSize = textView.sizeThatFits(CGSize(width: commentView.frame.size.width, height: 10000.0))
			if newSize.height != commentViewHeightConstraint.constant {
				let _ = UIViewPropertyAnimator(duration: 0.4, curve: .easeInOut) {
					self.commentViewHeightConstraint.constant = newSize.height
				}
				cellSizeChanged()
			}
		}
	}
}

