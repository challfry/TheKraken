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
	lazy var noSeamailSegment = FilteringDataSourceSegment()
	lazy var threadSegment = FRCDataSourceSegment<SeamailThread>()
	let dataManager = SeamailDataManager.shared
	
	lazy var noSeamailCell: LabelCellModel = {
		let cell = LabelCellModel("No Seamails in your inbox yet, but you can start a conversation by tapping the \"New\" button." )
		
		CurrentUser.shared.tell(cell, when: "loggedInUser.seamailParticipant.count") { observer, observed in
			observer.shouldBeVisible = observed.loggedInUser?.seamailParticipant.count == 0
		}?.execute()
		
		return cell
	}()
	
	// Used to store incoming global nav until our view is loaded. 
	var globalNav: GlobalNavPacket?

// MARK: Methods	
	override func awakeFromNib() {
		super.awakeFromNib()
	}
	
	override func viewDidLoad() {
        super.viewDidLoad()
        
		// Pull-to-refresh
		collectionView.refreshControl = UIRefreshControl()
		collectionView.refreshControl?.addTarget(self, action: #selector(self.self.startRefresh), for: .valueChanged)

        loginDataSource.append(segment: loginSection)
		loginSection.headerCellText = "In order to see your Seamail, you will need to log in first."

		threadDataSource.append(segment: noSeamailSegment)
		noSeamailSegment.append(noSeamailCell)
		
		threadDataSource.append(segment: threadSegment)
		threadSegment.activate(predicate: NSPredicate(value: false), sort: [ NSSortDescriptor(key: "lastModTime", ascending: false)],
				cellModelFactory: createCellModel)
       
		// When a user is logged in we'll set up the FRC to load the threads which that user can 'see'. Remember, CoreData
		// stores ALL the seamail we ever download, for any user who logs in on this device.
        CurrentUser.shared.tell(self, when: "loggedInUser") { observer, observed in        		
			if let currentUserID = observed.loggedInUser?.userID {
				let pred = NSCompoundPredicate(andPredicateWithSubpredicates: [
						NSPredicate(format: "fezType IN %@", ["open", "closed"] as CVarArg),
						NSPredicate(format: "ANY participants.userID == %@", currentUserID as CVarArg)])
				observer.threadSegment.changePredicate(to: pred)
        		observer.threadDataSource.register(with: observer.collectionView, viewController: observer)
        		observer.dataManager.loadSeamails { 
					DispatchQueue.main.async { observer.collectionView.reloadData() }
				}
				observer.newThreadButton.isEnabled = true
				observer.navigationController?.popToViewController(self, animated: false)
			}
       		else {
       			// If nobody's logged in, pop to root, show the login cells.
 				observer.threadSegment.changePredicate(to: NSPredicate(value: false))
				observer.loginDataSource.register(with: observer.collectionView, viewController: observer)
				observer.newThreadButton.isEnabled = false
				observer.navigationController?.popToViewController(self, animated: false)
       		}
        }?.execute()        

		title = "Seamail"
		
		if let packet = globalNav {
			_ = globalNavigateTo(packet: packet)
		}
		
//		threadSegment.log.instanceEnabled = true
    }
    
    override func viewDidAppear(_ animated: Bool) {
    	super.viewDidAppear(animated)
		loginDataSource.enableAnimations = true
		threadDataSource.enableAnimations = true
		loginSection.clearAllSensitiveFields()
		dataManager.loadSeamails()
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
	override var knownSegues : Set<GlobalKnownSegue> {
		Set<GlobalKnownSegue>([ .userProfile, .showSeamailThread ])
	}
    
	func globalNavigateTo(packet: GlobalNavPacket) -> Bool {
		// If we haven't loaded the FRC yet, cache the packet and return
		if threadSegment.frc == nil {
			globalNav = packet
			return true
		}
		globalNav = nil
		
		// Nav to a thread with the given users
		if let userNames = packet.arguments["seamailThreadParticipants"] as? Set<String> {
			let _ = self.view		// Force the view to load
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
		// Nav to the given thread ID
		else if let threadIDStr = packet.arguments["thread"] as? String, let threadID = UUID(uuidString: threadIDStr) {
			if let nav = self.navigationController, let threads = threadSegment.frc?.fetchedObjects {
				for thread in threads {
					if thread.id == threadID {
						let storyboard = UIStoryboard(name: "Main", bundle: nil)
						let existingThreadVC = storyboard.instantiateViewController(withIdentifier: "SeamailThread") as! SeamailThreadViewController
						existingThreadVC.threadModel = thread
						nav.viewControllers = [nav.viewControllers[0], existingThreadVC]
						if let globalNav = existingThreadVC as? GlobalNavEnabled {
							globalNav.globalNavigateTo(packet: packet)
						}
						return true
					}
				}
			}
		}
		return true
	}
	
	// This is the unwind segue handler for the thread view. It needs to exist, but doesn't need to do anything.
	@IBAction func dismissingSeamailThread(segue: UIStoryboardSegue) {
	}

	// This is the unwind segue from the compose view.
	@IBAction func dismissingPostingView(_ segue: UIStoryboardSegue) {
		dataManager.loadSeamails()
	}	

}
