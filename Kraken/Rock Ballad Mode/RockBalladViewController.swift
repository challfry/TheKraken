//
//  RockBalladViewController.swift
//  Kraken
//
//  Created by Chall Fry on 2/18/20.
//  Copyright © 2020 Chall Fry. All rights reserved.
//

import UIKit
import AVKit
import AVFoundation

class RockBalladViewController: UIViewController {
	@IBOutlet var videoView: VideoView!
	@IBOutlet var closeButton: UIButton!
	
	override var prefersStatusBarHidden: Bool {
		return true
	}

    override func viewDidLoad() {
        super.viewDidLoad()
        
        if let videoURL = Bundle.main.url(forResource: "RockBalladMode", withExtension: "mov") {
	        videoView.configure(videoURL)
	        videoView.play()
		}
    }
    
	@IBAction func closeButtonTapped(_ sender: Any) {
		dismiss(animated: true, completion: nil)
	}    
}

class VideoView: UIView {
    
    var playerLayer: AVPlayerLayer?
    var player: AVPlayer?
    var isLoop: Bool = false
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        
    }
    
    func configure(_ videoURL: URL) {
		player = AVPlayer(url: videoURL)
		playerLayer = AVPlayerLayer(player: player)
		playerLayer?.frame = bounds
		playerLayer?.videoGravity = AVLayerVideoGravity.resizeAspectFill
		if let playerLayer = self.playerLayer {
			layer.addSublayer(playerLayer)
		}
		NotificationCenter.default.addObserver(self, selector: #selector(reachTheEndOfTheVideo(_:)), 
				name: NSNotification.Name.AVPlayerItemDidPlayToEndTime, object: self.player?.currentItem)
    }
    
    func play() {
		if player?.timeControlStatus != AVPlayer.TimeControlStatus.playing {
            player?.play()
        }
    }
    
    func pause() {
        player?.pause()
    }
    
    func stop() {
        player?.pause()
		player?.seek(to: CMTime.zero)
    }
    
	@objc func reachTheEndOfTheVideo(_ notification: Notification) {
		player?.pause()
		player?.seek(to: CMTime.zero)
		player?.play()
    }
}
