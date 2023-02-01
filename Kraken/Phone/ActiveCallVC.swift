//
//  ActiveCallVC.swift
//  Kraken
//
//  Created by Chall Fry on 1/20/23.
//  Copyright © 2023 Chall Fry. All rights reserved.
//

import Foundation
import UIKit

@objc class ActiveCallVC: BaseCollectionViewController {
	
	@IBOutlet weak var usernameLabel: UILabel!
	@IBOutlet weak var avatarImageView: UIImageView!
	@IBOutlet weak var endCallButton: UIButton!
	@IBOutlet weak var callTimeLabel: UILabel!
	
	var updateTimer: Timer?
	
	override func viewDidLoad() {
		allowTransparency = false
        super.viewDidLoad()
        
        // This prevents the VC from being dismissed by swiping down, or by tapping elsewhere on the screen.
        isModalInPresentation = true
        
        PhonecallDataManager.shared.tell(self, when: "currentCall.other.username") { observer, observed in
			observer.usernameLabel.text = observed.currentCall?.other.username ?? "<unknown>"
        }?.execute()
        PhonecallDataManager.shared.tell(self, when: ["currentCall.other.userImageName", "currentCall.other.fullPhoto"]) { observer, observed in
			observed.currentCall?.other.loadUserFullPhoto()
			observer.avatarImageView.image = observed.currentCall?.other.fullPhoto
        }?.execute()
        
		PhonecallDataManager.shared.tell(self, when: "currentCall") { observer, observed in 
			if observed.currentCall == nil {
				observer.dismiss(animated: true)
			}
		}
	}
	
	override func viewDidAppear(_ animated: Bool) {
		updateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
			guard let self = self else { return }
			if let startTime = PhonecallDataManager.shared.currentCall?.callStartTime {
				let formatter = DateComponentsFormatter()
				formatter.zeroFormattingBehavior = .pad
				let interval = Date().timeIntervalSince(startTime)
				formatter.allowedUnits = interval >= 3600.0 ? [.hour, .minute, .second] : [.minute, .second]
				self.callTimeLabel.text = formatter.string(from: interval)
			}
			else {
				self.callTimeLabel.text = nil
			}
		}
	}
	
	override func viewDidDisappear(_ animated: Bool) {
		updateTimer?.invalidate()
	}
	
	@IBAction func endCallTapped() {
		PhonecallDataManager.shared.endCall()
	}
	
}
