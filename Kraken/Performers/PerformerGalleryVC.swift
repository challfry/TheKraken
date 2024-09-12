//
//  PerformerGalleryVC.swift
//  Kraken
//
//  Created by Chall Fry on 9/1/24.
//  Copyright © 2024 Chall Fry. All rights reserved.
//

import Foundation
import UIKit
import SwiftUI


class PerformerGalleryViewController: BaseCollectionViewController, GlobalNavEnabled {
	var showOfficialPerformers: Bool = true

	let performersData = PerformerDataManager.shared
	var dataSource = KrakenDataSource()
	var searchSegment = FilteringDataSourceSegment()
		lazy var searchCell = PerformerSearchCellModel(searchAction: filterPerformers)
	var performersSegment = FRCDataSourceSegment<Performer>()
		
    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = "Performers"
        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 10.0
        layout.sectionInset = UIEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
        collectionView.collectionViewLayout = layout
        
        performersData.updatePerformers(official: showOfficialPerformers)
        
		// Register ds stuff
		searchSegment.append(searchCell)
		performersSegment.loaderDelegate = self
		performersSegment.activate(predicate: NSPredicate(format: "isOfficialPerformer == %d", showOfficialPerformers), 
						sort: [ NSSortDescriptor(key: "sortOrder", ascending: true)], 
						cellModelFactory: createCellModel)
		dataSource.append(segment: searchSegment)
		dataSource.append(segment: performersSegment)
  		dataSource.register(with: collectionView, viewController: self)
	}

    override func viewDidAppear(_ animated: Bool) {
    	super.viewDidAppear(animated)
		dataSource.enableAnimations = true
	}
	
	// Gets called from within collectionView:cellForItemAt:. Creates cell models from FRC result objects.
	func createCellModel(_ model: Performer) -> BaseCellModel {
		let cellModel = PerformerGalleryCellModel(with: model, showImage: searchCell.showImages)
		searchCell.tell(cellModel, when: "showImages") { observer, observed in
			observer.showImage = observed.showImages
		}?.execute()
		return cellModel
	}
	
	func filterPerformers(_ searchString: String) {
		if searchString.isEmpty {
			performersSegment.changePredicate(to: NSPredicate(format: "isOfficialPerformer == %d", showOfficialPerformers))
		}
		else {
			performersSegment.changePredicate(to: NSPredicate(format: "isOfficialPerformer == %d AND name CONTAINS[cd] %@", 
					showOfficialPerformers, searchString))
		}
	}
	
	// MARK: Navigation
	override var knownSegues : Set<GlobalKnownSegue> {
		Set<GlobalKnownSegue>([ .performerBio ])
	}
	
	@discardableResult func globalNavigateTo(packet: GlobalNavPacket) -> Bool {
		if let segue = packet.segue, knownSegues.contains(segue) {
			performKrakenSegue(segue, sender: packet.sender)
			return true
		}
		if let official = packet.sender as? Bool {
			showOfficialPerformers = official
		}
		return false
	}

}

extension PerformerGalleryViewController: FRCDataSourceLoaderDelegate {
	func userIsViewingCell(at indexPath: IndexPath) {
	}
}

// MARK: Search Cell
@objc protocol PerformerSearchCellBindingProtocol: KrakenCellBindingProtocol {
	var searchText: String { get set }
	var showImages: Bool { get set }
}

@objc class PerformerSearchCellModel: BaseCellModel, PerformerSearchCellBindingProtocol {
	private static let validReuseIDs = [ "PerformerSearchCell" : PerformerSearchCell.self ]
	override class var validReuseIDDict: [String: BaseCollectionViewCell.Type ] { return validReuseIDs }

    @objc dynamic var searchText: String = ""
    @objc dynamic var showImages: Bool = false
	var searchAction: (String) -> Void

	init(searchAction: @escaping (String) -> Void) {
		self.searchAction = searchAction
    	super.init(bindingWith: PerformerSearchCellBindingProtocol.self)
    }
}

class PerformerSearchCell: BaseCollectionViewCell, PerformerSearchCellBindingProtocol {
 	private static let cellInfo = [ "PerformerSearchCell" : PrototypeCellInfo("PerformerSearchCell") ]
	override class var validReuseIDDict: [ String: PrototypeCellInfo ] { return cellInfo }

	var searchText: String = "" {
		didSet {
			if textField.text != searchText {
				textField.text = searchText
			}
		}
	}
    var showImages: Bool = false

	@IBOutlet weak var textField: UITextField!
	@IBOutlet weak var picsButton: UIButton!
	@IBOutlet weak var widthConstraint: NSLayoutConstraint!
		
	@IBAction func searchTextChanged(_ sender: Any) {
		if let m = cellModel as? PerformerSearchCellModel {
			m.searchText = textField.text ?? ""
			m.searchAction(m.searchText)
		}
	}
	
	@IBAction func togglePicsButton(_ sender: UIButton) {
		sender.isSelected.toggle()
		if let cm = cellModel as? PerformerSearchCellModel {
			cm.showImages = sender.isSelected
		}
	}
	
	override func collectionViewSizeChanged(to newSize: CGSize) {
		widthConstraint.constant = newSize.width
	}
}


// MARK: Gallery Cell
@objc protocol PerformerGalleryCellBindingProtocol: FetchedResultsBindingProtocol {
    var showImage: Bool { get set }
}

@objc class PerformerGalleryCellModel: FetchedResultsCellModel, PerformerGalleryCellBindingProtocol {
	private static let validReuseIDs = [ "PerformerGalleryCell" : PerformerGalleryCell.self ]
	override class var validReuseIDDict: [String: BaseCollectionViewCell.Type ] { return validReuseIDs }

    @objc dynamic var showImage: Bool 
    
    init(with: Performer, showImage: Bool) {
		self.showImage = showImage
    	super.init(withModel: with, reuse: "PerformerGalleryCell", bindingWith: PerformerGalleryCellBindingProtocol.self)
    }
    
}

class PerformerGalleryCell: BaseCollectionViewCell, PerformerGalleryCellBindingProtocol {
	private static let cellInfo = [ "PerformerGalleryCell" : PrototypeCellInfo("PerformerGalleryCell") ]
	override class var validReuseIDDict: [ String: PrototypeCellInfo ] { return cellInfo }

	@IBOutlet weak var imageView: UIImageView!
	@IBOutlet weak var button: UIButton!
	@IBOutlet weak var widthConstraint: NSLayoutConstraint!
	@IBOutlet var imageHeightConstraint: NSLayoutConstraint!
		
	override func awakeFromNib() {
		super.awakeFromNib()
		fullWidth = false
		contentView.layer.cornerRadius = 16
		
		button.configuration?.background.cornerRadius = 0
		
		let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(buttonTapped))
		imageView.isUserInteractionEnabled = true
		imageView.addGestureRecognizer(tapGestureRecognizer)
	}

    var showImage: Bool = false {
    	didSet {
			self.imageHeightConstraint.isActive = !self.showImage
   			animateIfNotPrototype(withDuration: 0.3) {
   				self.layoutIfNeeded()
				self.cellSizeChanged()
				// Hackish -- cellSizeChanged doesn't call this while building a cell, but we need it.
				self.cellModel?.cellSize = CGSize(width: 0, height: 0)
			}
    	}
    }

	var model: NSFetchRequestResult? {
		didSet {
			if let performerModel = model as? Performer {
				if let imageFilename = performerModel.imageFilename {
					ImageManager.shared.image(withSize:.medium, forKey: imageFilename) { image in
						self.imageView.image = image ?? UserManager.shared.noAvatarImage
						self.cellSizeChanged()
					}
				}
				else {
					imageView.image = UserManager.shared.noAvatarImage
					self.cellSizeChanged()
				}
				button.setTitle(performerModel.name, for: .normal)
			}
		}
	}
	
	@IBAction func buttonTapped(_ sender: Any) {
		if let performerModel = model as? Performer, let vc = viewController as? BaseCollectionViewController {
			vc.performKrakenSegue(.performerBio, sender: performerModel.id)
		}
	}
	
	override func collectionViewSizeChanged(to newSize: CGSize) {
		widthConstraint.constant = (newSize.width - 20 - 11) / 2
	}
	
	override func prepareForReuse() {
		super.prepareForReuse()
		if showImage == imageHeightConstraint.isActive {
			imageHeightConstraint.isActive = !showImage
			cellSizeChanged()
		}
	}
	
	override func calculateSize() -> CGSize {
		let size = contentView.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
		calculatedSize = size
		return size
	}
}
