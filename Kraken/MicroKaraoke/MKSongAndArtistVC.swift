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
	var knownSegues : Set<GlobalKnownSegue> {
		Set<GlobalKnownSegue>([ .microKaraokeCamera ])
	}
}

