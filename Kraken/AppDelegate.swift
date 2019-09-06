//
//  AppDelegate.swift
//  Kraken
//
//  Created by Chall Fry on 3/20/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit
import UserNotifications

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

	var window: UIWindow?
	var backgroundSessionCompletionHandler: (() -> Void)?
	
	func application(_ application: UIApplication, willFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
//		LocalCoreData.shared.fullCoreDataReset()

		// Startup tasks. Hopefully they won't interact, but let's keep them in the same order just to be sure.
		CurrentUser.shared.setInitialLoginState()		// If someone was logged in when the app quit, keeps them logged in. 
		_ = PostOperationDataManager.shared				// Responsible for POSTs to the server. 
		RefreshTimers.appForegrounded()
		UNUserNotificationCenter.current().delegate = Notifications.shared
		Notifications.appForegrounded()
		return true
	}

	func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
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
	}

	func applicationWillEnterForeground(_ application: UIApplication) {
		// Called as part of the transition from the background to the active state; here you can undo many of the changes made on entering the background.
		RefreshTimers.appForegrounded()
		Notifications.appForegrounded()
	}

	func applicationDidBecomeActive(_ application: UIApplication) {
		// Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.

	}

	func applicationWillTerminate(_ application: UIApplication) {
		// Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
	}

	func application(_ application: UIApplication, handleEventsForBackgroundURLSession 
  			identifier: String, completionHandler: @escaping () -> Void) {
		backgroundSessionCompletionHandler = completionHandler
	}
	
// MARK: State Restoration
	// These 2 methods enable State Restoration in the app.
	func application(_ application: UIApplication, shouldSaveApplicationState coder: NSCoder) -> Bool {
  		return true
	}

	func application(_ application: UIApplication, shouldRestoreApplicationState coder: NSCoder) -> Bool {
		return true
	}

}

