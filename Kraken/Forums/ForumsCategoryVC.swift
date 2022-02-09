//
//  ForumsCategoryVC.swift
//  Kraken
//
//  Created by Chall Fry on 3/20/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit

class ForumsCategoryViewController: BaseCollectionViewController {
	var forumsNavTitleButton: UIButton!
	@IBOutlet weak var forumsFilterView: UIVisualEffectView!
	@IBOutlet weak var forumsFilterViewTop: NSLayoutConstraint!
	@IBOutlet weak var forumsFilterContainerView: UIView!
	@IBOutlet weak var forumsFilterStackView: UIStackView!
	@IBOutlet weak var forumsFilterHeightConstraint: NSLayoutConstraint!
	
	@IBOutlet weak var newForumButton: UIBarButtonItem!
	
	// Set during segue
	var categoryModel: ForumCategory?
	
	//
	@objc dynamic var filterPack: ForumFilterPack?
	
	enum FilterType {
		case allWithActivitySort
		case allWithCreationSort		
		case favorites					// Forums the user has favorited. Favoriting forums is local only, the server 
										// has no API to track it.
		case history					// Shows the last forums visited, most recent at top.
		case userHasPosted				// Forums the user has posted into.
	}
	var currentFilterType: FilterType = .allWithActivitySort
	
	let threadDataSource = KrakenDataSource()
		var loadingSegment = FilteringDataSourceSegment()
		var threadSegment = FRCDataSourceSegment<ForumThread>()
		var readCountSegment = FRCDataSourceSegment<ForumReadCount>()
 
	let loginDataSource = KrakenDataSource()
		let loginSection = LoginDataSourceSegment()

    var filterPopupVC: EmojiPopupViewController?
    
    lazy var loadingStatusCellModel: LoadingStatusCellModel = {
    	let cell = LoadingStatusCellModel()
    	cell.statusText = "Loading Forum Threads"
    	cell.showSpinner = true
    	
    	ForumsDataManager.shared.tell(cell, when: ["isPerformingLoad", "lastError"]) { observer, observed in 
    		observer.shouldBeVisible = observed.isPerformingLoad || observed.lastError != nil
    		observer.errorText = observed.lastError?.getCompleteError()
    	}?.execute()
     	
    	return cell
    }()
    
    lazy var loadTimeCellModel: ForumsLoadTimeCellModel = {
    	let cell = ForumsLoadTimeCellModel()
    	cell.refreshButtonAction = { [weak self] in
    		if let strongSelf = self, let cat = strongSelf.categoryModel {
    			let sort = strongSelf.currentFilterType == .allWithActivitySort ? ForumFilterPack.SortType.update :
    					ForumFilterPack.SortType.create
				strongSelf.filterPack = ForumsDataManager.shared.forceRefreshForumThreads(for: cat, sort: sort) 
			}
    	}
    	
    	self.tell(cell, when: ["filterPack.refreshTime"]) { observer, observed in 
			observer.lastLoadTime = observed.filterPack?.refreshTime
    	}?.execute()
    	return cell
    }()
    

// MARK: Methods
	
	override func viewDidLoad() {
		super.viewDidLoad()
		buildFilterView()
		
		threadDataSource.append(segment: loadingSegment)
		loadingSegment.append(loadingStatusCellModel)
		loadingSegment.append(loadTimeCellModel)
		
		guard let cat = categoryModel else {
			//
			return
		}
		
		threadDataSource.append(segment: threadSegment)
		threadSegment.loaderDelegate = self
		threadSegment.activate(predicate: NSPredicate(format: "category == %@", cat), 
				sort: [NSSortDescriptor(key: "sticky", ascending: false),
				NSSortDescriptor(key: "lastPostTime", ascending: false)], cellModelFactory: createCellModel)

		threadDataSource.append(segment: readCountSegment)
		readCountSegment.activate(predicate: NSPredicate(value: false), 
				sort: [ NSSortDescriptor(key: "lastPostTime", ascending: false)], cellModelFactory: createReadCountCellModel)

        loginDataSource.append(segment: loginSection)
		loginSection.headerCellText = "In order to see the Forums, you will need to log in first."

		// When a user is logged in we'll set up the FRC to load the threads which that user can 'see'. Remember, CoreData
		// stores ALL the seamail we ever download, for any user who logs in on this device.
        CurrentUser.shared.tell(self, when: "loggedInUser") { observer, observed in        		
			if let _ = observed.loggedInUser?.userID {
        		observer.threadDataSource.register(with: observer.collectionView, viewController: observer)
				observer.newForumButton.isEnabled = true
				observer.navigationItem.titleView = observer.forumsNavTitleButton
			}
       		else {
       			// If nobody's logged in, pop to root, show the login cells.
				observer.loginDataSource.register(with: observer.collectionView, viewController: observer)
				observer.newForumButton.isEnabled = false
				observer.navigationController?.popToViewController(self, animated: false)
				observer.navigationItem.titleView = nil
       		}
        }?.execute()        

		knownSegues = Set([.showForumThread, .modalLogin])
	}
		
    override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		
		// This will ensure we have *some* content loaded, and also that we'll do a refresh if the content is really stale.
		if let cat = categoryModel {
			let sort: ForumFilterPack.SortType = currentFilterType == .allWithActivitySort ? .update : .create
			filterPack = ForumsDataManager.shared.checkLoadForumTheads(for: cat, sort: sort, userViewingIndex: 0)
		}
	}
	
    override func viewDidAppear(_ animated: Bool) {
    	super.viewDidAppear(animated)
		threadDataSource.enableAnimations = true
	}
	
	func buildFilterView () {
		// Install a button as the nav title.
		forumsNavTitleButton = UIButton()
		forumsNavTitleButton.setTitle("All Forums", for: .normal)
		forumsNavTitleButton.titleLabel?.font = UIFont.boldSystemFont(ofSize: 17)
		forumsNavTitleButton.setTitleColor(UIColor(named: "Kraken Label Text"), for: .normal)
		forumsNavTitleButton.setTitleColor(UIColor(named: "Kraken Secondary Text"), for: .highlighted)
		forumsNavTitleButton.imageEdgeInsets = UIEdgeInsets(top: 0, left: -8, bottom: 0, right: 8)
		navigationItem.titleView = forumsNavTitleButton
		forumsNavTitleButton.addTarget(self, action: #selector(filterButtonTapped), for: .touchUpInside)
		
		forumsFilterView.layer.cornerRadius = 8.0
		forumsFilterView.layer.masksToBounds = true
		forumsFilterHeightConstraint.constant = 0
		
		CurrentUser.shared.tell(self, when: "loggedInUser") { observer, observed in
			if observed.isLoggedIn() {
				observer.forumsNavTitleButton.setImage(UIImage(named: "ChevronDownGrey"), for: .normal)
			}
			else {
				observer.forumsNavTitleButton.setImage(nil, for: .normal)
				observer.setFilterType(.allWithActivitySort)
			}
		}?.execute()
		
		forumsNavTitleButton.sizeToFit()
		
		// Accessibility
	}
	
	func setFilterType(_ newType: FilterType) {
	
		if newType != currentFilterType {
			currentFilterType = newType
			switch (newType) {
			case .allWithActivitySort:
				threadSegment.activate(predicate: NSPredicate(value: true), 
						sort: [NSSortDescriptor(key: "sticky", ascending: false),
						NSSortDescriptor(key: "lastPostTime", ascending: false)], 
						cellModelFactory: createCellModel)
				readCountSegment.activate(predicate: NSPredicate(value: false), 
						sort: [ NSSortDescriptor(key: "lastReadTime", ascending: false)], 
						cellModelFactory: createReadCountCellModel)
				forumsNavTitleButton.setTitle("All Forums", for: .normal)
			case .allWithCreationSort:
				threadSegment.activate(predicate: NSPredicate(value: true), 
						sort: [NSSortDescriptor(key: "sticky", ascending: false),
						NSSortDescriptor(key: "createTime", ascending: false)], 
						cellModelFactory: createCellModel)
				readCountSegment.activate(predicate: NSPredicate(value: false), 
						sort: [ NSSortDescriptor(key: "lastReadTime", ascending: false)], 
						cellModelFactory: createReadCountCellModel)
				forumsNavTitleButton.setTitle("All Forums", for: .normal)
			case .history:
				threadSegment.activate(predicate: NSPredicate(value: false), 
						sort: [ NSSortDescriptor(key: "lastPostTime", ascending: false)], 
						cellModelFactory: createCellModel)
				readCountSegment.activate(predicate: NSPredicate(value: true), 
						sort: [ NSSortDescriptor(key: "lastReadTime", ascending: false)], 
						cellModelFactory: createReadCountCellModel)
				forumsNavTitleButton.setTitle("Forum History", for: .normal)
			case .favorites:
				threadSegment.activate(predicate: NSPredicate(value: false), 
						sort: [ NSSortDescriptor(key: "lastPostTime", ascending: false)], 
						cellModelFactory: createCellModel)
				readCountSegment.activate(predicate: NSPredicate(format: "isFavorite == TRUE"), 
						sort: [ NSSortDescriptor(key: "forumThread.sticky", ascending: false),
						NSSortDescriptor(key: "forumThread.lastPostTime", ascending: false) ], 
						cellModelFactory: createReadCountCellModel)
				forumsNavTitleButton.setTitle("Favorite Forums", for: .normal)
			case .userHasPosted:
				threadSegment.activate(predicate: NSPredicate(value: false), 
						sort: [ NSSortDescriptor(key: "lastPostTime", ascending: false)], 
						cellModelFactory: createCellModel)
				readCountSegment.activate(predicate: NSPredicate(format: "userPosted == TRUE"), 
						sort: [ NSSortDescriptor(key: "forumThread.sticky", ascending: false),
						NSSortDescriptor(key: "forumThread.lastPostTime", ascending: false) ], 
						cellModelFactory: createReadCountCellModel)
				forumsNavTitleButton.setTitle("Forums You Posted To", for: .normal)
			}
			
			// Only show the refresh time cell if we're showing all forums
			loadTimeCellModel.shouldBeVisible = [.allWithActivitySort, .allWithCreationSort, .userHasPosted].contains(newType)
		}
		
		forumsNavTitleButton.frame = CGRect(origin: CGPoint(x: 0, y: 0), size: forumsNavTitleButton.intrinsicContentSize)
		
		// Hide the filter panel
		if forumsFilterHeightConstraint.constant != 0 {
			forumsFilterHeightConstraint.constant = 0
			UIView.animate(withDuration: 0.3) {
				self.view.layoutIfNeeded()
			}
		}	
	}

	// Gets called from within collectionView:cellForItemAt:. Creates cell models from FRC result objects.
	func createCellModel(_ model: ForumThread) -> BaseCellModel {
		let cellModel = ForumsThreadCellModel(with: model)
		return cellModel
	}
	
	// Gets called from within collectionView:cellForItemAt:. Creates cell models from FRC result objects.
	func createReadCountCellModel(_ model: ForumReadCount) -> BaseCellModel {
		let cellModel = ForumsThreadCellModel(with: model)
		return cellModel
	}
    
// MARK: Actions
    
    // This is the button in the title area of the navbar.
	@objc func filterButtonTapped() {
		guard CurrentUser.shared.isLoggedIn() else {
			setFilterType(.allWithActivitySort)
			return
		}
	
		if forumsFilterHeightConstraint.constant == 0 {
			forumsFilterHeightConstraint.constant = forumsFilterStackView.bounds.size.height + 10
			
			collectionView.accessibilityElementsHidden = true
		}
		else {
			forumsFilterHeightConstraint.constant = 0
			collectionView.accessibilityElementsHidden = false
		}
		UIView.animate(withDuration: 0.3) {
			self.view.layoutIfNeeded()
		}
    }
    
    @IBAction func allForumsButtonTapped() {
		setFilterType(.allWithActivitySort)
    }

    @IBAction func forumHistoryButtonTapped() {
		setFilterType(.history)
    }

    @IBAction func favoriteForumsButtonTapped() {
    	setFilterType(.favorites)
    }

    @IBAction func postedForumsButtonTapped() {
    	setFilterType(.userHasPosted)
    }

	// This is the unwind segue from the compose view.
	@IBAction func dismissingPostingView(_ segue: UIStoryboardSegue) {
		// Load new threads when the user creates a new thread.
		if let cat = categoryModel {
			let sort: ForumFilterPack.SortType = currentFilterType == .allWithActivitySort ? .update : .create
			filterPack = ForumsDataManager.shared.forceRefreshForumThreads(for: cat, sort: sort ) 
		}
	}	
}

extension ForumsCategoryViewController: FRCDataSourceLoaderDelegate {
	func userIsViewingCell(at indexPath: IndexPath) {
		if let cat = categoryModel {
			let sort: ForumFilterPack.SortType = currentFilterType == .allWithActivitySort ? .update : .create
			ForumsDataManager.shared.checkLoadForumTheads(for: cat, sort: sort, userViewingIndex: indexPath.row)
		}
	}
}

