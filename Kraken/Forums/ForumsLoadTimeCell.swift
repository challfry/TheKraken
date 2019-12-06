//
//  ForumsLoadTimeCell.swift
//  Kraken
//
//  Created by Chall Fry on 12/3/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit

@objc protocol ForumsLoadTimeBindingProtocol {
	var lastLoadTime: Date? { get set }
}

@objc class ForumsLoadTimeCellModel: BaseCellModel, ForumsLoadTimeBindingProtocol {
	override class var validReuseIDDict: [String: BaseCollectionViewCell.Type ] { 
		return [ "ForumsLoadTime" : ForumsLoadTimeCell.self ] 
	}

	var lastLoadTime: Date?
	
	init() {
		super.init(bindingWith: ForumsLoadTimeBindingProtocol.self)
	}
}


class ForumsLoadTimeCell: BaseCollectionViewCell, ForumsLoadTimeBindingProtocol {
	private static let cellInfo = [ "ForumsLoadTime" : PrototypeCellInfo("ForumsLoadTimeCell") ]
	override class var validReuseIDDict: [ String: PrototypeCellInfo] { return ForumsLoadTimeCell.cellInfo }

	var lastLoadTime: Date?

	
}
