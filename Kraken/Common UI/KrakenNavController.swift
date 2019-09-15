//
//  KrakenNavController.swift
//  Kraken
//
//  Created by Chall Fry on 8/8/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit


class KrakenNavController: UINavigationController, GlobalNavEnabled {
	var networkLabel = UILabel()
	
	override func viewDidLoad() {
        super.viewDidLoad()
        
        networkLabel.backgroundColor = UIColor(red: 1.0, green: 240.0 / 255.0, blue: 210.0 / 255.0, alpha: 0.90)
		networkLabel.font = UIFont.italicSystemFont(ofSize: 14)
		networkLabel.text = "No network — Can't connect to the Twitarr server"
		networkLabel.textAlignment = .center
		view.addSubview(networkLabel)
		networkLabel.translatesAutoresizingMaskIntoConstraints = false
		networkLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor).isActive = true
		networkLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor).isActive = true
		networkLabel.topAnchor.constraint(equalTo: navigationBar.bottomAnchor).isActive = true
	
	
		NetworkGovernor.shared.tell(self, when: "connectionState") { observer, governor in
			observer.networkLabel.isHidden = governor.connectionState == NetworkGovernor.ConnectionState.canConnect			
		}?.execute()
    }
    
    // By default, nav controllers just pass global nav actions to their root, or the first VC in their stack
    // that can handle nav.
    func globalNavigateTo(packet: GlobalNavPacket) {
    	if viewControllers.count > 0, let rootVC = viewControllers[0] as? GlobalNavEnabled {
    		rootVC.globalNavigateTo(packet: packet)
    	}
    }
}


//        let effectView = UIVisualEffectView(effect: UIBlurEffect(style: .regular))
//		view.addSubview(effectView)
//		effectView.translatesAutoresizingMaskIntoConstraints = false
//		effectView.leadingAnchor.constraint(equalTo: view.leadingAnchor).isActive = true
//		effectView.trailingAnchor.constraint(equalTo: view.trailingAnchor).isActive = true
//		effectView.topAnchor.constraint(equalTo: navigationBar.bottomAnchor).isActive = true
//        
//        networkLabel.backgroundColor = UIColor(red: 1.0, green: 240.0 / 255.0, blue: 210.0 / 255.0, alpha: 1.0)
//		networkLabel.font = UIFont.italicSystemFont(ofSize: 14)
//		networkLabel.text = "No network — Can't connect to the Twitarr server"
//		networkLabel.textAlignment = .center
//		effectView.contentView.addSubview(networkLabel)
//		networkLabel.translatesAutoresizingMaskIntoConstraints = false
//		networkLabel.leadingAnchor.constraint(equalTo: effectView.contentView.leadingAnchor).isActive = true
//		networkLabel.trailingAnchor.constraint(equalTo: effectView.contentView.trailingAnchor).isActive = true
//		networkLabel.topAnchor.constraint(equalTo: effectView.contentView.topAnchor).isActive = true
//		networkLabel.bottomAnchor.constraint(equalTo: effectView.contentView.bottomAnchor).isActive = true
