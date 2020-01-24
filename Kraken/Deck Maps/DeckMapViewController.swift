//
//  DeckMapViewController.swift
//  Kraken
//
//  Created by Chall Fry on 10/29/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit
import PDFKit

class DeckMapViewController: UIViewController {
	@IBOutlet weak var pdfView: PDFView!
	@IBOutlet weak var deckSegmentedControl: UISegmentedControl!
	@IBOutlet weak var findOverlayView: UIVisualEffectView!
	@IBOutlet weak var findOverlayTrailingConstraint: NSLayoutConstraint!
	@IBOutlet weak var textSearchField: UITextField!
	@IBOutlet weak var searchResultsTable: UITableView!
	@IBOutlet weak var searchResultsHeightConstraint: NSLayoutConstraint!
	
	var roomToShow: DeckDataManager.RoomLocation?
	var currentDeck: Int = 1
	var roomSuggestions: [DeckDataManager.RoomLocation] = []
	
	override func viewDidLoad() {
        super.viewDidLoad()
        
        // Don't show the no-network banner in this view -- the maps are all local
        if let nav = self.navigationController as? KrakenNavController {
        	nav.showNetworkBanner = false
        }
        
        pdfView.document = DeckDataManager.shared.document
        pdfView.displayMode = .singlePage
		currentDeck = 1
		pdfView.minScaleFactor = 1.0
		pdfView.maxScaleFactor = 3.0
		findOverlayTrailingConstraint.constant = 0 - findOverlayView.bounds.size.width
		
		// Set scale factors based on page size and view size
		if let page0 = pdfView.document?.page(at: 0) {
			let bounds = page0.bounds(for: .cropBox)
			pdfView.minScaleFactor = 1.14 * pdfView.bounds.size.height / bounds.size.height
			pdfView.maxScaleFactor = 0.97 * pdfView.bounds.size.width / bounds.size.width
		}
		
		searchResultsHeightConstraint.constant = 0
		searchResultsTable.estimatedRowHeight = 30		
	}
	
	override func viewWillAppear(_ animated: Bool) {
		if let initialRoom = roomToShow {
			pointAtRoom(initialRoom)
		}
		else {
			DeckDataManager.shared.removePointer()
		}

		// Get the deck that is being displayed, set UI Widgets to reflect that.
		if let page = pdfView.currentPage {
			currentDeck = (pdfView.document?.index(for: page) ?? 0) + 1
		}
		
		deckSegmentedControl.selectedSegmentIndex = currentDeck - 1
		setNavBarTitle()
	}
    
	// Shows/hides the search panel
	@IBAction func findButtonTapped(_ sender: Any) {
		if findOverlayTrailingConstraint.constant == 0 {
			findOverlayTrailingConstraint.constant = 0 - findOverlayView.bounds.size.width
			textSearchField.resignFirstResponder()
		}
		else {
			findOverlayTrailingConstraint.constant = 0
			textSearchField.becomeFirstResponder()
		}
	}
	
	// Changes decks.
	@IBAction func deckSegmentedControlTapped(_ sender: Any) {
		let segment = deckSegmentedControl.selectedSegmentIndex 
		currentDeck = segment + 1
		setNavBarTitle()
		if let pdfPage = pdfView.document?.page(at: segment) {
			pdfView.go(to: pdfPage)
		}
	}
	
	func setNavBarTitle() {
		var deckName: String
		switch currentDeck {
		case 1:	deckName = "Main Deck"
		case 2:	deckName = "Lower Promenade Deck"
		case 3:	deckName = "Promenade Deck"
		case 4:	deckName = "Upper Promenade Deck"
		case 5:	deckName = "Verandah Deck"
		case 6:	deckName = "Upper Verandah Deck"
		case 7:	deckName = "Rotterdam Deck"
		case 8:	deckName = "Navigation Deck"
		case 9:	deckName = "Lido Deck"
		case 10: deckName = "Panorama Deck"
		case 11: deckName = "Observation Deck"
		default: deckName = "Unknown Deck"
		}
		
		self.title = "\(currentDeck) - \(deckName)"
		deckSegmentedControl.selectedSegmentIndex = currentDeck - 1
	}
	
	// Other parts of the app should generally call this fn to open the map initially pointing to a specific room.
	func pointAtRoomNamed(_ roomName: String) {
		if let room = DeckDataManager.shared.findRoom(named: roomName) {
			pointAtRoom(room)
		}
		else {
			// If the given string didn't match a room, be sure to remove the pointer.
			DeckDataManager.shared.removePointer()
		}
	}
		
	func pointAtRoom(_ room: DeckDataManager.RoomLocation) {
		if !isViewLoaded {
			roomToShow = room
			return
		}
		currentDeck = DeckDataManager.shared.pointAtRoom(room, forView: pdfView)
		setNavBarTitle()
	}

}

extension DeckMapViewController: UITextFieldDelegate {
	func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
		if var textFieldContents = textField.text {
			let swiftRange: Range<String.Index> = Range(range, in: textFieldContents)!
			textFieldContents.replaceSubrange(swiftRange, with: string)
	
			updateCompletions(newText: textFieldContents)
		}
		
		return true
	}
	
	func textFieldShouldClear(_ textField: UITextField) -> Bool {
		updateCompletions(newText: "")
		return true
	}
	
	func updateCompletions(newText: String) {
		let completions = DeckDataManager.shared.findRooms(matching: newText)
		roomSuggestions = completions
		searchResultsTable.reloadData()
		searchResultsHeightConstraint.constant = searchResultsTable.contentSize.height
		
		UIView.animate(withDuration: 0.3) {
		//	self.view.setNeedsLayout()
		//	self.view.setNeedsLayout()
			self.searchResultsTable.superview!.layoutIfNeeded()
		}
	}
}

extension DeckMapViewController: UITableViewDataSource, UITableViewDelegate {
	func numberOfSections(in tableView: UITableView) -> Int {
		return 1
    }

	func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		return roomSuggestions.count
	}
	
	func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		var cell: SearchButtonCell? = tableView.dequeueReusableCell(withIdentifier: "SearchButtonCell")
				as? SearchButtonCell
		if cell == nil {
			cell = UITableViewCell(style: .default, reuseIdentifier: "SearchButtonCell") as? SearchButtonCell
		}
		
		if roomSuggestions.count > indexPath.row {
			let suggestion = roomSuggestions[indexPath.row]
			cell?.titleButton.setTitle(suggestion.name, for: .normal)
			cell?.deckLabel.text = "Deck \(suggestion.deck)"
			cell?.roomLocation = suggestion
			cell?.vc = self
		}
		return cell ?? UITableViewCell(style: .default, reuseIdentifier: "SearchButtonCell")
	}
		

}

class SearchButtonCell: UITableViewCell {
	@IBOutlet weak var titleButton: UIButton!
	@IBOutlet weak var deckLabel: UILabel!
	
	var roomLocation: DeckDataManager.RoomLocation?
	var vc: DeckMapViewController?
	
	@IBAction func buttonTapped(_ sender: Any) {
		if let room = roomLocation {
			vc?.pointAtRoom(room)
			vc?.findButtonTapped(self)
		}
	}
}
