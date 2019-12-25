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
	dynamic var postText: String?
	dynamic var photos: [PhotoDetails]?
	dynamic var photoImages: [Data]? 
	dynamic var loggedInUserIsAuthor: Bool = false		// False if no logged in user

	// Reply, Edit, Delete, Like
	dynamic var currentUserReplyOpCount: Int32 = 0
	dynamic var currentUserHasDeleteOp: Bool = false
	dynamic var currentUserHasEditOp: Bool = false
	dynamic var currentUserReactOpCount: Int32 = 0
	dynamic var currentUserHasLikeOp: LikeOpKind = .none
	dynamic var currentUserLikesThis: Bool = false

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
  				photos = nil
  				isDeleted = true
  				shouldBeVisible = false
			}
		}
	}
	
	var viewController: BaseCollectionViewController?
	
	func setup(from postModel: ForumPost) {
	
		// Directly set some stuff that can't change.
		author = postModel.author
		postTime = postModel.postDate()
					
		// We can't show the current number of likes this post has, as the API support is kinda lacking.
		// (There's a separate call to get the likes for a post, but it's per-post).
		numLikes = 0
		
		// Post text
		addObservation(postModel.tell(self, when: "text") { observer, observed in 	
			observer.postText = observed.text
		}?.execute())
							
		// Photos
		addObservation(postModel.tell(self, when: "photos") { observer, observed in
			if observed.photos.count > 0, let photo = observed.photos[0] as? PhotoDetails {
				observer.photos = [photo]
			}
			else {
				observer.photos = []
			}
		}?.execute())
		
		// Watch for login/out
		let authorUsername = author?.username ?? ""
		addObservation(CurrentUser.shared.tell(self, when: "loggedInUser") { observer, observed in
			let currentUsername = CurrentUser.shared.loggedInUser?.username ?? ""
			observer.loggedInUserIsAuthor = authorUsername == currentUsername
		
			// When the current user changes, need to re-evaluate: DeleteOps, EditOps, Likes, LikeOps
//			observer.currentUserHasDeleteOp = postModel.opsDeletingThisTweet?.contains { 
//				$0.author.username == currentUsername 
//			} ?? false
//			observer.currentUserHasEditOp = tweetModel.opsEditingThisTweet?.author.username == currentUsername
//			observer.currentUserLikesThis = tweetModel.likeReaction?.users.contains { $0.username == currentUsername } ?? false
//			if let likeOp = tweetModel.getPendingUserReaction("like") {
//				observer.currentUserHasLikeOp = likeOp.isAdd ? .like : .unlike
//			}
//			else {
//				observer.currentUserHasLikeOp = .none
//			}
			
		}?.execute())
		
		// Reply ops for replies that are children of this post
		currentUserReplyOpCount = 0
		
		// Ops deleting this post
//		addObservation(tweetModel.tell(self, when: "opsDeletingThisTweet") { observer, observed in
//			let currentUsername = CurrentUser.shared.loggedInUser?.username ?? ""
//			observer.currentUserHasDeleteOp = observed.opsDeletingThisTweet?.contains { 
//				$0.author.username == currentUsername 
//			} ?? false
//		}?.execute())
//		
//		// Ops editing this tweet
//		addObservation(tweetModel.tell(self, when: "opsEditingThisTweet") { observer, observed in
//			let currentUsername = CurrentUser.shared.loggedInUser?.username ?? ""
//			observer.currentUserHasEditOp = observed.opsEditingThisTweet?.author.username == currentUsername
//		}?.execute())
//		
//		// Likes
//		addObservation(tweetModel.tell(self, when: "reactionDict.like.users.count") { observer, observed in
//			let currentUsername = CurrentUser.shared.loggedInUser?.username ?? ""
//			observer.currentUserLikesThis = observed.likeReaction?.users.contains 
//					{ $0.username == currentUsername } ?? false
//		}?.execute())
//							
//		// Like/Unlike ops
//		addObservation(tweetModel.tell(self, when: "reactionOpsCount") { observer, observed in
//			if let likeOp = tweetModel.getPendingUserReaction("like") {
//				observer.currentUserHasLikeOp = likeOp.isAdd ? .like : .unlike
//			}
//			else {
//				observer.currentUserHasLikeOp = .none
//			}
//		}?.execute())
	}
	
	init(withModel: ForumPost?) {
		super.init(withModel: nil, reuse: "tweet", bindingWith: TwitarrTweetCellBindingProtocol.self)
		model = withModel
	}

//MARK: Action Handlers
	func linkTextTapped(link: String) {
		viewController?.performKrakenSegue(.tweetFilter, sender: link)
	}
	
	func authorIconTapped() {
		if let tweetModel = model as? TwitarrPost {
			viewController?.performKrakenSegue(.userProfile, sender: tweetModel.author.username)
		}
	}
	
	func likeButtonTapped() {
 		guard isInteractive else { return }
   		guard let tweetModel = model as? TwitarrPost else { return } 

		// FIXME: Still not sure what to do in the case where the user, once logged in, already likes the post.
		// When nobody is logged in we still enable and show the Like button. Tapping it opens the login panel, 
		// with a successAction that performs the like action.
		if !CurrentUser.shared.isLoggedIn() {
 			let seguePackage = LoginSegueWithAction(promptText: "In order to like this post, you'll need to log in first.",
					loginSuccessAction: { tweetModel.setReaction("like", to: !self.currentUserLikesThis) }, 
					loginFailureAction: nil)
  			viewController?.performKrakenSegue(.modalLogin, sender: seguePackage)
   		}
   		else {
			tweetModel.setReaction("like", to: !currentUserLikesThis)
   		}
	}
	
	func replyButtonTapped() {
	}
	
	func editButtonTapped() {
   		guard let tweetModel = model as? TwitarrPost else { return } 
		viewController?.performKrakenSegue(.editTweet, sender: tweetModel)
	}
	
	func deleteButtonTapped() {
	
	}
	
	func cancelDeleteOpButtonTapped() {
		guard let tweetModel = model as? TwitarrPost else { return } 
		tweetModel.cancelDeleteOp()   		
	}
	
	func cancelEditOpButtonTapped() {
		guard let tweetModel = model as? TwitarrPost else { return } 
		tweetModel.cancelEditOp()   		
	}
	
	func viewPendingRepliesButtonTapped() {
		guard let tweetModel = model as? TwitarrPost else { return } 
		viewController?.performKrakenSegue(.pendingReplies, sender: tweetModel)
	}
	
	func cancelReactionOpButtonTapped() {
		guard let tweetModel = model as? TwitarrPost else { return } 
		tweetModel.cancelReactionOp("like")   		
	}

}
