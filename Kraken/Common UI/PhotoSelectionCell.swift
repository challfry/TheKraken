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
	@objc dynamic var privateSelected: Bool { get set }
	@objc dynamic var showAuthView: Bool { get set }
}

@objc class PhotoSelectionCellModel: BaseCellModel, PhotoSelectionCellProtocol {
	private static let validReuseIDs = [ "PhotoSelectionCell" : PhotoSelectionCell.self ]
	override class var validReuseIDDict: [String: BaseCollectionViewCell.Type ] { return validReuseIDs }
	
	@objc dynamic var showAuthView = PHPhotoLibrary.authorizationStatus() == .notDetermined
	
	override var shouldBeVisible: Bool {
		didSet {
			let status = PHPhotoLibrary.authorizationStatus()
			if status == .restricted || status == .denied {
				shouldBeVisible = false
			}
		}
	}
	
	init() {
		super.init(bindingWith: PhotoSelectionCellProtocol.self)
		
		let status = PHPhotoLibrary.authorizationStatus()
		if status == .restricted || status == .denied {
			shouldBeVisible = false
		}

		if !showAuthView {
			let allPhotosOptions = PHFetchOptions()
			allPhotosOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
			allPhotosOptions.includeAssetSourceTypes = [.typeUserLibrary, .typeCloudShared, .typeiTunesSynced] 
			allPhotos = PHAsset.fetchAssets(with: .image, options: allPhotosOptions)
		}
	}
	
	// Will be nil if no photo selected
	var allPhotos: PHFetchResult<PHAsset>?
	var selectedPhotoIndex: Int?
	
	func getSelectedPhoto() -> PHAsset? {
		if let index = selectedPhotoIndex, let photos = allPhotos, index < photos.count {
			return photos[index]
		}	
		return nil
	}
}

class PhotoSelectionCell: BaseCollectionViewCell, PhotoSelectionCellProtocol, UICollectionViewDataSource, UICollectionViewDelegate {
	@IBOutlet var authorizationView: UIView!
	@IBOutlet var photoCollectionView: UICollectionView!
	@IBOutlet weak var heightConstraint: NSLayoutConstraint!
	
	private static let cellInfo = [ "PhotoSelectionCell" : PrototypeCellInfo("PhotoSelectionCell") ]
	override class var validReuseIDDict: [ String: PrototypeCellInfo ] { return cellInfo }

	@objc dynamic var showAuthView: Bool = true {
		didSet {
			authorizationView.isHidden = !showAuthView
			photoCollectionView.isHidden = showAuthView
		}
	}
	
    override func awakeFromNib() {
        super.awakeFromNib()
 		lineLayout = HorizontalLineLayout(withParent: self)
		photoCollectionView.collectionViewLayout = lineLayout!
		heightConstraint.constant = 400

		photoCollectionView.register(PhotoButtonCell.self, forCellWithReuseIdentifier: "PhotoButtonCell")

		authorizationView.isHidden = !showAuthView
		photoCollectionView.isHidden = showAuthView
    }

	@IBAction func authButtonTapped(_ sender: Any) {
		PHPhotoLibrary.requestAuthorization { status in
			DispatchQueue.main.async {
				if status == .restricted || status == .denied {
					self.cellModel?.shouldBeVisible = false
				}
				if status == .authorized {
					(self.cellModel as? PhotoSelectionCellModel)?.showAuthView = false
				}
			}
		}
	}
	
	func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
		if let model = cellModel as? PhotoSelectionCellModel {
			return model.allPhotos?.count ?? 0
		}
		return 0
	}
	
	func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
		let cell = photoCollectionView.dequeueReusableCell(withReuseIdentifier: "PhotoButtonCell", for: indexPath) as! PhotoButtonCell 
		if let model = cellModel as? PhotoSelectionCellModel {
			cell.asset = model.allPhotos?.object(at: indexPath.row)
		}
		cell.ownerCell = self
		return cell
	}
	
	var lineLayout: HorizontalLineLayout?
	func cellTapped(_ cell: PhotoButtonCell) {
		if let _ = lineLayout?.privateSelectedIndexPath {
			lineLayout?.privateSelectedIndexPath = nil
			(cellModel as? PhotoSelectionCellModel)?.selectedPhotoIndex = nil
		} 
		else {
			let indexPath = photoCollectionView.indexPath(for: cell)
			lineLayout?.privateSelectedIndexPath = indexPath
			(cellModel as? PhotoSelectionCellModel)?.selectedPhotoIndex = indexPath?.row
		}
		UIView.animate(withDuration: 0.3) {
			self.lineLayout?.invalidateLayout()
			self.photoCollectionView.layoutIfNeeded()
		}
	}
	
	@objc dynamic override var privateSelected: Bool {
		didSet {
			heightConstraint.constant = privateSelected ? 400 : 400
			cellSizeChanged()
		}
	}
	
}

@objc class PhotoButtonCell: UICollectionViewCell {
	@objc weak dynamic var ownerCell: PhotoSelectionCell?
	var photoButton = UIButton()
	var asset: PHAsset? {
		didSet {
			guard let asset = asset else { return }
			let _ = PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width:400, height: 400), 
					contentMode: .aspectFill, options: nil) { image, info in
				if let image = image {
					self.photoButton.setImage(image, for: .normal)
				}
			} 
		}
	}
	
	override init(frame: CGRect) {
		super.init(frame: frame)
		
		// Add the photo as a button; makes highlight and hit detection easier.
		photoButton.frame = self.bounds
		addSubview(photoButton)
		photoButton.addTarget(self, action:#selector(buttonHit), for:.touchUpInside)
		photoButton.adjustsImageWhenHighlighted = true
		photoButton.adjustsImageWhenDisabled = true
		photoButton.imageView?.contentMode = .scaleAspectFill
		photoButton.contentVerticalAlignment = .fill
		photoButton.contentHorizontalAlignment = .fill
		photoButton.imageView?.clipsToBounds = true
		photoButton.clipsToBounds = true
		
		photoButton.translatesAutoresizingMaskIntoConstraints = false
		photoButton.leadingAnchor.constraint(equalTo: leadingAnchor).isActive = true
		photoButton.trailingAnchor.constraint(equalTo: trailingAnchor).isActive = true
		photoButton.bottomAnchor.constraint(equalTo: bottomAnchor).isActive = true
		
		// Make a label that only shows up when the cell is selected (via constraints)
		let label = UILabel()
		label.text = "This photo will be added to your post"
		addSubview(label)
		label.translatesAutoresizingMaskIntoConstraints = false
		label.textAlignment = .center
		label.clipsToBounds = true
		label.leadingAnchor.constraint(equalTo: leadingAnchor).isActive = true
		label.trailingAnchor.constraint(equalTo: trailingAnchor).isActive = true
		label.topAnchor.constraint(equalTo: topAnchor).isActive = true
		photoButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 80.0).isActive = true
		photoButton.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 0).isActive = true
	}
	
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc func buttonHit() {
    	ownerCell?.cellTapped(self)
		photoButton.imageView?.contentMode = photoButton.imageView?.contentMode == .scaleAspectFill ?
				.scaleAspectFit : .scaleAspectFill

    }
}


class HorizontalLineLayout: UICollectionViewLayout {
	var privateSelectedIndexPath: IndexPath?
	weak var parentCell: PhotoSelectionCell?
	
	static let cellWidth = 80
	static let cellSpacing = 6
	static var cellStride: Int { return cellWidth + cellSpacing }
	
	init(withParent: PhotoSelectionCell) {
		parentCell = withParent
		super.init()
	}
	
	required init?(coder aDecoder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	override var collectionViewContentSize: CGSize {
		if let _ = privateSelectedIndexPath {
			return collectionView!.bounds.size 
		}
		else if let model = parentCell?.cellModel as? PhotoSelectionCellModel {
			let photoCount = model.allPhotos?.count ?? 0
			return CGSize(width: photoCount * (HorizontalLineLayout.cellStride), height: 80)
		}
		
		return collectionView!.bounds.size 
	}

	override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
		var result: [UICollectionViewLayoutAttributes] = []
		let photoCount = (parentCell?.cellModel as? PhotoSelectionCellModel)?.allPhotos?.count ?? 0
		if let path = privateSelectedIndexPath {
			let attrs = UICollectionViewLayoutAttributes(forCellWith: path)
			attrs.isHidden = false
			attrs.frame = collectionView!.bounds
			result.append(attrs)
		}
		else {
			var index = Int(Int(rect.origin.x) / HorizontalLineLayout.cellStride)
			if index < 0 { index = 0 }
			var last = Int(Int(rect.origin.x + rect.size.width) / HorizontalLineLayout.cellStride)
			if last > photoCount { last = photoCount }
			while index < last {
				let val = UICollectionViewLayoutAttributes(forCellWith: IndexPath(row: index, section: 0))
				val.isHidden = false
				val.frame = CGRect(x: index * HorizontalLineLayout.cellStride, y: 0, width: HorizontalLineLayout.cellWidth, height: 80)
				result.append(val)
				index = index + 1
			}
		}
		
		return result
	}
	
	override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
		let result = UICollectionViewLayoutAttributes(forCellWith: indexPath)
		if let selectedIndexPath = privateSelectedIndexPath {
			result.isHidden = selectedIndexPath != indexPath
			result.frame = collectionView!.bounds
		}
		else {
			result.isHidden = false
			result.frame = CGRect(x: indexPath.row * HorizontalLineLayout.cellStride, y: 0,
					width: HorizontalLineLayout.cellWidth, height: 80)
		}
		return result
	}

	override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
		return true
	}
	
	var exitContentOffset = CGPoint(x:0, y:0)
	override func targetContentOffset(forProposedContentOffset proposedContentOffset: CGPoint) -> CGPoint {
		if let _ = privateSelectedIndexPath {
			exitContentOffset = proposedContentOffset
			return CGPoint(x: 0, y: 0)
		}
		else {
			return exitContentOffset
		}
	}
}
