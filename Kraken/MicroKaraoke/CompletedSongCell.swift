//
//  CompletedSongCell.swift
//  Kraken
//
//  Created by Chall Fry on 2/5/24.
//  Copyright © 2024 Chall Fry. All rights reserved.
//

import Foundation
import UIKit
import CoreData
import AVFoundation

@objc protocol CompletedSongCellProtocol {
	dynamic var songID: Int64 { get set } 
	dynamic var songTitle: String { get set } 
	dynamic var artistName: String { get set }
	dynamic var showDownloadView: Bool { get set }
}

class CompletedSongCellModel: FetchedResultsCellModel, CompletedSongCellProtocol {
	override class var validReuseIDDict: [String: BaseCollectionViewCell.Type ] { 
		return [ "CompletedSongCell" : CompletedSongCell.self ] 
	}

	dynamic var songID: Int64 = 0
	dynamic var songTitle: String = ""
	dynamic var artistName: String = ""
	dynamic var showDownloadView: Bool = false
	
	weak var vc: BaseCollectionViewController?

    override var model: NSFetchRequestResult? {
    	didSet {
    		clearObservations()
    		if let songModel = model as? MicroKaraokeSong {
    			songID = songModel.id
    			songTitle = songModel.songName
    			artistName = songModel.artistName
			}
		}
	}

	init(songModel: MicroKaraokeSong, vc: BaseCollectionViewController) {
		super.init(withModel: songModel, reuse: "CompletedSongCell", bindingWith: CompletedSongCellProtocol.self)
		model = songModel
		self.vc = vc
	}
	
	func playButtonTapped() {
		showDownloadView = true
		MicroKaraokeDataManager.shared.downloadCompletedSong(songID: songID) { (finishedVideo: AVPlayerItem?, movieFile: URL?) in
			self.showDownloadView = false
			if let vc = self.vc as? MicroKaraokeRootViewController {
				if let player = finishedVideo {
					vc.showMovie(player)
				}
				else if let movie = movieFile {
					let activityViewController = UIActivityViewController(activityItems: [movie], applicationActivities: nil)
					self.vc!.present(activityViewController, animated: true, completion: {})
				}
			}
		}
	}
}

class CompletedSongCell: BaseCollectionViewCell, CompletedSongCellProtocol {
	private static let cellInfo = [ "CompletedSongCell" : PrototypeCellInfo("CompletedSongCell") ]
	override class var validReuseIDDict: [ String: PrototypeCellInfo] { return CompletedSongCell.cellInfo }

	@IBOutlet weak var songIDLabel: UILabel!
	@IBOutlet weak var songTitleLabel: UILabel!
	@IBOutlet weak var artistLabel: UILabel!
	@IBOutlet weak var playButton: UIButton!
	@IBOutlet weak var downloadView: UIView!
		@IBOutlet weak var downloadingLabel: UILabel!
		@IBOutlet weak var progressBar: UIProgressView!
	
	dynamic var songID: Int64 = 0 { didSet { songIDLabel.text = String(songID) } }
	dynamic var songTitle: String = "" { didSet { songTitleLabel.text = songTitle } }
	dynamic var artistName: String = "" { didSet { artistLabel.text = artistName } }
	dynamic var showDownloadView: Bool = false {
		didSet {
			downloadView.isHidden = !showDownloadView
			if showDownloadView, progressTimer != nil {
				progressTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { timer in
					self.progressBar.progress = MicroKaraokeDataManager.shared.songDownloadProgress
				}
			}
			else {
				progressTimer?.invalidate()
			}
		}
	}
	
	var progressTimer: Timer?

	override func awakeFromNib() {
		super.awakeFromNib()
		songIDLabel.styleFor(.body)
		songTitleLabel.styleFor(.body)
		artistLabel.styleFor(.body)
		downloadingLabel.styleFor(.body)		
		if let normalImage = UIImage(systemName: "play.rectangle"), let highlightedImage = UIImage(systemName: "play.rectangle.fill") {
			let colors = [UIColor(named: "Icon Foreground") ?? UIColor.black, UIColor(named: "Kraken Icon Blue" ) ?? UIColor.blue]
			let config = (normalImage.symbolConfiguration ?? UIImage.SymbolConfiguration(weight: .regular))
					.applying(UIImage.SymbolConfiguration(paletteColors: colors))
					.applying(UIImage.SymbolConfiguration(pointSize: 30.0))
					.applying(UIImage.SymbolConfiguration(scale: .large))
			playButton.setImage(normalImage, for: .normal)
			playButton.setImage(highlightedImage, for: .highlighted)
			playButton.setPreferredSymbolConfiguration(config, forImageIn: .normal)
			playButton.setPreferredSymbolConfiguration(config, forImageIn: .highlighted)
			
			downloadView.isHidden = true
		}
		
		MicroKaraokeDataManager.shared.tell(self, when: "downloadingVideoForSongID") { observer, observed in 
			if let songIDStr = observed.downloadingVideoForSongID, let songID = Int(songIDStr) {
				observer.playButton.isEnabled = false
				observer.downloadView.isHidden = songID != observer.songID
			}
			else {
				observer.playButton.isEnabled = true
				observer.downloadView.isHidden = true
			}
		}?.execute()
	}
	
	@IBAction func playButtonHit(_ sender: Any) {
		if let cellModel = cellModel as? CompletedSongCellModel {
			cellModel.playButtonTapped()
		}
	}
}
