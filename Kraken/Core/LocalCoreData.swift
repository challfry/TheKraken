//
//  LocalCoreData.swift
//  Kraken
//
//  Created by Chall Fry on 4/6/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit
import CoreData

// This protocol exists to work around Self being available in protocols but not class definitions; see SE-0068.
// That is, we want a keypath rooted at Self, where Self can be a subclass of KrakenManagedObject. Protocol extensions can do this,
// but superclasses weirdly cannot.
protocol TestAndSettable : AnyObject {}
extension TestAndSettable where Self : KrakenManagedObject {
	@discardableResult func TestAndUpdate<ValueType: Equatable>(_ keypath: ReferenceWritableKeyPath<Self, ValueType>, _ newValue: ValueType) -> Bool {
		if self[keyPath: keypath] != newValue {
    		self[keyPath: keypath] = newValue
    		return true
    	}
    	
    	return false
	}
}

// A base class for our Core Data Managed Objects; contains utility functions
@objc(KrakenManagedObject) public class KrakenManagedObject: NSManagedObject, TestAndSettable {

	@objc dynamic override public func willTurnIntoFault() {
		super.willTurnIntoFault()
		ebn_handleCoreDataFault()
	}
	
	override public func awakeFromFetch() {
		super.awakeFromFetch()
		ebn_handleAwakeFromFetch()
	}

}

class LocalCoreData: NSObject {
	static let shared = LocalCoreData()
	
	// To use: throw LocalCoreData.Error(failureExplanation: "Failure parsing Forums response.", coreDataError: err)
	struct Error: Swift.Error {
		let failureExplanation: String 		// What were you trying to do when the error happened? 
		let coreDataError: NSError?			// The underlying Core Data error, if any
	}

	lazy var persistentContainer: NSPersistentContainer = {
		guard let modelURL = Bundle.main.url(forResource: "TwitarrModel", withExtension:"momd"),
				let model = NSManagedObjectModel(contentsOf: modelURL) else {
			fatalError("Can't load Core Data model file. That's bad.")
		}
		
		// Intent here is to set container name to parts of URL that uniquely identify the server, while allowing 
		// slightly different URLs that point to the same server instance to alias (e.g. HTTP vs. HTTPS).
		// This way, each different server you connect to gets its own cache.
		let serverURL = Settings.shared.baseURL
		let containerName = "TwitarrCoreData_\(serverURL.host ?? "")_\(serverURL.port ?? 80)_\(serverURL.path)"
		let container = NSPersistentContainer(name: containerName, managedObjectModel: model)
		container.loadPersistentStores(completionHandler: { (storeDescription, error) in
			if let error = error as NSError? {
				showDelayedTextAlert(title: "Core Data Storage Corrupt", message: """
				Something went wrong and we couldn't load our local database. To recover, we had to reset the database and try again. 
				
				The database is mostly a cache of server data we can re-fetch, but any changes not sent to the server have been lost.
				
				Error: \(error.localizedDescription)
				""")
				
				// Reset, and try opening it again. A second failure is fatal.
				for desc in container.persistentStoreDescriptions {
					do {
						if let storeURL = desc.url {
							try FileManager.default.removeItem(at: storeURL)
						}
					}
					catch {
						fatalError("Couldn't init CoreData, then couldn't reset CoreData stores. This is a fatal error. \(error)")
					}
				}
				container.loadPersistentStores(completionHandler: { (storeDescription, error) in
					if let error = error as NSError? {
						fatalError("Unresolved error \(error), \(error.userInfo)")
					}
					container.viewContext.automaticallyMergesChangesFromParent = true
				})
			}
			else {
				container.viewContext.automaticallyMergesChangesFromParent = true
			}
		})
		return container
	}()
	
	override init() {
		super.init()
		NotificationCenter.default.addObserver(self, selector: #selector(contextDidSaveNotificationHandler), 
				name: Notification.Name.NSManagedObjectContextObjectsDidChange, object: nil)
	}
	
	// This returns the single MOC for use by the UI in the main thread.
	lazy var mainThreadContext: NSManagedObjectContext = {
		return persistentContainer.viewContext
	}()
	
	// This creates a single MOC for use by network JSON parsers.
	lazy var networkOperationContext: NSManagedObjectContext = {
		return persistentContainer.newBackgroundContext()
	}()
	
	// Wraps some boilerplate when parsing server responses and adding the response contents to Core Data.
	// Runs the given block within the thread provided by the NetworkOperationContext, and inside a do...catch block.
	// While parsing you can push/pop operation failure strings to explaing what's being parsed; this can help
	// track down where we're throwing parse errors.
	//
	// Use is optional; roll your own for cases where you need to do something special, such as run code after 
	// a successful CD save.
	func performNetworkParsing(_ block: @escaping (NSManagedObjectContext) throws -> Void) {
		let context = networkOperationContext
		context.perform {
			do {
				try block(context)
				context.pushOpErrorExplanation("Failed to Save Network Core Data Context.")
				try context.save()
			}
			catch let error as LocalCoreData.Error {
				CoreDataLog.error(error.failureExplanation, ["error" : error])
			}
			catch {
				if let opStrings = context.userInfo["currentOpError"] as? [String] {
					var errString = "Core Data errors:\n"
					opStrings.forEach { errString.append( "\($0)\n") }
					CoreDataLog.error(errString, ["error" : error])
				}
				else {
					CoreDataLog.error("Unknown Error while processing a network packet.", ["error" : error])
				}
			}
			context.userInfo.removeAllObjects()
		}
	}

	// Wraps code that wants to change to Core Data, initiated by a user action (as opposed to a network load).
	// That is, use this for *changing* semantic state, no just loading and caching data from the server.
	// The wrapper checks for a logged-in user, and won't execute the change if nobody's logged in. If you
	// really need to make a change with nobody logged in just roll your own. 
	func performLocalCoreDataChange(_ block: @escaping (NSManagedObjectContext, KrakenUser) throws -> Void) {
		let context = networkOperationContext
		context.perform {
			do {
				guard let currentUser = CurrentUser.shared.getLoggedInUser(in: context) else { return }
				try block(context, currentUser)
				context.pushOpErrorExplanation("Failed to Save Core Data Context.")
				try context.save()
			}
			catch let error as LocalCoreData.Error {
				CoreDataLog.error(error.failureExplanation, ["error" : error])
			}
			catch {
				if let opStrings = context.userInfo["currentOpError"] as? [String] {
					var errString = "Core Data errors:\n"
					opStrings.forEach { errString.append( "\($0)\n") }
					CoreDataLog.error(errString, ["error" : error])
				}
				else {
					CoreDataLog.error("Unknown Error while processing a network packet.", ["error" : error])
				}
			}
			context.userInfo.removeAllObjects()
		}
	}
	
	// Updates the main context in response to data saves from the network context
	@objc func contextDidSaveNotificationHandler(notification: Notification) {
		if let notificationContext = notification.object as? NSManagedObjectContext, notificationContext === networkOperationContext {
			mainThreadContext.perform {
				self.mainThreadContext.mergeChanges(fromContextDidSave: notification)
			}
		}
	}

//	func saveContext () {
//		let context = persistentContainer.viewContext
//		if context.hasChanges {
//			do {
//				try context.save()
//			} catch {
//				let nserror = error as NSError
//				fatalError("Unresolved error \(nserror), \(nserror.userInfo)")
//			}
//		}
//	}
	
	// Deletes every object in the Core Data store. Should only be called at app launch, probably?
	func fullCoreDataReset() {
		do {
			for entity in persistentContainer.managedObjectModel.entities {
				if let entityName = entity.name {
					// create the delete request for the specified entity
					let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
					let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
					try persistentContainer.viewContext.execute(deleteRequest)
				}
			}
			
		} catch let error as NSError {
			CoreDataLog.error("Attempted a full reset, failed.", ["error" : error])
		}

	}

}

extension NSManagedObjectContext {

	// Sets a textual description of the current operation, used in the case where the current op fails and throws.
	// Set to a string such as "Failed to parse Forum threads and add to Core Data."
	func pushOpErrorExplanation(_ str: String) {
		if var opStack = userInfo["currentOpError"] as? Array<String> {
			opStack.append(str)
			userInfo["currentOpError"] = opStack
		} else {
			userInfo["currentOpError"] = [str]
		}
	}
	
	func popOpErrorExplanation() {
		if var opStack = userInfo["currentOpError"] as? Array<String> {
			userInfo["currentOpError"] = opStack.removeLast()
		}
	}
}
