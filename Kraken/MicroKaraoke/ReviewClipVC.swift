//
//  ReviewClipVC.swift
//  Kraken
//
//  Created by Chall Fry on 2/2/24.
//  Copyright © 2024 Chall Fry. All rights reserved.
//

import Foundation
import AVFoundation
import CoreMotion
import MediaPlayer

class ReviewClipViewController: UIViewController {
	@IBOutlet weak var videoView: ReviewClipView!
	@IBOutlet weak var uploadButton: UIButton!
	
	public var clipURL: URL?
	public var rotateView180 = false
	
	override func viewDidLoad() {
        super.viewDidLoad()
        
        if rotateView180 {
			self.view.transform = CGAffineTransform(rotationAngle: CGFloat.pi * CGFloat(180) / 180.0)
		}
 
        if let clipURL = clipURL {
	        videoView.configure(clipURL)
	        videoView.play()
		}
    }
    
	override func viewDidLayoutSubviews() {
		super.viewDidLayoutSubviews()
		videoView.positionPlayerLayer()
	}		

	@IBAction func uploadButtonTapped() {
		(UIApplication.shared.delegate as? AppDelegate)?.makeThisVCLandscape = false
		performSegue(withIdentifier: "doneRecordingClip", sender: nil)
    }
    
	@IBAction func retryButtonTapped(_ sender: Any) {
		performSegue(withIdentifier: "retryMKRecording", sender: nil)
	}
    
}

class ReviewClipView: UIView {
    
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
    
    func positionPlayerLayer() {
		playerLayer?.frame = bounds
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
