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

class MicroKaraokeSongAndArtistVC: UIViewController {
		
	@IBOutlet weak var songTitleLabel: UILabel!
	@IBOutlet weak var artistLabel: UILabel!
	@IBOutlet weak var playlistSongLabel: UILabel!
	@IBOutlet weak var blackCoverView: UIView!
	
	
	override func viewDidLoad() {
        super.viewDidLoad()
        self.title = "Micro Karaoke"
	}
	
    override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		songTitleLabel.text = MicroKaraokeDataManager.shared.getCurrentOffer()?.songName ?? "<unknown>"
		artistLabel.text = MicroKaraokeDataManager.shared.getCurrentOffer()?.artistName ?? "<unknown>"
		if let songID = MicroKaraokeDataManager.shared.getCurrentOffer()?.songID {
			playlistSongLabel.text = "Playlist Song \(songID)"
		}
		else {
			playlistSongLabel.text = ""
		}
	}
	
// MARK: Navigation
	@IBAction func okayButtonHit(_ sender: Any) {
		if MicroKaraokeDataManager.shared.getCurrentOffer()?.portraitMode == true {
			performSegue(withIdentifier: GlobalKnownSegue.microKaraokeCamera.rawValue, sender: self)
		}
		else {
			performSegue(withIdentifier: GlobalKnownSegue.microKaraokeCameraLandscape.rawValue, sender: self)
		}
	}
	
	// Catch the doneRecordingClip unwind, wait for the UI to rotate back to portrait if necessary, then re-issue the unwind.
	// Cover the view with black so this isn't as visible. This all is to hide the weird screen rotation that happens when we
	// switch out of landscape.
	@IBAction func doneRecordingClip(unwindSegue: UIStoryboardSegue) {
		blackCoverView.isHidden = false
		Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false, block: { timer in
			self.performSegue(withIdentifier: "doneRecordingClip", sender: nil)
		})
	}
	
	var knownSegues : Set<GlobalKnownSegue> {
		Set<GlobalKnownSegue>([ .microKaraokeCamera, .microKaraokeCameraLandscape ])
	}
}

