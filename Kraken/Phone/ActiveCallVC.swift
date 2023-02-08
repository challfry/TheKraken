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
	let composeDataSource = KrakenDataSource()
	let audioRouteSection =		FilteringDataSourceSegment()
	
	override func viewDidLoad() {
		allowTransparency = false
        super.viewDidLoad()
        
        // Fill in the collection view with the available audio routes
        // Because we're on a boat, there's no need to handle all the possible route configs (AirPlay, CarPlay, multiple headphones, AirPods)
		composeDataSource.register(with: collectionView, viewController: self)
		audioRouteSection.append(AudioRouteCellModel(title: "Microphone", image: UIImage(systemName: "phone"), route: .microphone, checked: true))
		audioRouteSection.append(AudioRouteCellModel(title: "Speaker", image: UIImage(systemName: "speaker"), route: .speaker))
		if PhonecallDataManager.shared.hasWiredHeadphoneRoute() {
			audioRouteSection.append(AudioRouteCellModel(title: "Wired Headphones", image: UIImage(systemName: "headphones"), route: .headphone))
		}
		if PhonecallDataManager.shared.hasWirelessHeadphoneRoute() {
			audioRouteSection.append(AudioRouteCellModel(title: "Headphones", image: UIImage(systemName: "headphones.circle"), route: .bluetooth))
		}
		composeDataSource.append(segment: audioRouteSection)

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
		}?.execute()
		
		NotificationCenter.default.addObserver(self, selector: #selector(engineRouteChanged),
				name: .AVAudioEngineConfigurationChange, object: nil)
	}
		
	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)

		// Its possible the call fails or gets canceled before we can even open.
		if PhonecallDataManager.shared.currentCall == nil {
			dismiss(animated: true)
		}

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
				self.callTimeLabel.text = "Setting up Call"
			}
		}
		
		let currentRoute = PhonecallDataManager.shared.getAudioRoute()
		self.audioRouteSection.visibleCellModels.forEach {
			if let cellModel = $0 as? AudioRouteCellModel {
				cellModel.routeIsSelected = cellModel.route == currentRoute
			}	
		}
	}
	
	override func viewDidDisappear(_ animated: Bool) {
		super.viewDidDisappear(animated)
		updateTimer?.invalidate()
	}
	
	@IBAction func endCallTapped() {
		PhonecallDataManager.shared.endCall(reason: .unanswered)
		self.dismiss(animated: true)
	}
	
	func audioRouteTapped(_ route: PhonecallDataManager.AudioRoute) {
		PhonecallDataManager.shared.setAudioRoute(route)
		audioRouteSection.visibleCellModels.forEach {
			if let cellModel = $0 as? AudioRouteCellModel {
				cellModel.routeIsSelected = false
			}
		}
	}
	
	@objc func engineRouteChanged(notification: Notification) {
		DispatchQueue.main.async {
			let currentRoute = PhonecallDataManager.shared.getAudioRoute()
			self.audioRouteSection.visibleCellModels.forEach {
				if let cellModel = $0 as? AudioRouteCellModel {
					cellModel.routeIsSelected = cellModel.route == currentRoute
				}
			}
		}
	}

}
