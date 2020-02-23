//
//  HashtagCompletionCell.swift
//  Kraken
//
//  Created by Chall Fry on 2/22/20.
//  Copyright © 2020 Chall Fry. All rights reserved.
//

import UIKit

@objc protocol HashtagCompletionCellBindingProtocol {
	var hashtagPrefix: String? { get set }
	var hashtagNames: [String]? { get set }
	var selectionCallback: ((String) -> Void)? { get set }
}

@objc class HashtagCompletionCellModel: BaseCellModel, HashtagCompletionCellBindingProtocol, NSFetchedResultsControllerDelegate {
	override class var validReuseIDDict: [String: BaseCollectionViewCell.Type ] { 
		return [ "HashtagCompletionCell" : HashtagCompletionCell.self ] 
	}

	dynamic var hashtagPrefix: String? {
		didSet {
			if let str = hashtagPrefix, !str.isEmpty {
				fetchedResults.fetchRequest.predicate = NSPredicate(format: "name CONTAINS %@", str)
				HashtagDataManager.shared.autocompleteHashtagLookup(for: str)
			}
			else {
				fetchedResults.fetchRequest.predicate = NSPredicate(value: false)
			}
			try? fetchedResults.performFetch()
			hashtagNames = nil
			if let objects = fetchedResults.fetchedObjects {
				hashtagNames = objects.map { $0.name }
			}
			
		}
	}
	
	dynamic var hashtagNames: [String]?
	dynamic var selectionCallback: ((String) -> Void)?

	var fetchedResults: NSFetchedResultsController<Hashtag>

	init(withTitle: String) {

		let fetchRequest = NSFetchRequest<Hashtag>(entityName: "Hashtag")
		fetchRequest.predicate = NSPredicate(value: false)
		fetchRequest.sortDescriptors = [ NSSortDescriptor(key: "name", ascending: true)]
		fetchRequest.fetchBatchSize = 10
		fetchedResults = NSFetchedResultsController(fetchRequest: fetchRequest,
				managedObjectContext: LocalCoreData.shared.mainThreadContext, sectionNameKeyPath: nil, cacheName: nil)

		super.init(bindingWith: HashtagCompletionCellBindingProtocol.self)
		fetchedResults.delegate = self
	}
   
	func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
		hashtagNames = nil
		if let objects = fetchedResults.fetchedObjects {
			hashtagNames = objects.map { $0.name }
		}
	}
}

class HashtagCompletionCell: BaseCollectionViewCell, HashtagCompletionCellBindingProtocol {
	private static let cellInfo = [ "HashtagCompletionCell" : PrototypeCellInfo("HashtagCompletionCell") ]
	override class var validReuseIDDict: [ String: PrototypeCellInfo] { return HashtagCompletionCell.cellInfo }

	// This is the CV inside the cell.
	@IBOutlet var tagCollectionView: UICollectionView!
	@IBOutlet var collectionHeightConstraint: NSLayoutConstraint!
	
	var selectionCallback: ((String) -> Void)?
	var hashtagPrefix: String? 
	var hashtagNames: [String]? {
		didSet {
			hashtagSection.removeAll()
			if let tags = hashtagNames {
				for tagName in tags {
					let newCell = createTagCell(tagName)
					hashtagSection.append(newCell)
				}	
			}
			
			tagDataSource.forceRunUpdates()
			collectionHeightConstraint.constant = tagCollectionView.contentSize.height
		//	print ("New height: \(tagCollectionView.contentSize.height)")
			cellSizeChanged()
		}
	}
	
	var tagDataSource = KrakenDataSource()
	var hashtagSection = FilteringDataSourceSegment()

	override func awakeFromNib() {
        super.awakeFromNib()
		tagDataSource.enableAnimations = true
		tagDataSource.register(with: tagCollectionView, viewController: viewController as? BaseCollectionViewController)
		tagDataSource.append(segment: hashtagSection)
		
		contentView.translatesAutoresizingMaskIntoConstraints = false
		
		if !isPrototypeCell {
			tagCollectionView.tell(self, when: "contentSize") { observer, observed in 
				observer.collectionHeightConstraint.constant = observed.contentSize.height
	//			print ("New height: \(observed.contentSize.height)")
				observer.cellSizeChanged()
			}
		}
		
	}
	
	func createTagCell(_ tagName: String) -> HashtagButtonCellModel {
		let cellModel = HashtagButtonCellModel(tagName)
		cellModel.shouldBeVisible = true
		cellModel.selectionCallback = { [weak self] tagName in
			self?.selectionCallback?(tagName)
		}
		return cellModel
	}
}

@objc protocol HashtagButtonCellBindingProtocol {
	var hashtagName: String { get set }
	var selectionCallback: ((String) -> Void)? { get set }
}

@objc class HashtagButtonCellModel: BaseCellModel, HashtagButtonCellBindingProtocol {
	override class var validReuseIDDict: [String: BaseCollectionViewCell.Type ] { 
		return [ "HashtagButtonCell" : HashtagButtonCell.self ]
	}

	var hashtagName: String
	var selectionCallback: ((String) -> Void)?
	
	init(_ tagName: String) {
		hashtagName = tagName
		super.init(bindingWith: HashtagButtonCellBindingProtocol.self)
	}
}

class HashtagButtonCell: BaseCollectionViewCell, HashtagButtonCellBindingProtocol {
	private static let cellInfo = [ "HashtagButtonCell" : PrototypeCellInfo("HashtagButtonCell") ]
	override class var validReuseIDDict: [ String: PrototypeCellInfo] { return HashtagButtonCell.cellInfo }
	
	@IBOutlet var button: UIButton!
	
	var hashtagName: String = "" {
		didSet {
			button.setTitle("#\(hashtagName)", for: .normal)
		}
	}
	var selectionCallback: ((String) -> Void)?
	
	@IBAction func buttonTapped(_ sender: Any) {
		selectionCallback?(hashtagName)
	}
	
	override func awakeFromNib() {
		self.fullWidth = false
		super.awakeFromNib()
	}
}

@objc class HashtagButtonRoundedRectView: UIView {
	override func draw(_ rect: CGRect) {
	//	let pathBounds = bounds.insetBy(dx: 10, dy: 5)
		let pathBounds = bounds

		let rectShape = CAShapeLayer()
		rectShape.bounds = pathBounds
		rectShape.position = self.center
		let rectPath = UIBezierPath(roundedRect: pathBounds, cornerRadius: 12)
		rectShape.path = rectPath.cgPath
		layer.mask = rectShape
		layer.masksToBounds = true
		
		let context = UIGraphicsGetCurrentContext()
		if let color = UIColor(named: "Announcement Header Color") {
			context?.setStrokeColor(color.cgColor)
			rectPath.stroke()
		}

	}
}
