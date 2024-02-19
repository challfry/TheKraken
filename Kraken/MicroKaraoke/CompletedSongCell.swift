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
	dynamic var showUserInVideoView: Bool { get set }
	dynamic var showModerationView: Bool { get set }
	dynamic var showDownloadView: Bool { get set }
	dynamic var allowVideoPlay: Bool { get set }
	dynamic var videoPlayedOnce: Bool { get set }
	dynamic var errorString: String? { get set }
}

class CompletedSongCellModel: FetchedResultsCellModel, CompletedSongCellProtocol {
	override class var validReuseIDDict: [String: BaseCollectionViewCell.Type ] { 
		return [ "CompletedSongCell" : CompletedSongCell.self ] 
	}

	dynamic var songID: Int64 = 0
	dynamic var songTitle: String = ""
	dynamic var artistName: String = ""
	dynamic var showUserInVideoView: Bool = false
	dynamic var showModerationView: Bool = false
	dynamic var showDownloadView: Bool = false
	dynamic var allowVideoPlay: Bool = false
	dynamic var videoPlayedOnce: Bool = false
	dynamic var errorString: String?
	
	weak var vc: BaseCollectionViewController?

    override var model: NSFetchRequestResult? {
    	didSet {
    		clearObservations()
    		if let songModel = model as? MicroKaraokeSong {
//				if !songModel.modApproved {
//					// Hide the cell if the song isn't approved yet, unless it's a mod
//					if let currentUser = CurrentUser.shared.loggedInUser, currentUser.accessLevel >= .moderator {
//						shouldBeVisible = true
//						showModerationView = true
//					}
//					else {
//						shouldBeVisible = false
//					}
//					
//				}
//				
//				// Only allow the video to play if the song's completed.
//				allowVideoPlay = songModel.completionTime != nil
   		
    			songID = songModel.id
    			songTitle = songModel.songName
    			artistName = songModel.artistName
//    			showUserInVideoView = songModel.userContributed
			}
			
		}
	}

	init(songModel: MicroKaraokeSong, vc: BaseCollectionViewController) {
		super.init(withModel: songModel, reuse: "CompletedSongCell", bindingWith: CompletedSongCellProtocol.self)
		model = songModel
		self.vc = vc
		
		self.tell(self, when: "model.modApproved") { observer, observed in 
			if let model = observed.model as? MicroKaraokeSong, !model.modApproved {
				// Hide the cell if the song isn't approved yet, unless it's a mod
				if let currentUser = CurrentUser.shared.loggedInUser, currentUser.accessLevel >= .moderator {
					observer.shouldBeVisible = true
					observer.showModerationView = true
				}
				else {
					observer.shouldBeVisible = false
				}
			}
			else {
				observer.showModerationView = false
			}
		}?.execute()
		self.tell(self, when: "model.completionTime") { observer, observed in 
			observer.allowVideoPlay = (observed.model as? MicroKaraokeSong)?.completionTime != nil
		}?.execute()
		self.tell(self, when: "model.userContributed") { observer, observed in 
			if let model = observed.model as? MicroKaraokeSong, model.userContributed {
				observer.showUserInVideoView = true
			}
			else {
				observed.showUserInVideoView = false
			}
		}?.execute()
	}
	
	func playButtonTapped() {
		showDownloadView = true
		errorString = nil
		MicroKaraokeDataManager.shared.downloadCompletedSong(songID: songID) { (finishedVideo: AVPlayerItem?, 
				movieFile: URL?, errorString: String?) in
			self.showDownloadView = false
			if let err = errorString {
				self.errorString = err
			}
			else if let vc = self.vc as? MicroKaraokeRootViewController {
				if let player = finishedVideo {
					vc.showMovie(player)
					self.videoPlayedOnce = true
				}
				else if let movie = movieFile {
					let activityViewController = UIActivityViewController(activityItems: [movie], applicationActivities: nil)
					self.vc!.present(activityViewController, animated: true, completion: {})
				}
			}
		}
	}
	
	func modApproveTapped() {
		errorString = nil
		MicroKaraokeDataManager.shared.modApproveSong(song: songID) { error in 
			self.errorString = error
			if error == nil {
				self.showModerationView = true
			}
		}
	}
}

class CompletedSongCell: BaseCollectionViewCell, CompletedSongCellProtocol {
	private static let cellInfo = [ "CompletedSongCell" : PrototypeCellInfo("CompletedSongCell") ]
	override class var validReuseIDDict: [ String: PrototypeCellInfo] { return CompletedSongCell.cellInfo }

	// Info View
		@IBOutlet weak var songIDLabel: UILabel!
		@IBOutlet weak var songTitleLabel: UILabel!
		@IBOutlet weak var artistLabel: UILabel!
		@IBOutlet weak var playButton: UIButton!
	@IBOutlet weak var userInVideoView: UIView!				// You're in this video!
	@IBOutlet weak var moderationView: UIView!
		@IBOutlet weak var approveLabel: UILabel!
		@IBOutlet weak var approveButton: UIButton!
	@IBOutlet weak var downloadView: UIView!
		@IBOutlet weak var downloadingLabel: UILabel!
		@IBOutlet weak var progressBar: UIProgressView!
	@IBOutlet weak var errorView: UIView!
		@IBOutlet weak var errorLabel: UILabel!
	// Bottom Horiz. Rule
	
	dynamic var songID: Int64 = 0 { didSet { songIDLabel.text = String(songID) } }
	dynamic var songTitle: String = "" { didSet { songTitleLabel.text = songTitle } }
	dynamic var artistName: String = "" { didSet { artistLabel.text = artistName } }
	dynamic var showUserInVideoView: Bool = false {
		didSet {
			userInVideoView.isHidden = !showUserInVideoView
			cellSizeChanged()
		}
	}
	dynamic var showModerationView: Bool = false {
		didSet {
			moderationView.isHidden = !showModerationView
			cellSizeChanged()
		}
	}
	dynamic var videoPlayedOnce: Bool = false {
		didSet {
			approveLabel.text = videoPlayedOnce ? "Awaiting Mod Approval" : "Mods: View Video to Approve"
			approveButton.isEnabled = videoPlayedOnce
		}
	}
	dynamic var showDownloadView: Bool = false {
		didSet {
			downloadView.isHidden = !showDownloadView
			if showDownloadView {
				if progressTimer == nil {
					progressTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { timer in
						self.progressBar.progress = MicroKaraokeDataManager.shared.songDownloadProgress
					}
				}
			}
			else {
				progressTimer?.invalidate()
			}
			cellSizeChanged()
		}
	}
	dynamic var allowVideoPlay: Bool = false {
		didSet {
			playButton.isEnabled = allowVideoPlay
		}
	}
	dynamic var errorString: String? {
		didSet {
			errorView.isHidden = errorString == nil
			errorLabel.text = errorString
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
			
			let disableColors = [UIColor.gray, UIColor.lightGray]
			let disableConfig = config.applying(UIImage.SymbolConfiguration(paletteColors: disableColors))
			playButton.setImage(normalImage, for: .disabled)
			playButton.setPreferredSymbolConfiguration(disableConfig, forImageIn: .disabled)
			
			downloadView.isHidden = true
		}
		
		MicroKaraokeDataManager.shared.tell(self, when: "downloadingVideoForSongID") { observer, observed in 
			if let songIDStr = observed.downloadingVideoForSongID, let songID = Int(songIDStr) {
				observer.playButton.isEnabled = false
				observer.downloadView.isHidden = songID != observer.songID
			}
			else {
				observer.playButton.isEnabled = observer.allowVideoPlay
				observer.downloadView.isHidden = true
			}
		}?.execute()
	}
	
	@IBAction func playButtonHit(_ sender: Any) {
		if let cellModel = cellModel as? CompletedSongCellModel {
			cellModel.playButtonTapped()
		}
	}
	
	@IBAction func approveButtonHit(_ sender: Any) {
		if let cellModel = cellModel as? CompletedSongCellModel {
			cellModel.modApproveTapped()
			approveButton.isEnabled = false
		}
	}
	
	@IBAction func webModerationButtonHit(_ sender: Any) {
		if let modPageURL = URL(string: "/moderate/microkaraoke/song/\(songID)", relativeTo: Settings.shared.baseURL) {
			UIApplication.shared.open(modPageURL)
		}
	}
}
