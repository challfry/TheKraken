//
//  KrakenNavController.swift
//  Kraken
//
//  Created by Chall Fry on 8/8/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit

class KrakenNavController: UINavigationController {
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
}
