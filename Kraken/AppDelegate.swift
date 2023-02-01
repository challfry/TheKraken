//
//  AppDelegate.swift
//  Kraken
//
//  Created by Chall Fry on 3/20/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit
import UserNotifications

var globalAppIsInBackground: Bool = true

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

	var window: UIWindow?
	var backgroundSessionCompletionHandler: (() -> Void)?
	
	func application(_ application: UIApplication, willFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
//		LocalCoreData.shared.fullCoreDataReset()

		// If it's after April 1, 2023, clear everything in Core Data
		let clearDayComponents = DateComponents(calendar: Calendar.current, timeZone: TimeZone(secondsFromGMT: 0 - 3600 * 5), 
				year: 2023, month: 4, day: 1)
		if let clearDate = Calendar.current.date(from: clearDayComponents),  Date() > clearDate {
			LocalCoreData.shared.fullCoreDataReset()
		}

		// Startup tasks. Hopefully they won't interact, but let's keep them in the same order just to be sure.
		CurrentUser.shared.setInitialLoginState()		// If someone was logged in when the app quit, keeps them logged in. 
		_ = PostOperationDataManager.shared				// Responsible for POSTs to the server. 
		RefreshTimers.appLaunched()
		UNUserNotificationCenter.current().delegate = Notifications.shared
		Notifications.appForegrounded()
		watchForStateChanges()
		
		let _ = PhonecallDataManager.shared
		
		return true
	}

	func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
		LocalPush.shared.appStarted()
		return true
	}

	// Sent when the application is about to move from active to inactive state. This can occur for certain types of 
	// temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application 
	// and it begins the transition to the background state.
	// Use this method to pause ongoing tasks, disable timers, and invalidate graphics rendering callbacks. 
	// Games should use this method to pause the game.
	func applicationWillResignActive(_ application: UIApplication) {
		RefreshTimers.appBackgrounded()
	}

	func applicationDidEnterBackground(_ application: UIApplication) {
		// Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
		// If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
		globalAppIsInBackground = true
	}

	func applicationWillEnterForeground(_ application: UIApplication) {
		// Called as part of the transition from the background to the active state; here you can undo many of the changes made on entering the background.
		globalAppIsInBackground = false
		RefreshTimers.appForegrounded(isLaunch: false)
		Notifications.appForegrounded()
	}

	func applicationDidBecomeActive(_ application: UIApplication) {
		// Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
		globalAppIsInBackground = false
	}

	func applicationWillTerminate(_ application: UIApplication) {
		// Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
	}

	func application(_ application: UIApplication, handleEventsForBackgroundURLSession 
  			identifier: String, completionHandler: @escaping () -> Void) {
		backgroundSessionCompletionHandler = completionHandler
	}
	
	func application(_ application: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:] ) -> Bool {
		let packet = GlobalNavPacket(from: nil, url: url.absoluteString)
		globalNavigateTo(packet: packet)
		return true
	}

// MARK: State Restoration
	// These 2 methods enable State Restoration in the app.
	func application(_ application: UIApplication, shouldSaveApplicationState coder: NSCoder) -> Bool {
		coder.encode(1, forKey: "KrakenArchiveVersion")
  		return true
	}

	func application(_ application: UIApplication, shouldRestoreSecureApplicationState coder: NSCoder) -> Bool {
		let archiveVersion = coder.decodeInt32(forKey: "KrakenArchiveVersion")
		if archiveVersion == 1 {
			AppLog.debug("Restoring Application State.")
			return true
		}
		return false
	}

}

// In iOS 13 you can override the system light/dark mode setting in your app's window. This code handles that override,
// watching the value in the Settings panel.
extension AppDelegate {
	func watchForStateChanges() {
		if #available(iOS 13.0, *) {
			Settings.shared.tell(self, when: "uiDisplayStyle") { observer, observed in 
				switch observed.uiDisplayStyle {
				case .systemDefault: observer.window?.overrideUserInterfaceStyle = UIUserInterfaceStyle.unspecified
				case .normalMode: observer.window?.overrideUserInterfaceStyle = UIUserInterfaceStyle.light
				case .darkMode: observer.window?.overrideUserInterfaceStyle = UIUserInterfaceStyle.dark
				case .deepSeaMode: observer.window?.overrideUserInterfaceStyle = UIUserInterfaceStyle.dark
				default: break					
				}
			}?.execute()
		}
	}
}

// MARK: - Global Navigation

// This protocol is sort of janky as it requires the caller to fill in the dict with all the steps you need to nav
// to the desired destination, but it works.
protocol GlobalNavEnabled {
	// Return true if you were able to nav at least partway toward the destination.
	@discardableResult func globalNavigateTo(packet: GlobalNavPacket) -> Bool
}

// This specifies how to get to a place in the app. Starting at the top of the app, each viewcontroller gets this navpacket,
// pulls out any relevant keys, shows the 'next' viewcontroller in the chain, and passes the packet on to the next VC.
// Still janky.
struct GlobalNavPacket {
	var column: Int								// Which column of the container view gets the nav
	var tab: RootTabBarViewController.Tab
	var segue: GlobalKnownSegue?
	var sender: Any?
	var arguments: [String : Any]
	
	init(from viewController: UIViewController, tab: RootTabBarViewController.Tab, arguments: [String : Any] = [:],
			segue: GlobalKnownSegue? = nil, sender: Any? = nil) {
		column = 0
		if let nav = viewController.navigationController as? KrakenNavController {
			column = nav.columnIndex
		}
		self.tab = tab
		self.segue = segue
		self.sender = sender
		self.arguments = arguments
	}
	
	init(column: Int, tab: RootTabBarViewController.Tab, arguments: [String : Any] = [:])
	{
		self.column = column
		self.tab = tab
		self.arguments = arguments
	}
	
	init(from viewController: UIViewController?, url urlString: String) {
		column = 0
		if let nav = viewController?.navigationController as? KrakenNavController {
			column = nav.columnIndex
		}
		arguments = ["url": urlString]
		if let url = URL(string: urlString), // let components = URLComponents(string: urlString),
				 url.pathComponents.count > 1, url.pathComponents[0] == "/" {
			switch url.pathComponents[1] {
				case "profile": 
					tab = .daily
					segue = .userProfile_Name
					sender = url.lastPathComponent
				case "tweets": 
					tab = .twitarr
					let filterPack = TwitarrFilterPack(urlString: urlString)
					sender = filterPack
					segue = filterPack.hasFilter() ? .tweetFilter : .twitarrRoot
				case "forums":
					tab = .forums
					if url.pathComponents.count == 3, let catID = UUID(uuidString: url.pathComponents[2]) {
						segue = .showForumCategory
						sender = catID
					}
					else {
						segue = .forumsRoot
					}
				case "forum": 
					tab = .forums
					if url.pathComponents.count == 3, let forumID = UUID(uuidString: url.pathComponents[2]) {
						segue = .showForumThread
						sender = forumID
					}
				case "seamail": 
					tab = .seamail
				case "fez":
					tab = .lfg
				case "events":
					tab = .events
				default: tab = .daily
			}
		}
		else {
			tab = .daily
		}
	}
}

extension AppDelegate: GlobalNavEnabled {
	@discardableResult func globalNavigateTo(packet: GlobalNavPacket) -> Bool {
    	if let containerVC = ContainerViewController.shared, containerVC.globalNavigateTo(packet: packet) {
    		return true
    	}
    	return true
    }
}
