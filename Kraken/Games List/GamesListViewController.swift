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
	

	let gamesData = GamesDataManager.shared
	lazy var dataSource = KrakenDataSource()
	lazy var gamesSegment = FilteringDataSourceSegment()
	
	// These represent the state of the current filter
	var filterList: [GamesListGame] = []				
	var favoritesPredicate: NSPredicate?
	var textPredicate: NSPredicate?


    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = "Board Games"
        
  		dataSource.register(with: collectionView, viewController: self)
		dataSource.append(segment: gamesSegment)

		gamesData.loadGamesFile {
			for gameName in self.gamesData.gameTitleArray {
				if let model = self.gamesData.gamesByName[gameName] {
					let cellModel = BoardGameCellModel(with: model)
					self.gamesSegment.append(cellModel)
				}
			}
		}
	}
    
    override func viewDidAppear(_ animated: Bool) {
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
		}
	}
	
}
