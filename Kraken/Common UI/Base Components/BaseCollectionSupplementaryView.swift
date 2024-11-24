//
//  BaseCollectionSupplementaryView.swift
//  Kraken
//
//  Created by Chall Fry on 2/5/20.
//  Copyright © 2020 Chall Fry. All rights reserved.
//

import UIKit

class BaseCollectionSupplementaryView: UICollectionReusableView {
	class var nib: UINib? {
		return nil
	}
	class var reuseID: String {
		return ""
	}
	var isPrototype = false
	weak var collectionView: UICollectionView?
	var indexPath: IndexPath?
	
	class func getPrototypeView(_ cv: UICollectionView, cellModel: BaseCellModel) -> BaseCollectionSupplementaryView? {
		if let nibContents = nib?.instantiate(withOwner: nil, options: nil) {
			let p = (nibContents[0] as! BaseCollectionSupplementaryView)
			p.isPrototype = true
			p.setup(cellModel: cellModel)
			return p
		}
		return nil
	}
	
	class func createView(_ cv: UICollectionView, indexPath: IndexPath, kind: String, cellModel: BaseCellModel) 
			-> BaseCollectionSupplementaryView {
		let newView = cv.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: reuseID, 
				for: indexPath) as! BaseCollectionSupplementaryView
		newView.collectionView = cv
		newView.indexPath = indexPath
		newView.setup(cellModel: cellModel)	
		return newView	
	}

	func setup(cellModel: BaseCellModel) {
		
	}
}
