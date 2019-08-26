//
//  ScheduleRootViewController.swift
//  Kraken
//
//  Created by Chall Fry on 8/12/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit
import CoreData

@objc class ScheduleRootViewController: BaseCollectionViewController {
	@IBOutlet var filterView: UIVisualEffectView!
	@IBOutlet var filterViewTrailingConstraint: NSLayoutConstraint!
	@IBOutlet weak var disclosureSlider: UISlider!
	@IBOutlet weak var searchTextField: UITextField!
	
	@IBOutlet weak var locationPickerContainer: UIView!
	@IBOutlet weak var 	locationPicker: UIPickerView!
	

	let dataManager = EventsDataManager.shared
	var scheduleDataSource = KrakenDataSource()
	var eventsSegment: FRCDataSourceSegment<Event>?

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
 		
		let events = FRCDataSourceSegment<Event>(withCustomFRC: dataManager.fetchedData)
		dataManager.addDelegate(events)
  		scheduleDataSource.append(segment: events)
		eventsSegment = events

		// Debug Logging
		scheduleDataSource.log.instanceEnabled = false
		events.log.instanceEnabled = false
		loadingSegment.log.instanceEnabled = false

		events.activate(predicate: nil, sort: nil, cellModelFactory: createCellModel)
		scheduleDataSource.register(with: collectionView, viewController: self)
		
		filterViewTrailingConstraint.constant = 0 - filterView.bounds.size.width
		searchTextField.delegate = self
		locationPicker.dataSource = self
		locationPicker.delegate = self
		locationPickerContainer.isHidden = true
    }
	
    override func viewDidAppear(_ animated: Bool) {
		locationPicker.reloadAllComponents()
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
	
	@objc dynamic var disclosureLevel: Int = 5
	@IBAction func disclosureSliderTapped() {
		let newLevel = Int(disclosureSlider.value)
		if newLevel != disclosureLevel {
			eventsSegment?.cellModels.forEach {
				if let cell = $0 as? EventCellModel {
					cell.disclosureLevel = disclosureLevel
				}
			}
			disclosureLevel = newLevel
			print(disclosureLevel)
		}
	}
	
	var searchText: String? {
		didSet {
			var newPred: NSPredicate
			if let search = searchText, !search.isEmpty {
				newPred = NSPredicate(format:
						"title contains[cd] %@ OR eventDescription contains[cd] %@ OR location contains[cd] %@",
						search, search, search)
			}
			else {
				newPred = NSPredicate(value: true)
			}
			eventsSegment?.changePredicate(to: newPred)
		}
	}
	
	@IBAction func locationButtonTapped() {
		locationPickerContainer.isHidden = false
		filterButtonTapped()
	}
	
	@IBAction func locationDoneButtonTapped() {
		let index = locationPicker.selectedRow(inComponent: 0)
		let location = dataManager.allLocations[index]
		let newPred = NSPredicate(format: "location contains[cd] %@", location)
		eventsSegment?.changePredicate(to: newPred)
		locationPickerContainer.isHidden = true
	}
	
	@IBAction func resetButtonTapped() {
		let newPred = NSPredicate(value: true)
		eventsSegment?.changePredicate(to: newPred)
		searchTextField.text = ""
		searchTextField.resignFirstResponder()
		filterButtonTapped()
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

extension ScheduleRootViewController: UITextFieldDelegate {
	func textFieldDidBeginEditing(_ textField: UITextField) {
		activeTextEntry = textField
	}
	
	func textFieldDidEndEditing(_ textField: UITextField, reason: UITextField.DidEndEditingReason) {
		activeTextEntry = nil
	}
	
	func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
		if var textFieldContents = textField.text {
			let swiftRange: Range<String.Index> = Range(range, in: textFieldContents)!
			textFieldContents.replaceSubrange(swiftRange, with: string)
			searchText = textFieldContents
		}
		return true
	}

	func textFieldShouldClear(_ textField: UITextField) -> Bool {
		searchText = nil
		return true
	}
}

extension ScheduleRootViewController: UIPickerViewDataSource, UIPickerViewDelegate {
	func numberOfComponents(in pickerView: UIPickerView) -> Int {
		return 1
	}
	
	func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
		return dataManager.allLocations.count
	}
	
	func pickerView(_ pickerView: UIPickerView, widthForComponent component: Int) -> CGFloat {
		return view.bounds.size.width
	}

	func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
		return dataManager.allLocations[row]
	}


}
