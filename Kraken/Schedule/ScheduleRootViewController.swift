//
//  ScheduleRootViewController.swift
//  Kraken
//
//  Created by Chall Fry on 8/12/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit
import CoreData

class ScheduleRootViewController: BaseCollectionViewController {
	@IBOutlet var filterView: UIVisualEffectView!
	@IBOutlet var filterViewTrailingConstraint: NSLayoutConstraint!
	

	let dataManager = EventsDataManager.shared
	var scheduleDataSource = KrakenDataSource()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Schedule"

		dataManager.loadEvents()


 		let loadingSegment = FilteringDataSourceSegment() 
 		let statusCell = OperationStatusCellModel()
 		statusCell.statusText = "Loading Events"
 		statusCell.shouldBeVisible = true
 		statusCell.showSpinner = true
 		loadingSegment.append(statusCell)
 		loadingSegment.forceSectionVisible = true
 		scheduleDataSource.append(segment: loadingSegment)
 		dataManager.tell(self, when: "networkUpdateActive") { observer, observed in
 			statusCell.shouldBeVisible = observed.networkUpdateActive  		
 		}
 		
 		let eventsSegment = FRCDataSourceSegment<Event>(withCustomFRC: dataManager.fetchedData)
		dataManager.addDelegate(eventsSegment)
  		scheduleDataSource.append(segment: eventsSegment)

		// Debug Logging
		scheduleDataSource.log.instanceEnabled = true
		eventsSegment.log.instanceEnabled = true
		loadingSegment.log.instanceEnabled = true

		eventsSegment.activate(predicate: nil, sort: nil, cellModelFactory: createCellModel)
		scheduleDataSource.register(with: collectionView, viewController: self)
		
		filterViewTrailingConstraint.constant = 0 - filterView.bounds.size.width
    }
        
	func createCellModel(_ model:Event) -> BaseCellModel {
		return EventCellModel(withModel: model)
	}

// MARK: Actions
	
	@IBAction func filterButtonTapped() {
		view.layoutIfNeeded()
		if filterView.frame.origin.x >= collectionView.bounds.maxX {
			UIView.animate(withDuration: 0.3) {
				self.filterViewTrailingConstraint.constant = 0
				self.view.layoutIfNeeded()
			}
		}
		else {
			UIView.animate(withDuration: 0.3) {
				self.filterViewTrailingConstraint.constant = 0 - self.filterView.bounds.size.width
				self.view.layoutIfNeeded()
			}
		}
	}
	
	@IBAction func rightNowButtonTapped() {
		
	}


    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destination.
        // Pass the selected object to the new view controller.
    }
    */

	@IBAction func dismissingLoginModal(_ segue: UIStoryboardSegue) {
		// Try to continue whatever we were doing before having to log in.
		if let loginVC = segue.source as? ModalLoginViewController {
			if CurrentUser.shared.isLoggedIn() {
				loginVC.segueData?.loginSuccessAction?()
			}
			else {
				loginVC.segueData?.loginFailureAction?()
			}
		}
	}	
}
