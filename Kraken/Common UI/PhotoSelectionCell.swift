//
//  PhotoSelectionCell.swift
//  Kraken
//
//  Created by Chall Fry on 5/28/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit
import Photos

@objc protocol PhotoSelectionCellProtocol {
	
}

@objc class PhotoSelectionCellModel: BaseCellModel, PhotoSelectionCellProtocol {
	private static let validReuseIDs = [ "PhotoSelectionCell" : PhotoSelectionCell.self ]
	override class var validReuseIDDict: [String: BaseCollectionViewCell.Type ] { return validReuseIDs }
	
	init() {
		super.init(bindingWith: PhotoSelectionCellProtocol.self)
		
		let status = PHPhotoLibrary.authorizationStatus()
		if status == .restricted || status == .denied {
			shouldBeVisible = false
		}
	}
	
}

class PhotoSelectionCell: BaseCollectionViewCell, PhotoSelectionCellProtocol, UICollectionViewDataSource, UICollectionViewDelegate {
	@IBOutlet var authorizationView: UIView!
	@IBOutlet var photoCollectionView: UICollectionView!

	private static let cellInfo = [ "PhotoSelectionCell" : PrototypeCellInfo("PhotoSelectionCell") ]
	override class var validReuseIDDict: [ String: PrototypeCellInfo ] { return cellInfo }
	
	var allPhotos: PHFetchResult<PHAsset>?

    override func awakeFromNib() {
        super.awakeFromNib()

		photoCollectionView.register(PhotoButtonCell.self, forCellWithReuseIdentifier: "PhotoButtonCell")

		let showAuthView = PHPhotoLibrary.authorizationStatus() == .notDetermined
		authorizationView.isHidden = !showAuthView
		photoCollectionView.isHidden = showAuthView
		
		if !showAuthView {
			let allPhotosOptions = PHFetchOptions()
			allPhotosOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
			allPhotosOptions.includeAssetSourceTypes = [.typeUserLibrary, .typeCloudShared, .typeiTunesSynced] 
			allPhotos = PHAsset.fetchAssets(with: .image, options: allPhotosOptions)
		}
    }

	@IBAction func authButtonTapped(_ sender: Any) {
		PHPhotoLibrary.requestAuthorization { status in
			DispatchQueue.main.async {
				if status == .restricted || status == .denied {
					self.cellModel?.shouldBeVisible = false
				}
				if status == .authorized {
					self.authorizationView.isHidden = true
					self.photoCollectionView.isHidden = false
				}
			}
		}
	}
	
	func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
		return allPhotos?.count ?? 0
	}
	
	func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
		let cell = photoCollectionView.dequeueReusableCell(withReuseIdentifier: "PhotoButtonCell", for: indexPath) as! PhotoButtonCell 
		cell.asset = allPhotos?.object(at: indexPath.row)
		cell.ownerCell = self
		return cell
	}
}

@objc class PhotoButtonCell: UICollectionViewCell {
	@objc dynamic var ownerCell: PhotoSelectionCell?
	var photoButton = UIButton()
	var asset: PHAsset? {
		didSet {
			guard let asset = asset else { return }
			let _ = PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width:80, height: 80), 
					contentMode: .aspectFill, options: nil) { image, info in
				if let image = image {
					self.photoButton.setImage(image, for: .normal)
				}
			} 
		}
	}
	
	override init(frame: CGRect) {
		super.init(frame: frame)
		photoButton.frame = self.bounds
		addSubview(photoButton)
		photoButton.addTarget(self, action:#selector(buttonHit), for:.touchUpInside)
		photoButton.adjustsImageWhenHighlighted = true
		photoButton.adjustsImageWhenDisabled = true
		photoButton.imageView?.contentMode = .scaleAspectFill	 
	}
	
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc func buttonHit() {
//    	ownerCell?.buttonTapped(withString:emoji)
    }
}


