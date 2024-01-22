//
//  LFGRootViewController.swift
//  Kraken
//
//  Created by Chall Fry on 12/10/22.
//  Copyright © 2022 Chall Fry. All rights reserved.
//

import Foundation
import UIKit
import CoreData

class LFGRootViewController: BaseCollectionViewController, GlobalNavEnabled {

	@IBOutlet weak var createLFGButton: UIBarButtonItem!
	
	// Used to store incoming global nav until our view is loaded. 
	var globalNav: GlobalNavPacket?

	let loginDataSource = KrakenDataSource()
	let loginSection = LoginDataSourceSegment()

	let lfgDataSource = KrakenDataSource()
	lazy var joinedHeaderSegment = FilteringDataSourceSegment()
	lazy var joinedSegment = FRCDataSourceSegment<SeamailThread>()
	lazy var openHeaderSegment = FilteringDataSourceSegment()
	lazy var openSegment = FRCDataSourceSegment<SeamailThread>()
	let dataManager = SeamailDataManager.shared

	lazy var joinedHeaderCell: LabelCellModel = {
		let labelText = NSAttributedString(string: "LFGs you've already joined:", 
				attributes: [.font: UIFont.systemFont(ofSize: 17, symbolicTraits: .traitBold)])
		let cell = LabelCellModel(labelText)
		cell.bgColor = UIColor(named: "Info Title Background")
		cell.shouldBeVisible = true
		return cell
	}()
	
	lazy var noJoinedLFGsCell: LabelCellModel = {
		let cell = LabelCellModel("You haven't joined any LFGs yet." )
		cell.bgColor = UIColor(named: "Text View Background")
		
		joinedSegment.wrapper.tell(cell, when: "isEmpty") { observer, observed in
			observer.shouldBeVisible = observed.isEmpty
		}?.execute()
		
		return cell
	}()
	
	lazy var noOpenLFGsCell: LabelCellModel = {
		let cell = LabelCellModel("There are no upcoming LFGs to join." )
		cell.bgColor = UIColor(named: "Text View Background")
		
		openSegment.wrapper.tell(cell, when: "isEmpty") { observer, observed in
			observer.shouldBeVisible = observed.isEmpty
		}?.execute()
		
		return cell
	}()

	lazy var openHeaderCell: LabelCellModel = {
		let labelText = NSAttributedString(string: "LFGs you could join:", 
				attributes: [.font: UIFont.systemFont(ofSize: 17, symbolicTraits: .traitBold)])
		let cell = LabelCellModel(labelText)
		cell.bgColor = UIColor(named: "Info Title Background")
		cell.shouldBeVisible = true
		return cell
	}()
	
// MARK: - Methods
	
	override func viewDidLoad() {
        super.viewDidLoad()
        startRefresh()
        
		// Pull-to-refresh
		collectionView.refreshControl = UIRefreshControl()
		collectionView.refreshControl?.addTarget(self, action: #selector(self.self.startRefresh), for: .valueChanged)

        loginDataSource.append(segment: loginSection)
		loginSection.headerCellText = "In order to see Looking For Group activities, you will need to log in first."

		lfgDataSource.append(segment: joinedHeaderSegment)
		joinedHeaderSegment.append(joinedHeaderCell)
		joinedHeaderSegment.append(noJoinedLFGsCell)
		
		lfgDataSource.append(segment: joinedSegment)
		joinedSegment.activate(predicate: NSPredicate(value: false), sort: [ NSSortDescriptor(key: "lastModTime", ascending: false)],
				cellModelFactory: createCellModel)
       
		lfgDataSource.append(segment: openHeaderSegment)
		openHeaderSegment.append(openHeaderCell)
		openHeaderSegment.append(noOpenLFGsCell)

		lfgDataSource.append(segment: openSegment)
		openSegment.activate(predicate: NSPredicate(value: false), sort: [ NSSortDescriptor(key: "startTime", ascending: true)],
				cellModelFactory: createCellModel)
       
		// When a user is logged in we'll set up the FRC to load the threads which that user can 'see'. Remember, CoreData
		// stores ALL the seamail we ever download, for any user who logs in on this device.
        CurrentUser.shared.tell(self, when: "loggedInUser") { observer, observed in        		
			if let currentUserID = observed.loggedInUser?.userID {
				let joinedPred = NSCompoundPredicate(andPredicateWithSubpredicates: [
						NSPredicate(format: "NOT (fezType IN %@)", ["open", "closed"] as CVarArg),
						NSPredicate(format: "ANY participants.userID == %@", currentUserID as CVarArg)])
				observer.joinedSegment.changePredicate(to: joinedPred)
				let openPred = NSCompoundPredicate(andPredicateWithSubpredicates: [
						NSPredicate(format: "NOT (fezType IN %@)", ["open", "closed"] as CVarArg),
						NSPredicate(format: "SUBQUERY(participants, $x, $x.userID == %@).@count == 0", currentUserID as CVarArg),
						NSPredicate(format: "startTime > %@", cruiseCurrentDate() - 3600 as CVarArg),
						NSPredicate(format: "cancelled == false"),
						])
				observer.openSegment.changePredicate(to: openPred)
        		observer.lfgDataSource.register(with: observer.collectionView, viewController: observer)
        		observer.dataManager.loadOpenLFGs()
        		observer.dataManager.loadSeamails()
				observer.navigationController?.popToViewController(self, animated: false)
				observer.createLFGButton.isEnabled = true
			}
       		else {
       			// If nobody's logged in, pop to root, show the login cells.
 				observer.openSegment.changePredicate(to: NSPredicate(value: false))
 				observer.joinedSegment.changePredicate(to: NSPredicate(value: false))
				observer.loginDataSource.register(with: observer.collectionView, viewController: observer)
				observer.navigationController?.popToViewController(self, animated: false)
				observer.createLFGButton.isEnabled = false
       		}
        }?.execute()        

		title = "LFG"
		
		if let packet = globalNav {
			_ = globalNavigateTo(packet: packet)
		}
		
//		joinedSegment.log.instanceEnabled = true
    }
    
    override func viewDidAppear(_ animated: Bool) {
    	super.viewDidAppear(animated)
		loginDataSource.enableAnimations = true
		lfgDataSource.enableAnimations = true
		loginSection.clearAllSensitiveFields()
		dataManager.loadSeamails()
		dataManager.loadOpenLFGs()
	}

	@objc func startRefresh() {
		dataManager.loadOpenLFGs {
			self.dataManager.loadSeamails {
				DispatchQueue.main.async { 
					self.collectionView.refreshControl?.endRefreshing()
				}
			}
		}
    }

	// Gets called from within collectionView:cellForItemAt:
	func createCellModel(_ model: SeamailThread) -> BaseCellModel {
		let cellModel = LFGCellModel(withModel: model, reuse: "LFGCell")
		return cellModel
	}

// MARK: Actions
	@IBAction func createLFGTapped() {
		performKrakenSegue(.lfgCreateEdit, sender: nil)
	}

// MARK: Navigation
	override var knownSegues : Set<GlobalKnownSegue> {
		Set<GlobalKnownSegue>([ .userProfile_User, .userProfile_Name, .showSeamailThread, .lfgCreateEdit ])
	}

	func globalNavigateTo(packet: GlobalNavPacket) -> Bool {
		return true
	}
	
	// This is the unwind segue from the compose view.
	@IBAction func dismissingPostingView(_ segue: UIStoryboardSegue) {
		dataManager.loadSeamails()
	}	

}
