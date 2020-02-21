//
//  SegmentCell.swift
//  Kraken
//
//  Created by Chall Fry on 10/27/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit

@objc protocol SegmentCellProtocol {
	dynamic var cellTitle: String? { get set }
	dynamic var segmentTitles: [String] { get set }
	dynamic var selectedSegment: Int { get set }
}

@objc class SegmentCellModel: BaseCellModel, SegmentCellProtocol {
	private static let validReuseIDs = [ "SegmentCell" : SegmentCell.self ]
	override class var validReuseIDDict: [String: BaseCollectionViewCell.Type ] { return validReuseIDs }

	dynamic var cellTitle: String?
	dynamic var segmentTitles: [String] = []
	dynamic var selectedSegment: Int = -1
	var stateChanged: (() -> Void)?
	
	init(titles: [String]) {
		segmentTitles = titles
		super.init(bindingWith: SegmentCellProtocol.self)
	}

}

class SegmentCell: BaseCollectionViewCell, SegmentCellProtocol {
	private static let cellInfo = [ "SegmentCell" : PrototypeCellInfo("SegmentCell") ]
	override class var validReuseIDDict: [ String: PrototypeCellInfo ] { return cellInfo }

	@IBOutlet weak var titleLabel: UILabel!
	@IBOutlet weak var segmentControl: UISegmentedControl!
	
	var cellTitle: String? {
		didSet {
			titleLabel.text = cellTitle
		}
	}
	
	var segmentTitles: [String] = [] {
		didSet {
			let savedIndex = segmentControl.selectedSegmentIndex
			segmentControl.removeAllSegments()
			for (index, title) in segmentTitles.enumerated() {
				segmentControl.insertSegment(withTitle: title, at: index, animated: false)
			}
			if segmentControl.numberOfSegments > savedIndex {
				segmentControl.selectedSegmentIndex = savedIndex
			}
		}
	}
	
	var selectedSegment: Int = -1 {
		didSet {
			if segmentControl.numberOfSegments > selectedSegment {
				segmentControl.selectedSegmentIndex = selectedSegment
			}
		}
	}
	
	override func awakeFromNib() {
		super.awakeFromNib()
		titleLabel.styleFor(.body)
	}
	
	@IBAction func segmentSelectionChanged() {
		if let model = cellModel as? SegmentCellModel {
			model.selectedSegment = segmentControl.selectedSegmentIndex
			model.stateChanged?()
		}
	}
	
}
