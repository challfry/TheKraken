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
		let container = NSPersistentContainer(name: "TwitarrModel", managedObjectModel: model)
		container.loadPersistentStores(completionHandler: { (storeDescription, error) in
			if let error = error as NSError? {
				fatalError("Unresolved error \(error), \(error.userInfo)")
			}
			
			container.viewContext.automaticallyMergesChangesFromParent = true
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
