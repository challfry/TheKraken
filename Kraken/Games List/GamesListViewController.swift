//
//  GamesListViewController.swift
//  Kraken
//
//  Created by Chall Fry on 1/30/20.
//  Copyright © 2020 Chall Fry. All rights reserved.
//

import UIKit

class GamesListViewController: BaseCollectionViewController {
	@IBOutlet var filterTextField: UITextField!
	@IBOutlet var favoriteFilterButton: UIButton!
	@IBOutlet var tableIndexView: TableIndexView!
	@IBOutlet weak var tableIndexViewTrailing: NSLayoutConstraint!
	
	let gamesData = GamesDataManager.shared
	lazy var dataSource = KrakenDataSource()
	lazy var gamesSegment = FilteringDataSourceSegment()
	
	// These represent the state of the current filter
	var filterList: [GamesListGame] = []				

    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = "Board Games"

		tableIndexView.setup(self)

  		dataSource.register(with: collectionView, viewController: self)
		dataSource.append(segment: gamesSegment)

		gamesData.loadGamesFile {
			for gameName in self.gamesData.gameTitleArray {
				if let model = self.gamesData.gamesByName[gameName] {
					let cellModel = BoardGameCellModel(with: model)
					self.gamesSegment.append(cellModel)
				}
			}
			self.updateCellVisibility()
		}
	}
    
    override func viewDidAppear(_ animated: Bool) {
    	super.viewDidAppear(animated)
		dataSource.enableAnimations = true
	}
    
	@IBAction func favoriteFilterButtonTapped(_ sender: Any) {
		favoriteFilterButton.isSelected = !favoriteFilterButton.isSelected
		updateCellVisibility()
	}
	
	@IBAction func textFieldChanged(_ sender: Any) {
		updateCellVisibility()
	}
	
	func updateCellVisibility() {
		filterList.removeAll()
		for cell in gamesSegment.allCellModels {
			guard let bgCell = cell as? BoardGameCellModel, let model = bgCell.model else { continue }
			var shouldBeVisible: Bool = true
			
			if favoriteFilterButton.isSelected, bgCell.model?.isFavorite == false {
				shouldBeVisible = false
			}
			if shouldBeVisible, let searchText = filterTextField.text, !searchText.isEmpty {
				if model.gameName.range(of: searchText, options: .caseInsensitive) == nil &&
						model.bggGameName?.range(of: searchText, options: .caseInsensitive) == nil 
					//	model.gameDescription?.range(of: searchText, options: .caseInsensitive) == nil
						 {
					shouldBeVisible = false
				}
			}
			bgCell.shouldBeVisible = shouldBeVisible
			if shouldBeVisible {
				filterList.append(model)
			}
		}
		
		let newOffset = filterList.count > 100 ? 0 : tableIndexView.bounds.size.width
		if newOffset != tableIndexViewTrailing.constant {
			UIView.animate(withDuration: 0.3, animations: {
				self.tableIndexViewTrailing.constant = newOffset
				self.view.layoutIfNeeded()
			})
		}
	}
}

extension GamesListViewController: TableIndexDelegate {
	func itemNameAt(percentage: CGFloat) -> String {
		guard filterList.count > 0 else { return "" }
		
		var arrayOffset = Int(CGFloat(filterList.count) * percentage)
		arrayOffset = min(max(0, arrayOffset), filterList.count - 1)
		
		return filterList[arrayOffset].gameName
	}
	
	func scrollToPercentage(_ percentage: CGFloat) {
		var arrayOffset = Int(CGFloat(filterList.count) * percentage)
		arrayOffset = min(max(0, arrayOffset), filterList.count - 1)
		collectionView.scrollToItem(at: IndexPath(row: arrayOffset, section: 0), at: .centeredVertically, animated: true)
	}

}
