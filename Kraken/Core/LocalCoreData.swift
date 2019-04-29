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
}

class LocalCoreData: NSObject {
	static let shared = LocalCoreData()

	lazy var persistentContainer: NSPersistentContainer = {
		let container = NSPersistentContainer(name: "TwitarrModel")
		container.loadPersistentStores(completionHandler: { (storeDescription, error) in
			if let error = error as NSError? {
				fatalError("Unresolved error \(error), \(error.userInfo)")
			}
			
			container.viewContext.automaticallyMergesChangesFromParent = true
		})
		return container
	}()
	
	// This returns the single MOC for use by the UI in the main thread.
	lazy var mainThreadContext: NSManagedObjectContext = {
		return persistentContainer.viewContext
	}()
	
	// This creates a single MOC for use by network JSON parsers.
	lazy var networkOperationContext: NSManagedObjectContext = {
		return persistentContainer.newBackgroundContext()
	}()
	
	func saveContext () {
		let context = persistentContainer.viewContext
		if context.hasChanges {
			do {
				try context.save()
			} catch {
				let nserror = error as NSError
				fatalError("Unresolved error \(nserror), \(nserror.userInfo)")
			}
		}
	}
	
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
			print(error)
		}

	}

}
