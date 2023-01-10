//
//  ContainerViewController.swift
//  Kraken
//
//  Created by Chall Fry on 1/28/20.
//  Copyright © 2020 Chall Fry. All rights reserved.
//

import UIKit

class ContainerViewController: UIViewController, GlobalNavEnabled {
	static var shared: ContainerViewController? = nil

	lazy var mainStoryboard = UIStoryboard(name: "Main", bundle: nil)
	var childControllers: [UIViewController] = []
	var childVCSize: CGSize = CGSize.zero
	var numColumns: Int = 1
	var columnWidth: CGFloat = 0
	
	var deepSeaView: UIView?

	override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
		super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
		ContainerViewController.shared = self
	}
	
	required init?(coder aDecoder: NSCoder) {
		super.init(coder: aDecoder)
		ContainerViewController.shared = self
	}
	
    override func viewDidLoad() {
        super.viewDidLoad()
		determineChildLayout(for: view.bounds.size)

		// Show the background image in Deep Sea Mode
		Settings.shared.tell(self, when: "uiDisplayStyle") { observer, observed in 
			if observed.uiDisplayStyle == .deepSeaMode {
				observer.buildDeepSeaImage()
			}
			UIView.animate(withDuration: 0.3) {
				observer.deepSeaView?.alpha = observed.uiDisplayStyle == .deepSeaMode ? 1.0 : 0.0
			}
		}?.execute()
	}
    
    func determineChildLayout(for ourSize: CGSize) {
    	let viewWidth = ourSize.width
    	numColumns = Int((ourSize.width + 100) / 400)
		if UIDevice.current.userInterfaceIdiom == .phone {
			numColumns = 1
			if childControllers.isEmpty {
				let vc = mainStoryboard.instantiateViewController(withIdentifier: "RootTabBarViewController") as UIViewController
				childControllers.append(vc)
			}
		}
		columnWidth = (viewWidth + 2) / CGFloat(numColumns)
    	childVCSize = CGSize(width: columnWidth - 2, height: ourSize.height)
    	
    	while childControllers.count < numColumns {
			let vc = mainStoryboard.instantiateViewController(withIdentifier: "DailyNavController") as UIViewController
			childControllers.append(vc)
			if let krakenNavVC = vc as? KrakenNavController {
				krakenNavVC.columnIndex = childControllers.count - 1
			}
    	}
    	
    	for index in 0..<numColumns {
    		let child = childControllers[index]
    		if !view.subviews.contains(child.view) {
				addChild(child)
				child.view.frame = CGRect(x: CGFloat(index) * columnWidth, y: 0, width: childVCSize.width, height: childVCSize.height)
				view.addSubview(child.view)
				child.didMove(toParent: self)
				
				setOverrideTraitCollection(UITraitCollection(horizontalSizeClass: .compact), forChild: child)
			}
			else {
				child.view.frame = CGRect(x: CGFloat(index) * columnWidth, y: 0, width: childVCSize.width, height: childVCSize.height)
			}
		}
		for index in numColumns..<childControllers.count {
    		let child = childControllers[index]
			if view.subviews.contains(child.view) {
    			child.willMove(toParent: nil)
    			child.view.removeFromSuperview()
    			child.removeFromParent()
    		}
		}
    }
    
	@discardableResult func globalNavigateTo(packet: GlobalNavPacket) -> Bool {
		if let childVC = packet.column < childControllers.count ? childControllers[packet.column] : childControllers.last,
				let globalNav = childVC as? GlobalNavEnabled {
			if !globalNav.globalNavigateTo(packet: packet) {
				if packet.column == 0, let tabVC = childControllers[0] as? RootTabBarViewController, 
						let dailyNav = tabVC.viewControllers?[0] as? KrakenNavController {
					dailyNav.globalNavigateTo(packet: packet)		
				}
			}
		}
		return true
	}
	
	override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
		super.viewWillTransition(to: size, with: coordinator)
		determineChildLayout(for: size)
	}

	override func viewWillLayoutSubviews() {
		determineChildLayout(for: view.bounds.size)
	}
	
	func buildDeepSeaImage() {
		var deepSeaView: UIView & DeepSeaView
		if Bool.random() {
			deepSeaView = OctopusPictureView(frame: view.frame)
		}
		else {
			deepSeaView = SquidAnimationView(frame: view.frame)
		}
		view.addSubview(deepSeaView)
		view.sendSubviewToBack(deepSeaView)
		deepSeaView.buildDeepSeaImage()
		deepSeaView.alpha = 0.0
		self.deepSeaView = deepSeaView
	}
		
	func columnIndex(for vc: UIViewController) -> Int {
		if let column = childControllers.firstIndex(of: vc) {
			return column
		}
		if let nav = vc.navigationController as? KrakenNavController {
			return nav.columnIndex
		}
		else if let nav = vc.navigationController {
			if let column = childControllers.firstIndex(of: nav) {
				return column
			}
		}
		return 0
	}
}
