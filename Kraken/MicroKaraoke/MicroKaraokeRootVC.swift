//
//  MicroKaraokeRootVC.swift
//  Kraken
//
//  Created by Chall Fry on 1/22/24.
//  Copyright © 2024 Chall Fry. All rights reserved.
//

import Foundation
import UIKit
import AVFoundation
import AVKit

class MicroKaraokeRootViewController: BaseCollectionViewController {
	
	let mkDataSource = KrakenDataSource()
			var composeSegment = FilteringDataSourceSegment() 
			var songsSegment = FRCDataSourceSegment<MicroKaraokeSong>()
	let loginDataSource = KrakenDataSource()
	let loginSection = LoginDataSourceSegment()
   
	@objc dynamic lazy var explainerCell = MKExplainerCellModel(action: makeRecordingButtonTapped)
	@objc dynamic lazy var loadingCell = MKLoaderCellModel()
	@objc dynamic lazy var successfulUploadCell = UploadCellModel()
	@objc dynamic lazy var completedVideosLabelCell = LabelCellModel("See Completed Videos:")

	override func viewDidLoad() {
        super.viewDidLoad()
        self.title = "Micro Karaoke"

		mkDataSource.register(with: collectionView, viewController: self)
 		mkDataSource.append(segment: composeSegment)
//		let composeSection = mkDataSource.appendFilteringSegment(named: "ComposeSection")
		composeSegment.append(explainerCell)
		composeSegment.append(loadingCell)
		composeSegment.append(successfulUploadCell)
		composeSegment.append(completedVideosLabelCell)
		
		mkDataSource.append(segment: songsSegment)
		songsSegment.activate(predicate: NSPredicate(value: true), sort: [NSSortDescriptor(key: "id", ascending: true)], 
				cellModelFactory: createSongCellModel)
		
		loadingCell.shouldBeVisible = false
		loadingCell.showSpinner = true
		successfulUploadCell.shouldBeVisible = false


// TODO: 1 minute timer
		MicroKaraokeDataManager.shared.getCompletedVideos()
	}
	
    override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		mkDataSource.enableAnimations = true
	}
	
// MARK: Navigation
	override var knownSegues : Set<GlobalKnownSegue> {
		Set<GlobalKnownSegue>([ .microKaraokeCamera, .microKaraokeTitleCard ])
	}
	
	var errorObservation: EBNObservation?
	func makeRecordingButtonTapped() {
		explainerCell.enableActionButton = false
		loadingCell.shouldBeVisible = true
		loadingCell.statusText = "Asking Server for Song Clip..."
		MicroKaraokeDataManager.shared.downloadOffer(done: {
			DispatchQueue.main.async {
				self.explainerCell.enableActionButton = true
				self.loadingCell.shouldBeVisible = false
				self.errorObservation?.stopObservations()
//				self.performKrakenSegue(.microKaraokeCamera, sender: nil)
				self.performKrakenSegue(.microKaraokeTitleCard, sender: nil)
			}
		})
		errorObservation = MicroKaraokeDataManager.shared.tell(self, when: "lastNetworkError") { observer, observed in 
			observer.explainerCell.enableActionButton = true
			observer.loadingCell.errorText = nil
			if let err = observed.lastNetworkError {
				observer.loadingCell.errorText = "Error: \(err)"
			}
		}
	}

	// This is the unwind segue for when the user cancels from the camera view
	@IBAction func cancelledMKRecording(unwindSegue: UIStoryboardSegue) {
	}

	// This is the unwind segue for when the user is done recording a clip
	@IBAction func doneRecordingClip(unwindSegue: UIStoryboardSegue) {
		explainerCell.enableActionButton = false
		loadingCell.shouldBeVisible = true
		successfulUploadCell.shouldBeVisible = false
		loadingCell.statusText = "Uploading Video..."
		MicroKaraokeDataManager.shared.uploadVideoClip(done: {
			self.explainerCell.enableActionButton = true
			self.loadingCell.shouldBeVisible = false
			self.errorObservation?.stopObservations()
			self.successfulUploadCell.shouldBeVisible = true
		})
		errorObservation = MicroKaraokeDataManager.shared.tell(self, when: "lastNetworkError") { observer, observed in 
			observer.explainerCell.enableActionButton = true
			observer.loadingCell.errorText = nil
			if let err = observed.lastNetworkError {
				observer.loadingCell.errorText = "Error: \(err)"
			}
		}
	}
	
	// Called by the CompletedSongCellModel when the music video is ready to view
	func showMovie(_ finishedMovie: AVPlayerItem) {
		let player = AVPlayer(playerItem: finishedMovie)
		let newVC = AVPlayerViewController()
		newVC.player = player
		self.present(newVC, animated: true) {
			newVC.player?.play()
		}
	}
	
// MARK: Custom Cells	
	func createSongCellModel(_ model: MicroKaraokeSong) -> BaseCellModel {
		let cellModel =  CompletedSongCellModel(songModel: model, vc: self)
		return cellModel
	}

}

// MARK: - Explainer Cell
@objc protocol ExplainerCellProtocol {
	dynamic var actionButtonTapped: (() -> Void)? { get set } 
	dynamic var enableActionButton: Bool { get set }
}

class MKExplainerCellModel: BaseCellModel, ExplainerCellProtocol {
	override class var validReuseIDDict: [String: BaseCollectionViewCell.Type ] { 
		return [ "MKExplainerCell" : MKExplainerCell.self ] 
	}

	dynamic var actionButtonTapped: (() -> Void)?
	dynamic var enableActionButton: Bool = true

	init(action: @escaping () -> Void) {
		super.init(bindingWith: ExplainerCellProtocol.self)
		actionButtonTapped = action
	}
}

class MKExplainerCell: BaseCollectionViewCell, ExplainerCellProtocol {
	@IBOutlet var label: UILabel!
	@IBOutlet var actionButton: UIButton!
	private static let cellInfo = [ "MKExplainerCell" : PrototypeCellInfo("MicroKaraokeExplainerCell") ]
	override class var validReuseIDDict: [ String: PrototypeCellInfo] { return MKExplainerCell.cellInfo }
	
	dynamic var actionButtonTapped: (() -> Void)?
	dynamic var enableActionButton: Bool = true {
		didSet { 
			actionButton.isEnabled = enableActionButton
		}
	}

	override func awakeFromNib() {
		super.awakeFromNib()
		label.styleFor(.body)
		actionButton.styleFor(.body)
		
		let explainerText = NSMutableAttributedString(string: "What's Micro Karaoke?\n\nYou'll sing ", attributes: bodyTextAttributes())
		explainerText.append(string: "one line", attrs: boldTextAttributes())
		explainerText.append(string: """
				 of a song while recording video. You won't know what song, or what line, until you start!
				
				Later, watch a music video with you in it.
				""", attrs: bodyTextAttributes())
		label.attributedText = explainerText
	}
	
	func boldTextAttributes() -> [ NSAttributedString.Key : Any ] {
		let metrics = UIFontMetrics(forTextStyle: .body)
		let baseFont = UIFont(name:"Helvetica-Bold", size: 17) ?? UIFont.preferredFont(forTextStyle: .body)
		let scaledfont = metrics.scaledFont(for: baseFont)
		let result: [NSAttributedString.Key : Any] = [ .font : scaledfont as Any, 
				.foregroundColor : UIColor(named: "Kraken Label Text") as Any ]
		return result
	}
	
	func bodyTextAttributes() -> [ NSAttributedString.Key : Any ] {
		let metrics = UIFontMetrics(forTextStyle: .body)
		let baseFont = UIFont(name:"Helvetica-Regular", size: 17) ?? UIFont.preferredFont(forTextStyle: .body)
		let scaledfont = metrics.scaledFont(for: baseFont)
		let result: [NSAttributedString.Key : Any] = [ .font : scaledfont as Any, 
				.foregroundColor : UIColor(named: "Kraken Label Text") as Any ]
		return result
	}
	
	@IBAction func actionButtonHit(_ sender: Any) {
		actionButtonTapped?()
	}
}

class MKLoaderCellModel: LoadingStatusCellModel {
	private static let validReuseIDs = [ "LoadingStatusBubbleCell" : LoadingStatusCell.self ]
	override class var validReuseIDDict: [String: BaseCollectionViewCell.Type ] { return validReuseIDs }
    override func reuseID(traits: UITraitCollection) -> String {
		return "LoadingStatusBubbleCell"
	}
}

// MARK: - Sucessful Upload Cell
@objc protocol UploadCellProtocol {
}

class UploadCellModel: BaseCellModel, UploadCellProtocol {
	override class var validReuseIDDict: [String: BaseCollectionViewCell.Type ] { return [ "UploadCell" : UploadCell.self ] }

	init() {
		super.init(bindingWith: UploadCellProtocol.self)
	}
}

class UploadCell: BaseCollectionViewCell, UploadCellProtocol {
	private static let cellInfo = [ "UploadCell" : PrototypeCellInfo("UploadCell") ]
	override class var validReuseIDDict: [ String: PrototypeCellInfo] { return UploadCell.cellInfo }
	
	@IBOutlet weak var label: UILabel!

	override func awakeFromNib() {
		super.awakeFromNib()
		label.styleFor(.body)
	}
}


// MARK: - Custom Views

@objc class MKRoundedRectView: UIView {
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
		if let color = UIColor(named: "AnnouncementHeader") {
			context?.setStrokeColor(color.cgColor)
			rectPath.stroke()
		}

	}
}
