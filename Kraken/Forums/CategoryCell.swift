//
//  CategoryCell.swift
//  Kraken
//
//  Created by Chall Fry on 12/12/21.
//  Copyright © 2021 Chall Fry. All rights reserved.
//

import UIKit
import CoreData

@objc protocol CategoryCellProtocol {
	dynamic var title: String? { get set }
	dynamic var purpose: String? { get set }
	dynamic var numThreads: Int32 { get set }
}

@objc class CategoryCellModel: FetchedResultsCellModel, CategoryCellProtocol {
	private static let validReuseIDs = [ "CategoryCell" : CategoryCell.self ]
	override class var validReuseIDDict: [String: BaseCollectionViewCell.Type ] { return validReuseIDs }

	dynamic var category: ForumCategory?

	dynamic var title: String?
	dynamic var purpose: String?
	dynamic var numThreads: Int32
	var tapAction: ((CategoryCellModel) -> Void)?
	
	init(category: ForumCategory) {
		self.category = category
		self.title = category.title
		self.purpose = category.purpose
		self.numThreads = category.numThreads
		super.init(withModel: category, reuse: "CategoryCell", bindingWith: CategoryCellProtocol.self)

		category.tell(self, when: "numThreads") { observer, observed in 
			observer.numThreads = observed.numThreads
		}
	}

//	init(with frr: NSFetchRequestResult?) {
//		numThreads = 0
//		super.init(withModel: frr, reuse: "CategoryCell", bindingWith: CategoryCellProtocol.self)
//		if let cat = frr as? ForumCategory {
//			category = cat
//		}
//		else if let pivot = frr as? ForumCategoryPivot {
//			category = pivot.category
//		}
//		
//		self.tell(self, when: "category.numThreads") { observer, observed in 
//			observer.numThreads = observed.category?.numThreads ?? 0
//		}
//	}

	override func cellTapped(dataSource: KrakenDataSource?, vc: UIViewController?) {
		tapAction?(self)
	}
}

class CategoryCell: BaseCollectionViewCell, CategoryCellProtocol {
	@IBOutlet var titleLabel: UILabel!
	@IBOutlet var purposeLabel: UILabel!
	@IBOutlet var numForumsLabel: UILabel!
	private static let cellInfo = [ "CategoryCell" : PrototypeCellInfo("CategoryCell") ]
	override class var validReuseIDDict: [ String: PrototypeCellInfo ] { return cellInfo }

	var title: String? {
		didSet { 
			titleLabel.text = title
			cellSizeChanged()
		}
	}
	var purpose: String? {
		didSet { 
			let attrString = NSMutableAttributedString(string: purpose ?? "", attributes: purposeLabel.getAttrs())
			purposeLabel.attributedText = StringUtilities.addInlineImages(str: attrString)
			cellSizeChanged()
		}
	}
	var numThreads: Int32 = 0 {
		didSet { 
			numForumsLabel.text = "\(numThreads) threads"
			cellSizeChanged()
		}
	}
		
	override var isHighlighted: Bool {
		didSet {
			standardHighlightHandler()
		}
	}
		
	override func awakeFromNib() {
		super.awakeFromNib()
		fullWidth = true
		
		titleLabel.styleFor(.body)
		purposeLabel.styleFor(.body)
		numForumsLabel.styleFor(.body)
	}
}
