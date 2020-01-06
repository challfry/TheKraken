//
//  ForumsRootViewController.swift
//  Kraken
//
//  Created by Chall Fry on 3/20/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit

class ForumsRootViewController: BaseCollectionViewController {
	var forumsNavTitleButton: UIButton!
	@IBOutlet weak var forumsFilterView: UIVisualEffectView!
	@IBOutlet weak var forumsFilterViewTop: NSLayoutConstraint!
	@IBOutlet weak var forumsFilterContainerView: UIView!
	@IBOutlet weak var forumsFilterStackView: UIStackView!
	@IBOutlet weak var forumsFilterHeightConstraint: NSLayoutConstraint!
	
	enum FilterType {
		case allWithActivitySort
//		case allWithCreationSort		// CreationSort doesn't quite work as we don't know creation time
										// until we load the first post.
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
    var filterPopupVC: EmojiPopupViewController?
    
    lazy var loadingStatusCell: LoadingStatusCellModel = {
    	let cell = LoadingStatusCellModel()
    	cell.statusText = "Loading Forum Threads"
    	cell.showSpinner = true
    	
    	ForumsDataManager.shared.tell(cell, when: ["isPerformingLoad", "lastError"]) { observer, observed in 
    		observer.shouldBeVisible = observed.isPerformingLoad || observed.lastError != nil
    		observer.errorText = observed.lastError?.getErrorString()
    	}?.execute()
     	
    	return cell
    }()
    
    lazy var loadTimeCellModel: ForumsLoadTimeCellModel = {
    	let cell = ForumsLoadTimeCellModel()
    	cell.refreshButtonAction = {
			ForumsDataManager.shared.loadForumThreads(fromOffset: 0) {
			}
    	}
    	
    	ForumsDataManager.shared.tell(cell, when: "lastForumRefreshTime") { observer, observed in 
    		observer.lastLoadTime = observed.lastForumRefreshTime
    	}?.execute()
    	return cell
    }()
    

// MARK: Methods
	
	override func viewDidLoad() {
		super.viewDidLoad()
		buildFilterView()		

		threadDataSource.append(segment: loadingSegment)
		loadingSegment.append(loadingStatusCell)
		loadingSegment.append(loadTimeCellModel)
		
		threadDataSource.append(segment: threadSegment)
		threadSegment.activate(predicate: NSPredicate(value: true), 
				sort: [NSSortDescriptor(key: "sticky", ascending: false),
				NSSortDescriptor(key: "lastPostTime", ascending: false)], cellModelFactory: createCellModel)

		threadDataSource.append(segment: readCountSegment)
		readCountSegment.activate(predicate: NSPredicate(value: false), 
				sort: [ NSSortDescriptor(key: "lastPostTime", ascending: false)], cellModelFactory: createReadCountCellModel)

		threadDataSource.register(with: collectionView, viewController: self)

	//	setupGestureRecognizer()
		knownSegues = Set([.showForumThread, .modalLogin])
	}
		
    override func viewWillAppear(_ animated: Bool) {
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
	}
	
	func setFilterType(_ newType: FilterType) {
	
		if newType != currentFilterType {
			currentFilterType = newType
			switch(newType) {
			case .allWithActivitySort:
				threadSegment.activate(predicate: NSPredicate(value: true), 
						sort: [NSSortDescriptor(key: "sticky", ascending: false),
						NSSortDescriptor(key: "lastPostTime", ascending: false)], 
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
			loadTimeCellModel.shouldBeVisible = newType == .allWithActivitySort
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
		}
		else {
			forumsFilterHeightConstraint.constant = 0
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

}
