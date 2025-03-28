//
//  ForumThreadViewController.swift
//  Kraken
//
//  Created by Chall Fry on 12/4/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit

class ForumThreadViewController: BaseCollectionViewController {
	@IBOutlet weak var postButton: UIBarButtonItem!
	
	// ThreadModel is what we're modelling, but you can set threadModelID and we'll load that thread ID 
	// and set threadModel ourselves.
	@objc dynamic var threadModel: ForumThread?
	@objc dynamic var threadModelID: UUID?
	
	// The highest index *loaded*
	var highestRefreshedIndex: Int = 0
	// The highest index *viewed*
	var highestViewedIndex: Int64 = 0

	let threadDataSource = KrakenDataSource()
	var threadSegment = FRCDataSourceSegment<ForumPost>()
	var loadingSegment = FilteringDataSourceSegment()

	let loginDataSource = KrakenDataSource()
		let loginSection = LoginDataSourceSegment()

    lazy var loadTimeCellModel: ForumsLoadTimeCellModel = {
    	let cell = ForumsLoadTimeCellModel()
    	cell.refreshButtonAction = {
			if let tm = self.threadModel {
				self.postButton.isEnabled = !tm.locked
				let lastKnownPost = tm.posts.count
				ForumPostDataManager.shared.loadThreadPosts(for: tm, fromOffset: lastKnownPost) { thread, lastIndex in
					self.highestRefreshedIndex = lastIndex
					cell.lastLoadTime = Date()
				}
			}
    	}
    	
    	self.tell(cell, when: "threadModel.lastUpdateTime") { observer, observed in 
    		observer.lastLoadTime = observed.threadModel?.lastUpdateTime
    	}?.execute()
    	return cell
    }()
    
	override func viewDidLoad() {
        super.viewDidLoad()
        
        // Set up the login data source, for cases where this VC is shown and nobody's logged in
		loginDataSource.append(segment: loginSection)
		loginSection.headerCellText = "In order to see this thread you will need to log in first."

		// Make the threadDS, and add the segment with all the posts
		threadDataSource.append(segment: threadSegment)
		threadSegment.loaderDelegate = self

		// Then add the loading segment
		loadingSegment.append(loadTimeCellModel)
		threadDataSource.append(segment: loadingSegment)

		// When a user is logged in we'll set up the FRC to load the threads which that user can 'see'. Remember, CoreData
		// stores ALL the forums we ever download, for any user who logs in on this device.
        CurrentUser.shared.tell(self, when: "loggedInUser") { observer, observed in        		
			if observed.isLoggedIn() {
        		observer.threadDataSource.register(with: observer.collectionView, viewController: observer)
//				observer.navigationItem.titleView = observer.forumsNavTitleButton

				ForumPostDataManager.shared.loadThreadPosts(for: observer.threadModel, forID: observer.threadModelID, fromOffset: 0) { thread, lastIndex in
					self.threadModel = thread
					self.highestRefreshedIndex = lastIndex
					self.loadTimeCellModel.lastLoadTime = Date()
					observer.postButton.isEnabled = observer.threadModel?.locked == false
				}
			}
       		else {
       			// If nobody's logged in, pop to root, show the login cells.
				observer.loginDataSource.register(with: observer.collectionView, viewController: observer)
				observer.navigationController?.popToViewController(observer, animated: false)
				observer.postButton.isEnabled = false
			}
        }?.execute()   

		self.tell(self, when: "threadModel") { observer, observed in 
			observer.title = observed.threadModel?.subject ?? "Thread"
			var threadPredicate: NSPredicate
			if let tm = observed.threadModel {
				threadPredicate = NSPredicate(format: "thread.id == %@", tm.id as CVarArg)
			}
			else {
				threadPredicate = NSPredicate(value: false)
			}
			observer.threadSegment.activate(predicate: threadPredicate, 
					sort: [ NSSortDescriptor(key: "id", ascending: true)], cellModelFactory: observer.createCellModel)
			observer.postButton.isEnabled = observed.threadModel?.locked == false && CurrentUser.shared.isLoggedIn()
			
		}?.execute()
    }
    
    override func viewWillAppear(_ animated: Bool) {
    	super.viewWillAppear(animated)
	}
	
	override func viewDidAppear(_ animated: Bool) {
    	super.viewDidAppear(animated)
		threadDataSource.enableAnimations = true

		let loadedPostCount = threadSegment.collectionView(collectionView, numberOfItemsInSection: 0) - 1
		if let currentUser = CurrentUser.shared.loggedInUser, let readCountObject = threadModel?.readCount
				.first(where: { rco in rco.user.username == currentUser.username }), loadedPostCount > 0 {
			let scrollTarget = min(loadedPostCount, Int(readCountObject.numPostsRead))
			collectionView.scrollToItem(at: IndexPath(row: Int(scrollTarget), section: 0), at: .bottom, animated: true)
		}
	}
	
	override func viewWillDisappear(_ animated: Bool) {
    	super.viewWillDisappear(animated)
		if let tm = threadModel {
			tm.updateLastReadTime(highestViewedIndex: highestViewedIndex)
		}
	}
	
	// Gets called from within collectionView:cellForItemAt:. Creates cell models from FRC result objects.
	func createCellModel(_ model: ForumPost) -> BaseCellModel {
		let cellModel = ForumPostCellModel(withModel: model)
		cellModel.viewController = self
		return cellModel
	}

	@IBAction func postButtonTapped(_ sender: Any) {
		performKrakenSegue(.composeForumPost, sender: threadModel)
	}
	
// MARK: Navigation
	override var knownSegues : Set<GlobalKnownSegue> {
		Set<GlobalKnownSegue>([ .composeForumPost, .editForumPost, .tweetFilter, .userProfile_User, .userProfile_Name,
				.modalLogin, .reportContent, .showLikeOptions ])
	}		
	
	// This is the unwind segue from the compose view.
	@IBAction func dismissingPostingView(_ segue: UIStoryboardSegue) {
	}	
}

extension ForumThreadViewController: FRCDataSourceLoaderDelegate {
	func userIsViewingCell(at indexPath: IndexPath) {
		if indexPath.row > highestViewedIndex {
			highestViewedIndex = Int64(indexPath.row)
		}
		if let tm = threadModel,  indexPath.row + 10 > highestRefreshedIndex, 
				highestRefreshedIndex + 1 < tm.postCount, !ForumsDataManager.shared.isPerformingLoad {
			ForumPostDataManager.shared.loadThreadPosts(for: tm, fromOffset: highestRefreshedIndex) { thread, lastIndex in
				self.highestRefreshedIndex = lastIndex
				self.loadTimeCellModel.lastLoadTime = Date()
			}
		}
	}
}

