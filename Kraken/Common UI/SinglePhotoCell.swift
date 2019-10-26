//
//  SinglePhotoCell.swift
//  Kraken
//
//  Created by Chall Fry on 10/16/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit

@objc protocol SinglePhotoCellProtocol {
	dynamic var image: UIImage? { get set }
}

@objc class SinglePhotoCellModel: BaseCellModel, SinglePhotoCellProtocol {	
	private static let validReuseIDs = [ "SinglePhotoCell" : SinglePhotoCell.self ]
	override class var validReuseIDDict: [String: BaseCollectionViewCell.Type ] { return validReuseIDs }

	dynamic var image: UIImage?
	
	init() {
		super.init(bindingWith: SinglePhotoCellProtocol.self)
	}
	
	init(_ initialImage: UIImage) {
		image = initialImage
		super.init(bindingWith: SinglePhotoCellProtocol.self)
	}
	init(_ imageData: NSData) {
		image = UIImage(data: imageData as Data)
		super.init(bindingWith: SinglePhotoCellProtocol.self)
	}
}


class SinglePhotoCell: BaseCollectionViewCell, SinglePhotoCellProtocol {
	private static let cellInfo = [ "SinglePhotoCell" : PrototypeCellInfo("SinglePhotoCell") ]
	override class var validReuseIDDict: [ String: PrototypeCellInfo ] { return cellInfo }

	@IBOutlet weak var imageView: UIImageView!
	
	var image: UIImage? {
		didSet {
			imageView.image = image
		}
	}
}
