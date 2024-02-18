//
//  Alerts.swift
//  Kraken
//
//  Created by Chall Fry on 9/2/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit

// This method is for places in the app where we want to inform the user of an error, don't have any non-blocking
// way to do so, and don't have access to the frontmost viewController. Usually, this means we're in the data layer,
// but it could also happen inside a collectionViewCell's code.
//
// This method attempts to find the top VC via global search, and uses that to present the alert.
func showErrorAlert(title: String, error: Error) {
	let alert = UIAlertController(title: title, message: error.localizedDescription, preferredStyle: .alert)
	alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
	if let topVC = UIApplication.getTopViewController() {
		topVC.present(alert, animated: true, completion: nil)
	}
}

// Same idea as above, but for code that might not be on the main thread.
func showDelayedTextAlert(title: String, message: String) {
	DispatchQueue.main.async {
		let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
		alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
		if let topVC = UIApplication.getTopViewController() {
			topVC.present(alert, animated: true, completion: nil)
		}
	}
}

extension UIApplication {

    class func getTopViewController(base: UIViewController? = nil) -> UIViewController? {
		let baseVC = base ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap { $0.windows }
				.first { $0.isKeyWindow }?.rootViewController

        if let nav = baseVC as? UINavigationController {
            return getTopViewController(base: nav.visibleViewController)

        } else if let tab = baseVC as? UITabBarController, let selected = tab.selectedViewController {
            return getTopViewController(base: selected)

        } else if let presented = baseVC?.presentedViewController {
            return getTopViewController(base: presented)
        }
        return baseVC
    }
}
