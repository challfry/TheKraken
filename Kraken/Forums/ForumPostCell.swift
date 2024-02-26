//
//  ForumPostCell.swift
//  Kraken
//
//  Created by Chall Fry on 12/4/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit

@objc class ForumPostCellModel: FetchedResultsCellModel, TwitarrTweetCellBindingProtocol {	
	override class var validReuseIDDict: [String: BaseCollectionViewCell.Type ] { return [ "tweet" : TwitarrTweetCell.self ] }

	// If false, the tweet cell doesn't show text links, the like/reply/delete/edit buttons, nor does tapping the 
	// user thumbnail open a user profile panel.
	@objc dynamic var isInteractive: Bool = true
	
	dynamic var author: KrakenUser?
	dynamic var postTime: Date?
	
	dynamic var numLikes: Int32 = 0
	dynamic var numLoves: Int32 = 0
	dynamic var numLaughs: Int32 = 0
	dynamic var postText: String?
	dynamic var photoDetails: [PhotoDetails]?
	dynamic var photoAttachments: [PostOpPhoto_Attachment]? 
	dynamic var loggedInUserIsAuthor: Bool = false		// False if no logged in user

	// Reply, Edit, Delete, Like
	dynamic var currentUserReplyOpCount: Int32 = 0
	dynamic var currentUserHasDeleteOp: Bool = false
	dynamic var currentUserHasEditOp: Bool = false
	dynamic var currentUserReactOpCount: Int32 = 0
	dynamic var currentUserHasLikeOp: LikeOpKind = .none
	dynamic var currentUserLikesThis: LikeOpKind = .none
	dynamic var canReply: Bool = false
	dynamic var isReplyGroup: Bool = false
	dynamic var canEdit: Bool = true
	dynamic var canDelete: Bool = true
	dynamic var canReport: Bool = false
	dynamic var authorIsBlocked: Bool = true

	dynamic var deleteConfirmationMessage: String = "Are you sure you want to delete this post?"
	dynamic var isDeleted: Bool = false
	
    override var model: NSFetchRequestResult? {
    	didSet {
    		clearObservations()
    		if let postModel = model as? ForumPost, !postModel.isDeleted {
    			setup(from: postModel)
			}
			else {
				author = nil
				postTime = nil
				postText = nil				
  				photoDetails = nil
  				photoAttachments = nil
  				isDeleted = true
  				shouldBeVisible = false
			}
		}
	}
	
	var viewController: BaseCollectionViewController?
	
	func setup(from postModel: ForumPost) {
	
		// Directly set some stuff that can't change.
		author = postModel.author
		postTime = postModel.createTime
					
		// We can't show the current number of likes this post has, as the API support is kinda lacking.
		// (There's a separate call to get the likes for a post, but it's per-post).
		addObservation(postModel.tell(self, when: "likeCount") { observer, observed in
			observer.numLikes = observed.likeCount
		}?.execute())
		addObservation(postModel.tell(self, when: "loveCount") { observer, observed in
			observer.numLoves = observed.loveCount
		}?.execute())
		addObservation(postModel.tell(self, when: "laughCount") { observer, observed in
			observer.numLaughs = observed.laughCount
		}?.execute())
		
		// Post text
		addObservation(postModel.tell(self, when: "text") { observer, observed in 	
			observer.postText = observed.text
		}?.execute())
							
		// Photos
		addObservation(postModel.tell(self, when: "photos") { observer, observed in
			if observed.photos.count > 0, let photoArray = observed.photos.array as? [PhotoDetails] {
				observer.photoDetails = photoArray
			}
			else {
				observer.photoDetails = nil
			}
		}?.execute())
		
		// Blocked users
		addObservation(CurrentUser.shared.tell(self, when: "loggedInUser.blockedUsers") { observer, observed in
			if let author = observer.author {
				observer.authorIsBlocked = observed.loggedInUser?.blockedUsers.contains(author) == true
			}
			else {
				observer.authorIsBlocked = false
			}
		}?.execute())
		
		// Watch for login/out
		let authorUsername = author?.username ?? ""
		addObservation(CurrentUser.shared.tell(self, when: "loggedInUser") { observer, observed in
			let currentUsername = CurrentUser.shared.loggedInUser?.username ?? ""
			observer.loggedInUserIsAuthor = authorUsername == currentUsername
			observer.canEdit = observer.loggedInUserIsAuthor
			observer.canDelete = observer.loggedInUserIsAuthor
			observer.canReport = !currentUsername.isEmpty && !observer.loggedInUserIsAuthor
						
		}?.execute())
		
		// Reply ops for replies that are children of this post
		currentUserReplyOpCount = 0
		
		// Ops deleting this post
		addObservation(postModel.tell(self, when: "opDeleting") { observer, observed in
			let currentUsername = CurrentUser.shared.loggedInUser?.username ?? ""
			observer.currentUserHasDeleteOp = observed.opDeleting?.author.username == currentUsername 
		}?.execute())
		
		// Ops editing this post
		addObservation(postModel.tell(self, when: "opEditing") { observer, observed in
			let currentUsername = CurrentUser.shared.loggedInUser?.username ?? ""
			observer.currentUserHasEditOp = observed.opEditing?.author.username == currentUsername
		}?.execute())
		
		// Likes by current user
		addObservation(postModel.tell(self, when: ["likeCount", "laughCount", "loveCount"]) { observer, observed in
			if let currentUserID = CurrentUser.shared.loggedInUser?.userID {
				observer.currentUserLikesThis = .none
				if let userReaction = observed.reactions.first(where: { $0.user?.userID == currentUserID }) {
					observer.currentUserLikesThis = userReaction.getLikeOpKind()
				}
			}
		}?.execute())
							
		// Like/Unlike ops
		addObservation(postModel.tell(self, when: "reactionOps.count") { observer, observed in
			if let likeOp = observed.getPendingUserReaction() {
				observer.currentUserHasLikeOp = LikeOpKind.fromString(likeOp.reactionWord)
			}
			else {
				observer.currentUserHasLikeOp = .none
			}
		}?.execute())
	}
	
	init(withModel: ForumPost?) {
		super.init(withModel: nil, reuse: "tweet", bindingWith: TwitarrTweetCellBindingProtocol.self)
		model = withModel
	}

//MARK: Action Handlers
	func linkTextTapped(link: String) {
		viewController?.segueOrNavToLink(link)
	}
	
	func authorIconTapped() {
		if let postModel = model as? ForumPost {
			viewController?.performKrakenSegue(.userProfile_User, sender: postModel.author)
		}
	}
	
	func likeButtonTapped(sender: UIButton) {
 		guard isInteractive else { return }
   		guard let postModel = model as? ForumPost else { return } 
		let senderPackage = LikeTypePopupSegue(post: postModel, button: sender)
		viewController?.performKrakenSegue(.showLikeOptions, sender: senderPackage)
	}
	
	func replyButtonTapped() {
		// Reply button should be hidden when used with this cell model.
	}
	
////
	
	func editButtonTapped() {
   		guard let postModel = model as? ForumPost else { return } 
		viewController?.performKrakenSegue(.editForumPost, sender: postModel)
	}
	
	func deleteButtonTapped() {
   		guard let postModel = model as? ForumPost else { return } 
		postModel.addDeletePostOp()
	}
	
	func cancelDeleteOpButtonTapped() {
   		guard let postModel = model as? ForumPost else { return } 
		postModel.cancelDeleteOp()   		
	}
	
	func cancelEditOpButtonTapped() {
   		guard let postModel = model as? ForumPost else { return } 
		postModel.cancelEditOp()   		
	}
	
	func viewPendingRepliesButtonTapped() {
		// Forum posts don't have replies in this sense (they have posts that come after them in their thread).
	}
	
	func cancelReactionOpButtonTapped() {
   		guard let postModel = model as? ForumPost else { return } 
		postModel.cancelReactionOp()   		
	}

	func reportContentButtonTapped() {
   		guard let postModel = model as? ForumPost else { return } 
		viewController?.performKrakenSegue(.reportContent, sender: postModel)
	}
	
// MARK: fns
	func getLikesData() { 
		if let postModel = model as? ForumPost {
			ForumPostDataManager.shared.loadForumPostDetail(post: postModel)
		}
	}
}

@objc class ForumPostOpCellModel: FetchedResultsCellModel, TwitarrTweetCellBindingProtocol {	
	override class var validReuseIDDict: [String: BaseCollectionViewCell.Type ] { return [ "tweet" : TwitarrTweetCell.self ] }

	// If false, the tweet cell doesn't show text links, the like/reply/delete/edit buttons, nor does tapping the 
	// user thumbnail open a user profile panel.
	@objc dynamic var isInteractive: Bool = false
	
	dynamic var author: KrakenUser?
	dynamic var postTime: Date?
	
	dynamic var numLikes: Int32 = 0
	dynamic var numLoves: Int32 = 0
	dynamic var numLaughs: Int32 = 0
	dynamic var postText: String?
	dynamic var photoDetails: [PhotoDetails]?
	dynamic var photoAttachments: [PostOpPhoto_Attachment]? 
	dynamic var loggedInUserIsAuthor: Bool = false		// False if no logged in user

	// Reply, Edit, Delete, Like
	dynamic var currentUserReplyOpCount: Int32 = 0
	dynamic var currentUserHasDeleteOp: Bool = false
	dynamic var currentUserHasEditOp: Bool = false
	dynamic var currentUserReactOpCount: Int32 = 0
	dynamic var currentUserHasLikeOp: LikeOpKind = .none
	dynamic var currentUserLikesThis: LikeOpKind = .none
	dynamic var canReply: Bool = false
	dynamic var isReplyGroup: Bool = false
	dynamic var canEdit: Bool = true
	dynamic var canDelete: Bool = true
	dynamic var canReport: Bool = false
	dynamic var authorIsBlocked: Bool = false

	dynamic var deleteConfirmationMessage: String = "This draft post hasn't been delivered to the server yet. Delete it?"
	dynamic var isDeleted: Bool = false
	
    override var model: NSFetchRequestResult? {
    	didSet {
    		clearObservations()
    		if let postModel = model as? PostOpForumPost, !postModel.isDeleted {
    			setup(from: postModel)
			}
			else {
				author = nil
				postTime = nil
				postText = nil				
  				photoDetails = nil
  				photoAttachments = nil
  				isDeleted = true
  				shouldBeVisible = false
			}
		}
	}
	
	var viewController: BaseCollectionViewController?
	
	func setup(from postModel: PostOpForumPost) {
	
		// Directly set some stuff that can't change.
		author = postModel.author
		postTime = nil
					
		// We can't show the current number of likes this post has, as the API support is kinda lacking.
		// (There's a separate call to get the likes for a post, but it's per-post).
		numLikes = 0
		
		// Post text
		addObservation(postModel.tell(self, when: "text") { observer, observed in 	
			observer.postText = observed.text
		}?.execute())
							
		// Photos
		addObservation(postModel.tell(self, when: "photos") { observer, observed in
			if let photoArray = observed.photos?.array as? [PhotoDetails], photoArray.count > 0 {
				observer.photoDetails = photoArray
			}
			else {
				observer.photoDetails = nil
			}
		}?.execute())
		
		// Watch for login/out
		let authorUsername = author?.username ?? ""
		addObservation(CurrentUser.shared.tell(self, when: "loggedInUser") { observer, observed in
			let currentUsername = CurrentUser.shared.loggedInUser?.username ?? ""
			observer.loggedInUserIsAuthor = authorUsername == currentUsername
		}?.execute())
		
		// Reply ops for replies that are children of this post
		currentUserReplyOpCount = 0
	}
	
	init(withModel: PostOpForumPost?) {
		super.init(withModel: nil, reuse: "tweet", bindingWith: TwitarrTweetCellBindingProtocol.self)
		model = withModel
	}

//MARK: Action Handlers
	func linkTextTapped(link: String) {
	}
	
	func authorIconTapped() {
	}
	
	func likeButtonTapped(sender: UIButton) {
	}
	
	func replyButtonTapped() {
	}
		
	func editButtonTapped() {
	}
	
	func deleteButtonTapped() {
	}
	
	func cancelDeleteOpButtonTapped() {
	}
	
	func cancelEditOpButtonTapped() {
	}
	
	func viewPendingRepliesButtonTapped() {
	}
	
	func cancelReactionOpButtonTapped() {
	}
	func reportContentButtonTapped() { }
	
	func getLikesData() { }

}
