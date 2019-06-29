//
//  CollectionFlowLayout.swift
//  Kraken
//
//  Created by Chall Fry on 5/22/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit

// Currently unused. Was for debugging.
class CollectionFlowLayout: UICollectionViewFlowLayout {

	override func shouldInvalidateLayout(forPreferredLayoutAttributes preferredAttributes: UICollectionViewLayoutAttributes, 
			withOriginalAttributes originalAttributes: UICollectionViewLayoutAttributes) -> Bool {
		let x = super.shouldInvalidateLayout(forPreferredLayoutAttributes: preferredAttributes, 
				withOriginalAttributes: originalAttributes)
		CollectionViewLog.debug("Bingo")
		return x
	}

}
