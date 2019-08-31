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
	let scheduleLayout = ScheduleLayout()
	var scheduleDataSource = KrakenDataSource()
	var eventsSegment: FRCDataSourceSegment<Event>?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Schedule"

		dataManager.loadEvents()
		collectionView.collectionViewLayout = scheduleLayout
		
		// Manually register the nib for the section header view
		let headerNib = UINib(nibName: "EventSectionHeaderView", bundle: nil)
		collectionView.register(headerNib, forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, 
				withReuseIdentifier: "EventSectionHeaderView")
		scheduleDataSource.buildSupplementaryView = createSectionHeaderView

		// Add the loading segment up top
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
 		
		// Then, the events segment
		let events = FRCDataSourceSegment<Event>(withCustomFRC: dataManager.fetchedData)
		dataManager.addDelegate(events)
  		scheduleDataSource.append(segment: events)
		eventsSegment = events
		scheduleLayout.eventsSegment = eventsSegment

		// Debug Logging
//		scheduleDataSource.log.instanceEnabled = true
//		events.log.instanceEnabled = true
//		loadingSegment.log.instanceEnabled = true

		events.activate(predicate: nil, sort: nil, cellModelFactory: createCellModel)
		scheduleDataSource.register(with: collectionView, viewController: self)
		
		filterViewTrailingConstraint.constant = 0 - filterView.bounds.size.width
		searchTextField.delegate = self
		locationPicker.dataSource = self
		locationPicker.delegate = self
		locationPickerContainer.isHidden = true
    }
	
    override func viewDidAppear(_ animated: Bool) {
		scheduleDataSource.enableAnimations = true
		locationPicker.reloadAllComponents()
	}
        
	func createCellModel(_ model:Event) -> BaseCellModel {
		return EventCellModel(withModel: model)
	}
	
	func createSectionHeaderView(_ cv: UICollectionView, _ kind: String, _ indexPath: IndexPath, 
			_ cellModel: BaseCellModel?) -> UICollectionReusableView {
		if let newView = cv.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: "EventSectionHeaderView", 
				for: indexPath) as? EventSectionHeaderView {
			if let eventCellModel = cellModel as? EventCellModel, let event = eventCellModel.model as? Event,
					let sectionStartTime = event.startTime {
				newView.setTime(to: sectionStartTime)
			}
			return newView
		}
		return UICollectionReusableView()
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
			eventsSegment?.cellModelSections.forEach {
				$0.forEach {
					if let cell = $0 as? EventCellModel {
						cell.disclosureLevel = newLevel
					}
				}
			}
			disclosureLevel = newLevel

			// Tell the layout that we're focusing on the topmost visible cell--this makes the layout object
			// try to keep that cell at top of screen.
			if collectionView.visibleCells.count > 0 {
				var focusCell = collectionView.visibleCells[0]
				collectionView.visibleCells.forEach { if $0.frame.minY < focusCell.frame.minY { focusCell = $0 } }
				
				if let focusEventCell = focusCell as? EventCell, let cellModel = focusEventCell.cellModel as? EventCellModel {
					scheduleLayout.focusCellModel = cellModel
				}
			}
			
			scheduleLayout.disclosureLevel = newLevel
			scheduleDataSource.invalidateLayout()
			print("Setting all cell levels to \(newLevel)")
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

// at disclosure 5, cv is 73708 high. 155 sections, 395 cells Av cell height is 186.
// at 4, cv is 73587 high. still 186 per cell.
// at 3, cv is 33450 high. 84 per cell
// at 2, cv is 24590 high. 62 per cell
// at 0, cv is 16439 high. 41 per cell.


// MARK: -
class ScheduleLayout: UICollectionViewLayout {
	var sectionHeaderPositions: [CGRect] = []
	var cellPositions: [[CGRect]] = []
	var privateContentSize: CGSize = CGSize(width: 0, height: 0)
	var focusCellModel: EventCellModel?
	var disclosureLevel: Int = 5
	
	weak var eventsSegment: FRCDataSourceSegment<Event>?
		
	override init() {
		super.init()
	}
	
	required init?(coder aDecoder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}
	
	func showingSectionHeaders() -> Bool {
		return disclosureLevel >= 1
	}
	
	override func prepare() {
		guard let cv = collectionView, let ds = cv.dataSource, let del = cv.delegate else { return }
		
		let flowDelegate = del as? UICollectionViewDelegateFlowLayout
		cellPositions.removeAll()
		sectionHeaderPositions.removeAll()
		let cvWidth = cv.bounds.width
		
		// Iterate through each cell in each section, get the cell's size, and place each cell in a big stack.
		var pixelOffset: CGFloat = 0.0
		let sectionCount = ds.numberOfSections?(in: cv) ?? 1
		for sectionIndex in 0..<sectionCount {
			
			// Only show cell headers if the disclosure level is high enough
			if showingSectionHeaders() {
				//
				if sectionIndex == 0 {
					sectionHeaderPositions.append(CGRect(x: 0, y: 0, width: 0, height: 0))
				}
				else {
					sectionHeaderPositions.append(CGRect(x: 0, y: pixelOffset, width: cvWidth, height: 27))
					pixelOffset += 27
				}
			}
			
			let cellCount = ds.collectionView(cv, numberOfItemsInSection: sectionIndex)
			var cellLocations = [CGRect]()
			for cellIndex in 0..<cellCount {
				// In more generic code if sizeForItemAt isn't implemented we get the value from other sources.
				let cellSize = flowDelegate?.collectionView?(cv, layout: self, sizeForItemAt: 
						IndexPath(row: cellIndex, section: sectionIndex)) ?? CGSize(width: cvWidth, height: 50)
				cellLocations.append(CGRect(x: CGFloat(0.0), y: pixelOffset, width: cvWidth, height: cellSize.height))
				pixelOffset += cellSize.height
			}
			cellPositions.append(cellLocations)
		}
		
		privateContentSize = CGSize(width: cvWidth, height: pixelOffset)
	}
	
	override var collectionViewContentSize: CGSize {
		return privateContentSize
	}

	override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {	
		var result: [UICollectionViewLayoutAttributes] = []
		
		// Better to use a binary search for this, but a strict binary search of a multilevel array is painful.
		var indexPath = IndexPath(row: 0, section: 0)
		let numSections = cellPositions.count
		while indexPath.section < numSections {
			if cellPositions[indexPath.section].count > 0, cellPositions[indexPath.section][0].maxY > rect.origin.y {
				if cellPositions[indexPath.section][0].origin.y > rect.origin.y {
					repeat {
						indexPath.section -= 1
					} while cellPositions[indexPath.section].count == 0 && indexPath.section > 0
				}
				break
			}
			indexPath.section += 1
		}
		if indexPath.section >= numSections {
			return nil
		}

		// Now find the first cell in this section that intersects the rect
		while indexPath.row < cellPositions[indexPath.section].count {
			if cellPositions[indexPath.section][indexPath.row].maxY > rect.origin.y {
				break
			}
			indexPath.row += 1
		}
		
		// Create layout attrs for every cell in the rect, add to result
		let rectYMax = rect.maxY
		while true {
		
			// Skip empty sections
			while indexPath.row >= cellPositions[indexPath.section].count {
				indexPath.section += 1
				indexPath.row = 0
				if indexPath.section >= cellPositions.count {
					break
				}
			}
			
			// Break if we're past the bottom of the rect
			if cellPositions[indexPath.section][indexPath.row].origin.y > rectYMax {
				break
			}
			let val = UICollectionViewLayoutAttributes(forCellWith: indexPath)
			val.isHidden = false
			val.frame = cellPositions[indexPath.section][indexPath.row]
			result.append(val)
			
			indexPath.row += 1
			if indexPath.row >= cellPositions[indexPath.section].count {
				indexPath.row = 0
				indexPath.section += 1
				if indexPath.section >= cellPositions.count {
					break
				}
			}
		}
		
		// Add in layoutAttributes for section headers
		if showingSectionHeaders() {
			for index in 0..<sectionHeaderPositions.count {
				let sectionHeaderRect = sectionHeaderPositions[index]
				if sectionHeaderRect.size.height > 0, sectionHeaderRect.intersects(rect) {
					let val = UICollectionViewLayoutAttributes(forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
							with: IndexPath(row: 0, section: index))
					val.isHidden = false
					val.frame = sectionHeaderRect
					result.append(val)
				}
				if sectionHeaderRect.minY > rect.maxY {
					break
				}
			}
		}
		
		return result
	}
	
	override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
		let result = UICollectionViewLayoutAttributes(forCellWith: indexPath)
		
		let cellRect = cellPositions[indexPath.section][indexPath.row]
		result.frame = cellRect
		result.isHidden = false
		
		return result
	}
	
	override func layoutAttributesForSupplementaryView(ofKind elementKind: String, at indexPath: IndexPath) 
			-> UICollectionViewLayoutAttributes? {
		if !showingSectionHeaders() || indexPath.count < 2 || indexPath.row != 0 {
			return nil
		}
		
		let result = UICollectionViewLayoutAttributes(forCellWith: indexPath)
		let cellRect = sectionHeaderPositions[indexPath.section]
		result.frame = cellRect
		result.isHidden = false
		
		return result
	}

	override func indexPathsToInsertForSupplementaryView(ofKind elementKind: String) -> [IndexPath] {
		if !showingSectionHeaders() {
			return []
		}

		var result = [IndexPath]()
		for index in 1..<sectionHeaderPositions.count {
			result.append(IndexPath(row: 0, section: index))
		}
		
		return result
	}

	override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
		if let cv = collectionView, newBounds.size.width != cv.bounds.size.width {
			return true
		}
		return false
	}
	
	override func targetContentOffset(forProposedContentOffset proposedContentOffset: CGPoint) -> CGPoint {
		guard let focusCellModel = focusCellModel, let eventsSegment = eventsSegment else { return proposedContentOffset }
		
		if var focusIndexPath = eventsSegment.indexPathNearest(to: focusCellModel) {
		
			// Hack
			focusIndexPath.section += 1
		
			let cellRect = cellPositions[focusIndexPath.section][focusIndexPath.row]
			return cellRect.origin
		}
		
		return proposedContentOffset
	}
}
