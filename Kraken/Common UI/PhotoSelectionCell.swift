//
//  PhotoSelectionCell.swift
//  Kraken
//
//  Created by Chall Fry on 5/28/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit
import Photos

enum PhotoDataType {
	case library(PHAsset)
	case camera(AVCapturePhoto)
}
	
@objc protocol PhotoSelectionCellProtocol {
	@objc dynamic var privateSelected: Bool { get set }
	@objc dynamic var cameraPhotos: [AVCapturePhoto] { get set }
}

@objc class PhotoSelectionCellModel: BaseCellModel, PhotoSelectionCellProtocol {
	private static let validReuseIDs = [ "PhotoSelectionCell" : PhotoSelectionCell.self ]
	override class var validReuseIDDict: [String: BaseCollectionViewCell.Type ] { return validReuseIDs }
	
	// Both of these will be nil if no photo selected
	var selectedPhotoIndexPath: IndexPath?
	var selectedPhoto: PhotoDataType?

	dynamic var cameraPhotos: [AVCapturePhoto] = []
	
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
	}
}

class PhotoSelectionCell: BaseCollectionViewCell, PhotoSelectionCellProtocol {
	@IBOutlet var authorizationView: UIView!
	@IBOutlet var photoCollectionView: UICollectionView!
	@IBOutlet weak var heightConstraint: NSLayoutConstraint!
	
	private static let cellInfo = [ "PhotoSelectionCell" : PrototypeCellInfo("PhotoSelectionCell") ]
	override class var validReuseIDDict: [ String: PrototypeCellInfo ] { return cellInfo }
	
	var cameraPhotos: [AVCapturePhoto] = [] {
		didSet {
			// Cheezing it, deleting all camera photo cells and rebuilding
			while cameraSegment.allCellModels.count > 1 {
				cameraSegment.delete(at: 1)
			}
			for photo in cameraPhotos {
				self.appendCameraPhotoCell(for: photo)
			}
		}
	}

	var photoDataSource = KrakenDataSource()
	let cameraSegment = FilteringDataSourceSegment()
	let photoSegment = PhotoDataSourceSegment()

	@objc dynamic var showAuthView: Bool = true {
		didSet {
			authorizationView.isHidden = !showAuthView
		}
	}
	
    override func awakeFromNib() {
        super.awakeFromNib()
 		lineLayout = HorizontalLineLayout(withParent: self)
		photoCollectionView.collectionViewLayout = lineLayout!
		heightConstraint.constant = 400
		

 		photoDataSource.register(with: photoCollectionView, viewController: nil)
  		photoDataSource.append(segment: cameraSegment)
  		let cameraCell = PhotoCameraCellModel()
  		cameraCell.buttonHit = { [weak self] cell in
  			if let self = self {
	  			self.dataSource?.performSegue(withIdentifier: "Camera", sender: self)
			}
  		}
		cameraSegment.append(cameraCell)
  		
  		let status = PHPhotoLibrary.authorizationStatus()
		showAuthView = status == .notDetermined
		if status == .authorized {
			attachPhotoSegment()
		}
    }

	@IBAction func authButtonTapped(_ sender: Any) {
		PHPhotoLibrary.requestAuthorization { status in
			DispatchQueue.main.async {
				if status == .restricted || status == .denied {
					self.showAuthView = false
				}
				if status == .authorized {
					self.attachPhotoSegment()
					self.showAuthView = false
				}
			}
		}
	}
	
	func attachPhotoSegment() {
		guard !((dataSource?.allSegments.first(where: { $0 is PhotoDataSourceSegment })) != nil) else { return }
		photoDataSource.append(segment: photoSegment)
		photoSegment.activate(predicate: nil, sort: nil, cellClass: PhotoButtonCell.self, reuseID: "PhotoButtonCell")
  		photoSegment.buttonHitClosure = { [weak self] cell in
  			if let self = self {
	  			self.photoCellTapped(cell)
			}
  		}
	}
		
	var lineLayout: HorizontalLineLayout?
	func photoCellTapped(_ cell: PhotoCollectionCellProtocol) {
		if let _ = lineLayout?.privateSelectedIndexPath {
			lineLayout?.privateSelectedIndexPath = nil
			if let cellModel = cellModel as? PhotoSelectionCellModel {
				cellModel.selectedPhotoIndexPath = nil
				cellModel.selectedPhoto = nil
			}
		} 
		else {
			if let cell = cell as? PhotoButtonCell, let cellModel = cellModel as? PhotoSelectionCellModel,
					let indexPath = photoCollectionView.indexPath(for: cell) {
				lineLayout?.privateSelectedIndexPath = indexPath
				cellModel.selectedPhotoIndexPath = indexPath
				if let asset = cell.asset {
					cellModel.selectedPhoto = PhotoDataType.library(asset)
				}
				else if let photo = cell.cameraPhoto {
					cellModel.selectedPhoto = PhotoDataType.camera(photo)
				}
			}
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
	
	func appendCameraPhotoCell(for photo: AVCapturePhoto) {
		let photoCell = PhotoButtonCellModel(with: photo)
  		photoCell.buttonHit = { [weak self] cell in
  			if let self = self {
	  			self.photoCellTapped(cell)
			}
  		}
		cameraSegment.append(photoCell)
	}
	
}

// MARK: -
@objc protocol PhotoCameraCellProtocol {
	var buttonHit: ((PhotoCameraCellProtocol) -> Void)? { get set }
}

@objc class PhotoCameraCellModel: BaseCellModel, PhotoCameraCellProtocol {
	override class var validReuseIDDict: [String: BaseCollectionViewCell.Type ] { 
		return [ "PhotoCameraCell" : PhotoCameraCell.self ] 
	}
	dynamic var buttonHit: ((PhotoCameraCellProtocol) -> Void)?
	
	init() {
		super.init(bindingWith: PhotoCameraCellProtocol.self)
	}
}

@objc class PhotoCameraCell: BaseCollectionViewCell, PhotoCameraCellProtocol {
	private static let cellInfo = [ "PhotoCameraCell" : PrototypeCellInfo(PhotoCameraCell.self) ]
	override class var validReuseIDDict: [ String: PrototypeCellInfo ] { return cellInfo }
	var buttonHit: ((PhotoCameraCellProtocol) -> Void)?
	var photoButton = UIButton()
	
	required init(frame: CGRect) {
		super.init(frame: frame)
		fullWidth = false

		// Add the photo as a button; makes highlight and hit detection easier.
		photoButton.frame = self.bounds
		addSubview(photoButton)
		photoButton.addTarget(self, action:#selector(photoButtonHit), for:.touchUpInside)
		photoButton.adjustsImageWhenHighlighted = true
		photoButton.adjustsImageWhenDisabled = true
		photoButton.imageView?.contentMode = .scaleAspectFill
		photoButton.contentVerticalAlignment = .fill
		photoButton.contentHorizontalAlignment = .fill
		photoButton.imageView?.clipsToBounds = true
		photoButton.clipsToBounds = true
		
		photoButton.translatesAutoresizingMaskIntoConstraints = false
		photoButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10).isActive = true
		photoButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10).isActive = true
		photoButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10).isActive = true
		photoButton.topAnchor.constraint(equalTo: topAnchor, constant: 10).isActive = true
		photoButton.adjustsImageWhenHighlighted = true
		photoButton.adjustsImageWhenDisabled = true
		
		photoButton.setImage(UIImage(named: "CameraIcon3"), for: .normal)
		photoButton.setImage(UIImage(named: "CameraIcon3Highlight"), for: .highlighted)
	}
	
	required init?(coder aDecoder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}
	
    @objc func photoButtonHit() {
    	buttonHit?(self)
    }
}

// MARK: -
@objc protocol PhotoButtonCellProtocol {
	var buttonHit: ((PhotoCollectionCellProtocol) -> Void)? { get set }
	var cameraPhoto: AVCapturePhoto? { get set }
}

// Model is only used for camera photos. The PhotoLibrary cells operate modelless.
@objc class PhotoButtonCellModel: BaseCellModel, PhotoButtonCellProtocol {
	override class var validReuseIDDict: [String: BaseCollectionViewCell.Type ] { 
		return [ "PhotoButtonCell" : PhotoCameraCell.self ] 
	}
	dynamic var buttonHit: ((PhotoCollectionCellProtocol) -> Void)?
	dynamic var cameraPhoto: AVCapturePhoto?
	
	init(with: AVCapturePhoto) {
		cameraPhoto = with
		super.init(bindingWith: PhotoButtonCellProtocol.self)
	}
}

@objc class PhotoButtonCell: BaseCollectionViewCell, PhotoCollectionCellProtocol, PhotoButtonCellProtocol {	
	private static let cellInfo = [ "PhotoButtonCell" : PrototypeCellInfo(PhotoButtonCell.self) ]
	override class var validReuseIDDict: [ String: PrototypeCellInfo ] { return cellInfo }

	var photoButton = UIButton()
	var buttonHit: ((PhotoCollectionCellProtocol) -> Void)?
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
	
	var cameraPhoto: AVCapturePhoto? {
		didSet {
			var counterRotate: UIImage.Orientation = .right
			if let raw = cameraPhoto?.metadata[String(kCGImagePropertyOrientation)] as? UInt32,
					let cgOrientation = CGImagePropertyOrientation(rawValue: raw) {
				counterRotate = UIImage.Orientation(cgOrientation)
				if let cgImage = cameraPhoto?.cgImageRepresentation()?.takeUnretainedValue() {
					let image = UIImage(cgImage: cgImage, scale: 1.0, orientation: counterRotate)
					self.photoButton.setImage(image, for: .normal)
				}
			}
		}
	}
	
	required init(frame: CGRect) {
		super.init(frame: frame)
		fullWidth = false
		
		// Add the photo as a button; makes highlight and hit detection easier.
		photoButton.frame = self.bounds
		addSubview(photoButton)
		photoButton.addTarget(self, action:#selector(photoButtonHit), for:.touchUpInside)
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
    
    @objc func photoButtonHit() {
    	buttonHit?(self)
		photoButton.imageView?.contentMode = photoButton.imageView?.contentMode == .scaleAspectFill ?
				.scaleAspectFit : .scaleAspectFill
    }
}

// MARK: -
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
	
	func totalCellCount(in cv: UICollectionView) -> Int {
		var cellCount: Int = 0
		for index in 0..<(cv.dataSource?.numberOfSections?(in: cv) ?? 0) {
			cellCount += cv.dataSource?.collectionView(cv, numberOfItemsInSection: index) ?? 0
		}
		return cellCount
	}

	override var collectionViewContentSize: CGSize {
		if let cv = collectionView {
			if let _ = privateSelectedIndexPath {
				return cv.bounds.size 
			}
			else {
				let photoCount = totalCellCount(in: cv)
				return CGSize(width: photoCount * (HorizontalLineLayout.cellStride), height: 80)
			}
		}
		return CGSize(width: 0, height: 0)
	}

	override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
		guard let cv = collectionView else { return nil }
		
		var result: [UICollectionViewLayoutAttributes] = []
		if let path = privateSelectedIndexPath {
			let attrs = UICollectionViewLayoutAttributes(forCellWith: path)
			attrs.isHidden = false
			attrs.frame = cv.bounds
			result.append(attrs)
		}
		else if let ds = cv.dataSource {
			let photoCount = totalCellCount(in: cv)
			var first = Int(Int(rect.origin.x) / HorizontalLineLayout.cellStride)
			if first < 0 { first = 0 }
			var last = Int(Int(rect.origin.x + rect.size.width) / HorizontalLineLayout.cellStride)
			if last > photoCount { last = photoCount }
			
			var path = IndexPath(row: 0, section: 0)
			var cellStartIndex = 0
			var cellsInThisSection = 0
			let numSections = ds.numberOfSections?(in: cv) ?? 0
			for sectionIndex in 0..<numSections {
				let nextSectionStartIndex = cellStartIndex + ds.collectionView(cv, numberOfItemsInSection: sectionIndex)
				if nextSectionStartIndex > first {
					path.section = sectionIndex
					path.row = first - cellStartIndex
					cellsInThisSection = ds.collectionView(cv, numberOfItemsInSection: sectionIndex)
					break
				}
				cellStartIndex = nextSectionStartIndex
			}
			
			for index in first..<last {
				if path.row >= cellsInThisSection {
					path.section += 1
					path.row = 0
					cellsInThisSection = ds.collectionView(cv, numberOfItemsInSection: path.section)
				}

				let val = UICollectionViewLayoutAttributes(forCellWith: path)
				val.isHidden = false
				val.frame = CGRect(x: index * HorizontalLineLayout.cellStride, y: 0, width: HorizontalLineLayout.cellWidth, height: 80)
				result.append(val)
				
				path.row += 1
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
		else if let cv = collectionView, let ds = cv.dataSource {
			var cellFlatIndex = indexPath.row
			for sectionIndex in 0..<indexPath.section {
				cellFlatIndex += ds.collectionView(cv, numberOfItemsInSection: sectionIndex)
			}
		
			result.isHidden = false
			result.frame = CGRect(x: cellFlatIndex * HorizontalLineLayout.cellStride, y: 0,
					width: HorizontalLineLayout.cellWidth, height: 80)
		}
		return result
	}

	override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
		if let cv = collectionView, newBounds.size.height != cv.bounds.size.height {
			return true
		}
		return false
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
