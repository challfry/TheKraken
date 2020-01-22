//
//  SeamailRootViewController.swift
//  Kraken
//
//  Created by Chall Fry on 3/29/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit
import CoreData

class SeamailRootViewController: BaseCollectionViewController, GlobalNavEnabled {
	@IBOutlet var newThreadButton: UIBarButtonItem!

	let loginDataSource = KrakenDataSource()
	let loginSection = LoginDataSourceSegment()
	let threadDataSource = KrakenDataSource()
	lazy var threadSegment = FRCDataSourceSegment<SeamailThread>()
	let dataManager = SeamailDataManager.shared

// MARK: Methods	
	override func awakeFromNib() {
		super.awakeFromNib()
		
		// Set the badge on the Seamail tab
		CurrentUser.shared.tell(self, when: ["loggedInUser", "loggedInUser.upToDateSeamailThreads.count", 
				"loggedInUser.seamailParticipant.count"]) { observer, observed in
			if let currentUser = observed.loggedInUser {
				let badgeCount = currentUser.seamailParticipant.count - currentUser.upToDateSeamailThreads.count
				observer.navigationController?.tabBarItem.badgeValue = badgeCount > 0 ? "\(badgeCount)" : nil
			}
			else {
				observer.navigationController?.tabBarItem.badgeValue = nil
			}
		}?.execute()
	}
	
	override func viewDidLoad() {
        super.viewDidLoad()
        
		// Pull-to-refresh
		collectionView.refreshControl = UIRefreshControl()
		collectionView.refreshControl?.addTarget(self, action: #selector(self.self.startRefresh), for: .valueChanged)

        loginDataSource.append(segment: loginSection)
		loginSection.headerCellText = "In order to see your Seamail, you will need to log in first."

		threadDataSource.append(segment: threadSegment)
		threadSegment.activate(predicate: nil, sort: [ NSSortDescriptor(key: "timestamp", ascending: false)],
				cellModelFactory: createCellModel)
       
		// When a user is logged in we'll set up the FRC to load the threads which that user can 'see'. Remember, CoreData
		// stores ALL the seamail we ever download, for any user who logs in on this device.
        CurrentUser.shared.tell(self, when: "loggedInUser") { observer, observed in        		
			if let username = observed.loggedInUser?.username {
 				observer.threadSegment.changePredicate(to: NSPredicate(format: "ANY participants.username == '\(username)'"))
        		observer.threadDataSource.register(with: observer.collectionView, viewController: observer)
        		observer.dataManager.loadSeamails { 
					DispatchQueue.main.async { observer.collectionView.reloadData() }
				}
				observer.newThreadButton.isEnabled = true
       		}
       		else {
       			// If nobody's logged in, pop to root, show the login cells.
 				observer.threadSegment.changePredicate(to: NSPredicate(value: false))
				observer.loginDataSource.register(with: observer.collectionView, viewController: observer)
				observer.newThreadButton.isEnabled = false
				self.navigationController?.popToRootViewController(animated: false)
       		}
        }?.execute()        

		title = "Seamail"
		knownSegues = Set([.userProfile, .showSeamailThread])
    }
    
    override func viewDidAppear(_ animated: Bool) {
		loginDataSource.enableAnimations = true
		threadDataSource.enableAnimations = true
		loginSection.clearAllSensitiveFields()
	}
	
	@objc func startRefresh() {
		dataManager.loadSeamails { 
			DispatchQueue.main.async { 
				self.collectionView.refreshControl?.endRefreshing()
			}
		}
    }

	// Gets called from within collectionView:cellForItemAt:
	func createCellModel(_ model:SeamailThread) -> BaseCellModel {
		let cellModel = SeamailThreadCellModel(withModel: model, reuse: "seamailThread")
		return cellModel
	}
	
	// Since there are 2 different ThreadCells for different content sizes, we need to reload when the trait
	// environment changes. Re-layout probably won't cut it, as we may need to change an existing cell from one
	// xib to the other.
	override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
		// There's a good chance we can limit this to changes to content size (read: font size) and size class (read: landscape)
		collectionView.reloadData()
	}
    
    // MARK: Navigation
    
	func globalNavigateTo(packet: GlobalNavPacket) -> Bool{
		if let userNames = packet.arguments["seamailThreadParticipants"] as? Set<String> {
			if let nav = self.navigationController, let threads = threadSegment.frc?.fetchedObjects {
				let storyboard = UIStoryboard(name: "Main", bundle: nil)
				for thread in threads {
					let threadParticipantNames = Set(thread.participants.map { $0.username })
					if threadParticipantNames == userNames {
						let existingThreadVC = storyboard.instantiateViewController(withIdentifier: "SeamailThread") as! SeamailThreadViewController
						existingThreadVC.threadModel = thread
						nav.viewControllers = [nav.viewControllers[0], existingThreadVC]
						if let globalNav = existingThreadVC as? GlobalNavEnabled {
							globalNav.globalNavigateTo(packet: packet)
						}
						return true
					}
				}
				
				// If we get here, we didn't find an existing seamail thread to the listed user.
				let newVC = storyboard.instantiateViewController(withIdentifier: "ComposeSeamailThreadVC")
				nav.viewControllers = [nav.viewControllers[0], newVC]
				if let globalNav = newVC as? GlobalNavEnabled {
					globalNav.globalNavigateTo(packet: packet)
				}
			}
		}
		return true
	}
	
	// This is the unwind segue handler for the thread view. It needs to exist, but doesn't need to do anything.
	@IBAction func dismissingSeamailThread(segue: UIStoryboardSegue) {
	}


}
