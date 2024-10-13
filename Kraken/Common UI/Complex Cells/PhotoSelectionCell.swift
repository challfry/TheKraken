//
//  PhotoSelectionCell.swift
//  Kraken
//
//  Created by Chall Fry on 5/28/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit
import Photos

// A photo selected by the PhotoSelectionCell. This type could be anything the user could attach to a post:
// 	- A photo from the photo library, 
//  - A new camera photo,
//  - An AR photo capture (Pirate hats, which are captured as UIImages, not AVCapturePhotos)
//  - local GIF files, 
//  - files already uploaded to the server.
// The datatype is dependent on whether the source is the camera or the library, so: enums to the rescue.
enum PhotoDataType {
	case library(PHAsset)
	case camera(AVCapturePhoto)
	case image(UIImage)

	// Cases with mime types
	case data(Data, String)
	case server(String, String)				// Filename, mime type
	
	func getUIImage(done: @escaping (UIImage?) -> Void) {
		switch self {
		case .library(let asset):
			PHImageManager.default().requestImage(for: asset, targetSize: PHImageManagerMaximumSize, 
					contentMode: .aspectFit, options: nil) { image, info in 
				// Skip the thumbnail, if we get one
				if let info = info, info[PHImageResultIsDegradedKey] as? Bool == true { 
					return
				}
				done(image)
			}
		case .camera(let cameraPhoto): 
			if let photoData = cameraPhoto.fileDataRepresentation(), let photoImage = UIImage(data: photoData) {
				done(photoImage)
			}
			else {
				done(nil)
			}
		case .image(let imageValue): done(imageValue)

		case .data(let imageData, _):
			let resultImage = UIImage(data: imageData)
			done(resultImage)
		case .server(let filename, _): ImageManager.shared.image(withSize: .small, forKey: filename, done: done)
		}
	}
	
	func getRawData() -> Data? {
		switch self {
		case .data(let result, _): return result
		default: return nil
		}
	}
}

// Wraps an optional UIImage in a thing that can be placed in an array. 
@objc class PhotoCellImageWrapper: NSObject {
	@objc dynamic var image: UIImage?
	var path: IndexPath?
	
	init(path: IndexPath?, photo: PhotoDataType) {
		self.path = path
		self.image = nil
		super.init()
		photo.getUIImage { image in
			self.image = image
		}
	}
}
	
// MARK: - PhotoSelectionCell
// PhotoSelectionCell, its model protocol, are a CollectionView cell that contains a horizontally scrolling
// collectionView. The horiz CollectionView contains a camera cell for opening the camera, and than photos
// from the user's photo library, in reverse chronological order. 
// The cell manages auth for photo lib access and camera access. It is designed for single selection only.
@objc protocol PhotoSelectionCellProtocol {
	// The max # of photos that may be selected. Currently 4 for forum posts, 1 for lfg messages.
	@objc dynamic var maxPhotos: Int { get set }
	// Images selected by the user. Note that the model tracks these interally with PhotoDataTypes, which have more info.
	@objc dynamic var selectedImages: [PhotoCellImageWrapper] { get set }
	// Photos taken with the camera while this cell was up.
	@objc dynamic var cameraPhotos: [AnyObject] { get set }
}

@objc class PhotoSelectionCellModel: BaseCellModel, PhotoSelectionCellProtocol {
	private static let validReuseIDs = [ "PhotoSelectionCell" : PhotoSelectionCell.self ]
	override class var validReuseIDDict: [String: BaseCollectionViewCell.Type ] { return validReuseIDs }
	
	@objc dynamic var maxPhotos: Int = 4
	@objc dynamic var selectedImages: [PhotoCellImageWrapper] = []
	@objc dynamic var cameraPhotos: [AnyObject] = []
	
	// PhotoDataType can't be observed (objC issues) so instead we pass the images to the cell
	var selectedPhotos: [PhotoDataType] = []
	
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
	
	func appendSelectedPhoto(path: IndexPath?, photo: PhotoDataType) {
		if selectedPhotos.count >= maxPhotos { return }
		if let path, selectedImages.contains(where: { $0.path == path }) { return }
		selectedPhotos.append(photo)
		selectedImages.append(.init(path: path, photo: photo))
	}
	
	func removeSelectedPhoto(at index: Int) {
		selectedPhotos.remove(at: index)
		selectedImages.remove(at: index)
	}
	
	func clearAllSelectedPhotos() {
		selectedPhotos.removeAll()
		selectedImages.removeAll()
	}
}

@objc class PhotoSelectionCell: BaseCollectionViewCell, PhotoSelectionCellProtocol {
	
	@IBOutlet weak var verticalStackView: UIStackView!
		@IBOutlet weak var addPicsContainer: UIView!
		@IBOutlet var addPicsHeight: NSLayoutConstraint!
			@IBOutlet weak var addPicsLabel: UILabel!
	
		@IBOutlet weak var selectedPhotosStack: UIStackView!
			@IBOutlet weak var photo1: UIImageView!
			@IBOutlet weak var photo2: UIImageView!
			@IBOutlet weak var photo3: UIImageView!
			@IBOutlet weak var photo4: UIImageView!
			var photoViews: [UIImageView] { return [ photo1, photo2, photo3, photo4 ] }
			
			@IBOutlet weak var cancelPic1Btn: UIButton!
			@IBOutlet weak var cancelPic2Btn: UIButton!
			@IBOutlet weak var cancelPic3Btn: UIButton!
			@IBOutlet weak var cancelPic4Btn: UIButton!
			var cancelPicButtons: [UIButton] { return [ cancelPic1Btn, cancelPic2Btn, cancelPic3Btn, cancelPic4Btn ] }
		
		@IBOutlet var photoCollectionView: UICollectionView!

	// Just shadows the collectionView's collectionViewLayout, correctly typed.
	var lineLayout: HorizontalLineLayout?
	
	private static let cellInfo = [ "PhotoSelectionCell" : PrototypeCellInfo("PhotoSelectionCell") ]
	override class var validReuseIDDict: [ String: PrototypeCellInfo ] { return cellInfo }
	
	var maxPhotos: Int = 4 {
		didSet {
			for index in 0..<4 {
				photoViews[index].superview?.isHidden = index >= maxPhotos
			}
			addPicsLabel.text = maxPhotos == 1 ? "Add a photo to your post" : "Add up to \(maxPhotos) photos to your post"
		}
	}
	
	var selectedImages: [PhotoCellImageWrapper] = [] {
		didSet {
			for index in 0..<4 {
				cancelPicButtons[index].isHidden = index >= selectedImages.count
			}
			addPicsHeight.isActive = !selectedImages.isEmpty
			selectedPhotosStack.isHidden = selectedImages.isEmpty
			UIView.animate(withDuration: 0.35) { [unowned self] in
				verticalStackView.layoutIfNeeded()
				setupSelectedPhotos()
				cellSizeChanged()
			}
			lineLayout?.invalidateLayout()
		}
	}
	
	var cameraPhotos: [AnyObject] = [] {
		didSet {
			// Cheezing it, deleting all camera photo cells and rebuilding
			while cameraSegment.allCellModels.count > 1 {
				cameraSegment.delete(at: 1)
			}
			for photo in cameraPhotos {
				if let capturePhoto = photo as? AVCapturePhoto {
					self.appendCameraPhotoCell(for: capturePhoto)
				}
				else if let captureImage = photo as? UIImage {
					self.appendCameraPhotoCell(for: captureImage)
				}
			}
		}
	}

	var photoDataSource = KrakenDataSource()
	let cameraSegment = FilteringDataSourceSegment()
	let authSegment = FilteringDataSourceSegment()
  		let authCell = PhotoAuthCellModel()
	let photoSegment = PhotoDataSourceSegment()
	
    override func awakeFromNib() {
        super.awakeFromNib()
 		lineLayout = HorizontalLineLayout(withParent: self)
		photoCollectionView.collectionViewLayout = lineLayout!
		addPicsHeight.constant = 0

 		photoDataSource.register(with: photoCollectionView, viewController: nil)
 		// The 'open Camera' button, and any pictures we've taken
  		photoDataSource.append(segment: cameraSegment)
  		let cameraCell = PhotoCameraCellModel()
  		cameraCell.buttonHit = { [weak self] cell in
  			if let self = self {
  				if Settings.shared.useFullscreenCameraViewfinder {
		  			self.dataSource?.performKrakenSegue(.fullScreenCamera, sender: self)
				}
				else {
					self.dataSource?.performKrakenSegue(.cropCamera, sender: self)
				}
			}
  		}
		cameraSegment.append(cameraCell)

		// Auth buttons for camera and library access
  		photoDataSource.append(segment: authSegment)
		authSegment.append(authCell)
		authCell.buttonHit = authButtonTapped
  		
  		let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
		authCell.shouldBeVisible = status == .notDetermined
		if status == .authorized {
			attachPhotoSegment()
		}
		
		self.tell(self, when: "cellModel.selectedImages.*.image") { observer, observed in
			observer.setupSelectedPhotos()
		}

		if !isPrototypeCell {
			for view in photoViews {
	 			let photoTap = UITapGestureRecognizer(target: self, action: #selector(PhotoSelectionCell.selectedPhotoTapped(_:)))
		 		view.addGestureRecognizer(photoTap)
			}
		}
   }
    
    func setupSelectedPhotos() {
    	for index in 0..<self.maxPhotos {
			if index < selectedImages.count {
				photoViews[index].image = selectedImages[index].image
			}
			else {
				photoViews[index].image = nil
			}
		}
    }

	@IBAction func authButtonTapped(_ sender: Any) {
		PHPhotoLibrary.requestAuthorization { status in
			DispatchQueue.main.async {
				if status == .restricted || status == .denied {
					self.authCell.shouldBeVisible = false
				}
				if status == .authorized {
					self.attachPhotoSegment()
					self.authCell.shouldBeVisible = false
				}
			}
		}
	}
	
	@IBAction func cancelPicButtonTapped(_ sender: Any) {
		if let cm = cellModel as? PhotoSelectionCellModel, let button = sender as? UIButton,
				let index = cancelPicButtons.firstIndex(of: button) {
			cm.removeSelectedPhoto(at: index)
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
	
	@objc func selectedPhotoTapped(_ sender: UITapGestureRecognizer) {
		if sender.state == .ended, let vc = viewController as? BaseCollectionViewController, 
				let imageView = sender.view as? UIImageView, let image = imageView.image {
			vc.showImageInOverlay(image: image)
		}
	}

	// Called when a photo in the 'available photos' bar is tapped. This could be a camera photo or a library photo.
	func photoCellTapped(_ cell: PhotoCollectionCellProtocol) {
		if let cell = cell as? PhotoButtonCell, let pdt = cell.getPhotoDataType(),  let cellModel = cellModel as? PhotoSelectionCellModel,
				let indexPath = photoCollectionView.indexPath(for: cell) {
			cellModel.appendSelectedPhoto(path: indexPath, photo: pdt)
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
	
	func appendCameraPhotoCell(for image: UIImage) {
		let photoCell = PhotoButtonCellModel(with: image)
  		photoCell.buttonHit = { [weak self] cell in
  			if let self = self {
	  			self.photoCellTapped(cell)
			}
  		}
		cameraSegment.append(photoCell)
	}
	
}

// MARK: - PhotoCameraCell

// PhotoCameraCell is a 'small' cell that has a cell-sized button that shows a camera icon.
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
		
		photoButton.setImage(UIImage(named: "CameraIcon3"), for: .normal)
		photoButton.setImage(UIImage(named: "CameraIcon3Highlight"), for: .highlighted)
		photoButton.imageView?.tintColor = UIColor(named: "Icon Foreground")
	}
	
	required init?(coder aDecoder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}
	
    @objc func photoButtonHit() {
    	buttonHit?(self)
    }
}

// MARK: - PhotoButtonCell
@objc protocol PhotoButtonCellProtocol {
	var buttonHit: ((PhotoCollectionCellProtocol) -> Void)? { get set }
	var cameraPhoto: AVCapturePhoto? { get set }
	var image: UIImage? { get set }
}

// Model is only used for camera photos. The PhotoLibrary cells operate modelless.
@objc class PhotoButtonCellModel: BaseCellModel, PhotoButtonCellProtocol {
	override class var validReuseIDDict: [String: BaseCollectionViewCell.Type ] { 
		return [ "PhotoButtonCell" : PhotoButtonCell.self ] 
	}
	dynamic var buttonHit: ((PhotoCollectionCellProtocol) -> Void)?
	dynamic var cameraPhoto: AVCapturePhoto?
	dynamic var image: UIImage?
	
	init(with: AVCapturePhoto) {
		cameraPhoto = with
		super.init(bindingWith: PhotoButtonCellProtocol.self)
	}
	
	init(with: UIImage) {
		image = with
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
			if let data = cameraPhoto?.fileDataRepresentation(), let image = UIImage(data: data) {
				self.photoButton.setImage(image, for: .normal)
			}
		}
	}
	
	var image: UIImage? {
		didSet {
			self.photoButton.setImage(image, for: .normal)
		}
	}
	
	required init(frame: CGRect) {
		super.init(frame: frame)
		fullWidth = false
		
		// Add the photo as a button; makes highlight and hit detection easier.
		photoButton.frame = self.bounds
		addSubview(photoButton)
		photoButton.addTarget(self, action:#selector(photoButtonHit), for:.touchUpInside)
		photoButton.imageView?.contentMode = .scaleAspectFit
		photoButton.imageView?.clipsToBounds = true
		photoButton.clipsToBounds = true
		photoButton.backgroundColor = UIColor(named: "Photocell Image BG")
		
		photoButton.translatesAutoresizingMaskIntoConstraints = false
		photoButton.topAnchor.constraint(equalTo: topAnchor).isActive = true
		photoButton.leadingAnchor.constraint(equalTo: leadingAnchor).isActive = true
		photoButton.trailingAnchor.constraint(equalTo: trailingAnchor).isActive = true
		photoButton.bottomAnchor.constraint(equalTo: bottomAnchor).isActive = true
	}
	
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc func photoButtonHit() {
    	buttonHit?(self)
    }
    
    func getPhotoDataType() -> PhotoDataType? {
		if let asset = asset {
			return PhotoDataType.library(asset)
		}
		else if let photo = cameraPhoto {
			return PhotoDataType.camera(photo)
		}
		else if let image = image {
			return PhotoDataType.image(image)
		}
		return nil
	}
}

// MARK: - Authorization Cell
@objc protocol PhotoAuthCellProtocol {
	var buttonHit: ((PhotoAuthCellProtocol) -> Void)? { get set }
}

@objc class PhotoAuthCellModel: BaseCellModel, PhotoAuthCellProtocol {
	override class var validReuseIDDict: [String: BaseCollectionViewCell.Type ] { 
		return [ "PhotoAuthCell" : PhotoAuthCell.self ] 
	}
	
	init() {
		super.init(bindingWith: PhotoAuthCellProtocol.self)
	}
	
	dynamic var buttonHit: ((PhotoAuthCellProtocol) -> Void)?
}

@objc class PhotoAuthCell: BaseCollectionViewCell, PhotoAuthCellProtocol {
	private static let cellInfo = [ "PhotoAuthCell" : PrototypeCellInfo(PhotoAuthCell.self) ]
	override class var validReuseIDDict: [ String: PrototypeCellInfo ] { return cellInfo }

	var buttonHit: ((PhotoAuthCellProtocol) -> Void)?
	var authButton = UIButton()

	required init(frame: CGRect) {
		super.init(frame: frame)
		fullWidth = false
		
		// Auth button
		authButton.frame = self.bounds
		addSubview(authButton)
		authButton.addTarget(self, action:#selector(authButtonHit), for:.touchUpInside)
		authButton.imageView?.contentMode = .scaleAspectFit
		authButton.imageView?.clipsToBounds = true
		authButton.setImage(UIImage(systemName: "photo.stack")!, for: .normal)
		authButton.setPreferredSymbolConfiguration(UIImage.SymbolConfiguration(pointSize: .init(50)), forImageIn: .normal)
		authButton.setTitle("Tap here to authorize photo library access", for: .normal)
		authButton.titleLabel?.lineBreakMode = NSLineBreakMode.byWordWrapping
		authButton.setTitleColor(UIColor(named: "Kraken Label Text"), for: .normal)
		authButton.clipsToBounds = true
		authButton.backgroundColor = UIColor(named: "Photocell Image BG")
		
		authButton.translatesAutoresizingMaskIntoConstraints = false
		authButton.topAnchor.constraint(equalTo: topAnchor).isActive = true
		authButton.leadingAnchor.constraint(equalTo: leadingAnchor).isActive = true
		authButton.trailingAnchor.constraint(equalTo: trailingAnchor).isActive = true
		authButton.bottomAnchor.constraint(equalTo: bottomAnchor).isActive = true
	}
	
	@MainActor required init?(coder aDecoder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}
	
    @objc func authButtonHit() {
    	buttonHit?(self)
    }
    
}

// MARK: -
class HorizontalLineLayout: UICollectionViewLayout {
	weak var parentCell: PhotoSelectionCell?
	
	static let cellWidth = 80
	static let cellSpacing = 6
	static var cellStride: Int { return cellWidth + cellSpacing }
	
	init(withParent: PhotoSelectionCell) {
		parentCell = withParent
		super.init()
		self.register(CheckmarkReusableView.self, forDecorationViewOfKind: "checkmark")
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
			let photoCount = totalCellCount(in: cv)
			var result = CGSize(width: photoCount * (HorizontalLineLayout.cellStride), height: 80)
			if PHPhotoLibrary.authorizationStatus(for: .readWrite) == .notDetermined {
				let authWidth = cv.bounds.width - CGFloat(HorizontalLineLayout.cellStride)
				result.width += authWidth - CGFloat(HorizontalLineLayout.cellWidth)
			}
			return result
		}
		return CGSize(width: 0, height: 0)
	}

	override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
		guard let cv = collectionView, let ds = cv.dataSource else { return nil }
		var result: [UICollectionViewLayoutAttributes] = []
		let photoCount = totalCellCount(in: cv)
		var first = Int(Int(rect.origin.x) / HorizontalLineLayout.cellStride)
		first = first.clamped(to: 0...photoCount)
		var last = Int(ceil((rect.origin.x + rect.size.width) / CGFloat(HorizontalLineLayout.cellStride)))
		last = last.clamped(to: 0...photoCount)
		
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
			
			// Cheezing it. Checking the cell at this path--if it's the auth cell, give it a special size.
			if path.section == 1, path.row == 0 {
				let cell = ds.collectionView(cv, cellForItemAt: path)
				if let _ = cell as? PhotoAuthCell {
					let width = Int(cv.bounds.width) - HorizontalLineLayout.cellStride
					val.frame = CGRect(x: index * HorizontalLineLayout.cellStride, y: 0, width: width, height: 80)
				}
			}
			result.append(val)
			
			if let parent = parentCell, parent.selectedImages.contains(where: { $0.path == path }) {
				if let decoration = layoutAttributesForDecorationView(ofKind: "checkmark", at: path) {
					result.append(decoration)
				}
			}
			
			path.row += 1
		}
		
		return result
	}
	
	override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
		let result = super.layoutAttributesForItem(at: indexPath) ?? UICollectionViewLayoutAttributes(forCellWith: indexPath)
		guard let cv = collectionView, let ds = cv.dataSource else {
			return result
		}
		var cellFlatIndex = indexPath.row
		for sectionIndex in 0..<indexPath.section {
			cellFlatIndex += ds.collectionView(cv, numberOfItemsInSection: sectionIndex)
		}
	
		result.isHidden = false
		result.frame = CGRect(x: cellFlatIndex * HorizontalLineLayout.cellStride, y: 0,
				width: HorizontalLineLayout.cellWidth, height: 80)
		return result
	}

	override func layoutAttributesForDecorationView(ofKind elementKind: String, at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        if elementKind == "checkmark" {
            let attributes = UICollectionViewLayoutAttributes(forDecorationViewOfKind: "checkmark", with: indexPath)
            var xOffset = indexPath.row
            for section in 0..<indexPath.section {
				xOffset += collectionView!.dataSource!.collectionView(collectionView!, numberOfItemsInSection: section)
			}
			
            attributes.frame = CGRect(x: xOffset * HorizontalLineLayout.cellStride + 60, y: 0, width: 20, height: 20)
            return attributes
        }
        return nil
	}
	
	override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
		if let cv = collectionView, newBounds.size.height != cv.bounds.size.height {
			return true
		}
		return false
	}
}

// This is the decoration that appears on the top right of photos when they're selected.
class CheckmarkReusableView: UICollectionReusableView {
	override init(frame: CGRect) {
		super.init(frame: frame)
		let config = UIImage.SymbolConfiguration(paletteColors: [.white, .systemBlue])
		let checkmarkImageView = UIImageView(image: UIImage(systemName: "checkmark.circle")?.applyingSymbolConfiguration(config))
		checkmarkImageView.contentMode = .scaleAspectFit
		addSubview(checkmarkImageView)
		checkmarkImageView.translatesAutoresizingMaskIntoConstraints = false
		NSLayoutConstraint.activate([
				leadingAnchor.constraint(equalTo: checkmarkImageView.leadingAnchor),
				trailingAnchor.constraint(equalTo: checkmarkImageView.trailingAnchor),
				topAnchor.constraint(equalTo: checkmarkImageView.topAnchor),
				bottomAnchor.constraint(equalTo: checkmarkImageView.bottomAnchor),
				widthAnchor.constraint(equalToConstant: 20),
				heightAnchor.constraint(equalToConstant: 20),
				])
	}
	
	 @MainActor required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}
}
