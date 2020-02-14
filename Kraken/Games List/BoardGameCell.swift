//
//  BoardGameCell.swift
//  Kraken
//
//  Created by Chall Fry on 1/31/20.
//  Copyright © 2020 Chall Fry. All rights reserved.
//

import UIKit

@objc protocol BoardGameCellBindingProtocol: KrakenCellBindingProtocol {
	var model: GamesListGame? { get set }
}

@objc class BoardGameCellModel: BaseCellModel, BoardGameCellBindingProtocol {
	private static let validReuseIDs = [ "BoardGameCell" : BoardGameCell.self ]
	override class var validReuseIDDict: [String: BaseCollectionViewCell.Type ] { return validReuseIDs }

    @objc dynamic var model: GamesListGame?
    
    init(with: GamesListGame) {
    	model = with
    	super.init(bindingWith: BoardGameCellBindingProtocol.self)
    }
    
    init() {
		super.init(bindingWith: BoardGameCellBindingProtocol.self)
    }
}

class BoardGameCell: BaseCollectionViewCell, BoardGameCellBindingProtocol {
	private static let cellInfo = [ "BoardGameCell" : PrototypeCellInfo("BoardGameCell") ]
	override class var validReuseIDDict: [ String: PrototypeCellInfo ] { return cellInfo }

	@IBOutlet var gameTitleLabel: UILabel!
	@IBOutlet var publishYearLabel: UILabel!
	@IBOutlet var favoriteButton: UIButton!
	@IBOutlet var minAgeLabel: UILabel!
	@IBOutlet var playerCountLabel: UILabel!
	@IBOutlet var playTimeLabel: UILabel!
	@IBOutlet var ratingsLabel: UILabel!
	@IBOutlet var complexityLabel: UILabel!
	@IBOutlet var 	expandsLabel: UILabel!
	@IBOutlet var 	numCopiesLabel: UILabel!
	@IBOutlet var 	descriptionLabel: UILabel!
	@IBOutlet var 	donatedByLabel: UILabel!
	@IBOutlet var 	stackViewHeightConstraint: NSLayoutConstraint!
	
	var model: GamesListGame? {
    	didSet {
    		clearObservations()
    		
    		if let model = model {
	    		gameTitleLabel.text = model.bggGameName ?? model.gameName
	    		publishYearLabel.text = model.yearPublished
	    		
	    		addObservation(model.tell(self, when: "isFavorite") { observer, observed in 
	    			observer.favoriteButton.isSelected = observed.isFavorite
	    		}?.execute())
	    		
	    		if let minAge = model.minAge {
		    		minAgeLabel.text = "ages \(minAge)+"
				}
				else if model.minPlayers == nil, model.minPlayingTime == nil, model.gameDescription == nil,
						model.avgRating == nil {
					// If there's no iitem info, say so here
					minAgeLabel.text = "No info available"
				}
				else {
					minAgeLabel.text = nil
				}
				
				if let minPlayers = model.minPlayers, let maxPlayers = model.maxPlayers {
					if minPlayers == maxPlayers {
						playerCountLabel.text = "\(minPlayers) players"
					}
					else {
						playerCountLabel.text = "\(minPlayers)-\(maxPlayers) players"
					}
				}
				else if let minPlayers = model.minPlayers {
					playerCountLabel.text = "\(minPlayers)+ players"
				}
				else if let maxPlayers = model.maxPlayers {
					playerCountLabel.text = "up to \(maxPlayers) players"
				}
				else {
					playerCountLabel.text = nil
				}
				
				if let minPlayTime = model.minPlayingTime, let maxPlayTime = model.maxPlayingTime {
					if minPlayTime == maxPlayTime {
						playTimeLabel.text = "\(minPlayTime) minutes"
					}
					else {
						playTimeLabel.text = "\(minPlayTime)-\(maxPlayTime) minutes"
					}
				}
				else if let minPlayTime = model.minPlayingTime {
					playTimeLabel.text = "\(minPlayTime)+ minutes"
				}
				else if let maxPlayTime = model.maxPlayingTime {
					playTimeLabel.text = "< \(maxPlayTime) minutes"
				}
				else {
					playTimeLabel.text = nil
				}
				
				if let rating = model.avgRating, rating > 0.0 {
					let ratingString = String(format: "Rating: %.2f", rating)
					ratingsLabel.text = ratingString
				}
				else {
					ratingsLabel.text = nil
				}
				
				if let complexity = model.complexity, complexity > 0.0 {
					let complexityString = String(format: "Complexity: %.2f", complexity)
					complexityLabel.text = complexityString
				}
				else {
					complexityLabel.text = nil
				}
				
				if let expandsGame = model.expands {
					expandsLabel.text = "Expansion for: \(expandsGame)"
				}
				else {
					expandsLabel.text = nil
				}
				
				// Only show the Num Copies label if there's more than one copy of the game
				if model.numCopies > 1 {
					numCopiesLabel.text = "\(model.numCopies) copies"
				}
				else {
					numCopiesLabel.text = nil
				}
				
				if let donatedBy = model.donatedBy {
					donatedByLabel.text = "Donated to Library by: \(donatedBy)"
				}
				else {
					donatedByLabel.text = nil
				}
				
				var extendedDescription: String = ""
				if let desc = model.gameDescription {
					extendedDescription = desc
				}
				if let notes = model.notes {
					extendedDescription.append("\n\nNotes: \(notes)")
				}
				
				if !extendedDescription.isEmpty {
					descriptionLabel.attributedText = StringUtilities.cleanupText(extendedDescription, addLinks: false)
				}
				else {
					descriptionLabel.text = nil
				}
			}
			cellSizeChanged()
    	}
    }
    
	override func awakeFromNib() {
        super.awakeFromNib()

		// Font styling
		gameTitleLabel.styleFor(.body)
		publishYearLabel.styleFor(.body)
		favoriteButton.styleFor(.body)
		minAgeLabel.styleFor(.body)
		playerCountLabel.styleFor(.body)
		playTimeLabel.styleFor(.body)
		ratingsLabel.styleFor(.body)
		complexityLabel.styleFor(.body)
		expandsLabel.styleFor(.body)
		numCopiesLabel.styleFor(.body)
		donatedByLabel.styleFor(.body)
		descriptionLabel.styleFor(.body)
		
		allowsSelection = true
		
		expandsLabel.text = nil
		numCopiesLabel.text = nil
		donatedByLabel.text = nil
		descriptionLabel.text = nil
	}

	override var isHighlighted: Bool {
		didSet {
			if !isPrototypeCell, isHighlighted == oldValue { return }
			standardHighlightHandler()
		}
	}
	
	override var privateSelected: Bool {
		didSet {
			if !isPrototypeCell, privateSelected == oldValue { return }
			standardSelectionHandler()
			
			if isPrototypeCell {
				stackViewHeightConstraint.isActive = !privateSelected
			}
			else {
				UIView.animate(withDuration: 0.3) {
					self.stackViewHeightConstraint.isActive = !self.privateSelected
					self.cellSizeChanged()
					self.layoutIfNeeded()
				}
			}
		}
	}

	@IBAction func favoriteButtonTapped() {
		GamesDataManager.shared.setFavoriteGameStatus(for: model, to: !favoriteButton.isSelected)
	}
}
