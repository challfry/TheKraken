//
//  PhotostreamCellModel.swift
//  Kraken
//
//  Created by Chall Fry on 4/20/24.
//  Copyright © 2024 Chall Fry. All rights reserved.
//

import UIKit

@objc protocol PhotostreamCellProtocol {
	var photostreamDataSource: KrakenDataSource? { get set } 
}

class PhotostreamCellModel: BaseCellModel, PhotostreamCellProtocol {
	private static let validReuseIDs = [ "PhotostreamCell" : PhotostreamCell.self ]
	override class var validReuseIDDict: [String: BaseCollectionViewCell.Type ] { return validReuseIDs }

	dynamic var photostreamDataSource: KrakenDataSource? = KrakenDataSource()
	lazy var photosSegment = FRCDataSourceSegment<StreamPhoto>()

	init() {
        super.init(bindingWith: PhotostreamCellProtocol.self)

		CurrentUser.shared.tell(self, when: "loggedInUser") { observer, observed in 
			observer.determineVisibility()
		}?.execute()
		ValidSections.shared.tell(self, when: "mutationCount") { observer, observed in
			observer.determineVisibility()
		}
		
		photostreamDataSource?.append(segment: photosSegment)
		photosSegment.activate(predicate: NSPredicate(value: true), sort: [ NSSortDescriptor(key: "id", ascending: false)],
				cellModelFactory: createCellModel)
    }
    
    func determineVisibility() {
		shouldBeVisible = (CurrentUser.shared.loggedInUser != nil) && !ValidSections.shared.disabledSections.contains(.photostream)
    }
    
	// Gets called from within collectionView:cellForItemAt:. This fn's job is to produce PhotoCameraCellModels for the CV that
	// sits inside this cell.
	func createCellModel(_ model: StreamPhoto) -> BaseCellModel {
		let cellModel = PhotostreamPhotoCellModel(photo: model)
		return cellModel
	}
}

class PhotostreamCell: BaseCollectionViewCell, PhotostreamCellProtocol {
	private static let cellInfo = [ "PhotostreamCell" : PrototypeCellInfo("PhotostreamCell") ]
	override class var validReuseIDDict: [ String: PrototypeCellInfo ] { return cellInfo }

	@IBOutlet weak var photostreamLabel: UILabel!
	@IBOutlet weak var addButton: UIButton!
	@IBOutlet weak var photoCollectionView: UICollectionView!
	
	dynamic var photostreamDataSource: KrakenDataSource? {
		didSet {
			DispatchQueue.main.async() {
				let vc = self.viewController as? BaseCollectionViewController
				self.photostreamDataSource?.register(with: self.photoCollectionView, viewController: vc)
			
				// If this cell was re-made, have to re-register all the cell types our collection uses
				self.photostreamDataSource?.registeredCellReuseIDs.values.forEach {
					$0?.registerCells(with: self.photoCollectionView)
				}
		}
		}
	}
		
	override func awakeFromNib() {
		super.awakeFromNib()
		
		// Font Styling
		photostreamLabel.styleFor(.title2)
		
		addButton.setImage(UIImage(systemName: "photo.badge.plus"), for: .normal)
		addButton.setImage(UIImage(systemName: "photo.badge.plus.fill"), for: .highlighted)
		let config = UIImage.SymbolConfiguration(pointSize: 25).applying(UIImage.SymbolConfiguration.preferringMulticolor())
		addButton.setPreferredSymbolConfiguration(config, forImageIn: .normal)
	}
	
	@IBAction func addPhotoButtonTapped(_ sender: Any) {
		if let appDel = UIApplication.shared.delegate as? AppDelegate, let vc = viewController {
			var packet = GlobalNavPacket(from: vc, tab: .daily)
			packet.segue = .photoStreamCamera
			appDel.globalNavigateTo(packet: packet)
		}
	}
}

// MARK: - Cells Within Cells

@objc protocol PhotostreamPhotoCellProtocol: FetchedResultsBindingProtocol {
//	var buttonHit: ((PhotoCameraCellProtocol) -> Void)? { get set }
	var photo: StreamPhoto? { get set }
}

@objc class PhotostreamPhotoCellModel: FetchedResultsCellModel, PhotostreamPhotoCellProtocol {
	override class var validReuseIDDict: [String: BaseCollectionViewCell.Type ] { 
		return [ "PhotostreamPhotoCell" : PhotostreamPhotoCell.self ] 
	}
	
	dynamic var photo: StreamPhoto?
	
	init(photo: StreamPhoto) {
		self.photo = photo
		super.init(withModel: photo, reuse: "PhotostreamPhotoCell", bindingWith: PhotostreamPhotoCellProtocol.self)
	}
}

@objc class PhotostreamPhotoCell: BaseCollectionViewCell, PhotostreamPhotoCellProtocol {
	private static let cellInfo = [ "PhotostreamPhotoCell" : PrototypeCellInfo("PhotostreamPhotoCell") ]
	override class var validReuseIDDict: [ String: PrototypeCellInfo ] { return cellInfo }
	
	@IBOutlet weak var imageView: UIImageView!
	@IBOutlet weak var locationLabel: UILabel!
	@IBOutlet weak var timeLabel: UILabel!
	
	var model: NSFetchRequestResult?

	dynamic var photo: StreamPhoto? {
		didSet {
			if let photo = photo {
				ImageManager.shared.image(withSize:.medium, forKey: photo.imageFilename) { image in
						self.imageView.image = image
				}
				if let event = photo.event {
					locationLabel.isUserInteractionEnabled = true
					locationLabel.attributedText = NSAttributedString(string: event.title, attributes: [
							.foregroundColor : UIColor(named: "Kraken Icon Blue") ?? UIColor.blue,
							.underlineStyle : NSNumber(1)]) 
				}
				else {
					locationLabel.isUserInteractionEnabled = false
					locationLabel.attributedText = NSAttributedString(string: photo.location ?? "On Boat", attributes: [
							.foregroundColor : UIColor(named: "Kraken Label Text") ?? UIColor.black,
							.underlineStyle : NSNumber(0)]) 
					locationLabel.text = photo.location
				}
				timeLabel.text = timeString(for: photo.createdAt)
			}
		}
	}
	
	override func awakeFromNib() {
		super.awakeFromNib()
		fullWidth = false
		allowsSelection = true
		
		locationLabel.styleFor(.body)
		timeLabel.styleFor(.body)
		imageView.layer.cornerRadius = 10
		
		if !isPrototypeCell {
			// Set up gesture recognizer to detect taps on the (single) photo, and open the fullscreen photo overlay.
			let photoTap = UITapGestureRecognizer(target: self, action: #selector(PhotostreamPhotoCell.photoTapped(_:)))
			imageView.addGestureRecognizer(photoTap)
			let linkTap = UITapGestureRecognizer(target: self, action: #selector(PhotostreamPhotoCell.linkTapped(_:)))
			locationLabel.addGestureRecognizer(linkTap)
		}
	}
	
	@IBAction func photoTapped(_ sender: UITapGestureRecognizer) {
		if let vc = viewController as? BaseCollectionViewController, let image = imageView.image {
			vc.showImageInOverlay(image: image)
		}
	}

	@IBAction func linkTapped(_ sender: UITapGestureRecognizer) {
		if let vc = viewController as? BaseCollectionViewController, let eventID = photo?.event?.id {
			vc.performKrakenSegue(.singleEvent, sender: eventID)
		}
	}

	func timeString(for time: Date) -> String {		
		let dateFormatter = DateFormatter()
		dateFormatter.locale = Locale(identifier: "en_US")
		dateFormatter.dateFormat = "E hh:mm a"
		if let serverTZ = ServerTime.shared.serverTimezone {
			dateFormatter.timeZone = serverTZ
		}
		return dateFormatter.string(from: time)
	}

}

@objc class PhotostreamRoundedRectView: UIView {
	override func draw(_ rect: CGRect) {
		let pathBounds = bounds.insetBy(dx: 10, dy: 5)

		let rectShape = CAShapeLayer()
		rectShape.bounds = pathBounds
		rectShape.position = self.center
		let rectPath = UIBezierPath(roundedRect: pathBounds, cornerRadius: 12)
		rectShape.path = rectPath.cgPath
		layer.mask = rectShape
		layer.masksToBounds = true
		
		let context = UIGraphicsGetCurrentContext()
		if let color = UIColor(named: "PortAndTheme BG") {
			context?.setStrokeColor(color.cgColor)
			rectPath.stroke()
		}

	}
}

