//
//  ServerTextFileParser.swift
//  Kraken
//
//  Created by Chall Fry on 5/3/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit
import CoreData

// Note: We save the raw JSON data instead of the parsed NSAttributedString because then we can modify the string attrs
// when there's no network.
@objc(ServerTextFile) public class ServerTextFile: KrakenManagedObject {
	@NSManaged public var fileName: String
	@NSManaged public var jsonData: Data
	@NSManaged public var fetchDate: Date

	func buildFromV2Data(context: NSManagedObjectContext, fileName: String, fileData: Data)
	{
		// In theory we could use test and set to reduce cases where we force CoreData saves when nothing actually changed.
		// However, we'll always increment fetchDate.
		self.fileName = fileName
		jsonData = fileData
		fetchDate = Date()
	}
}

class ServerTextFileParser: NSObject {

	// The last error we got from the server. Cleared when we start a new call.
	@objc dynamic var lastError: ServerError?
	@objc dynamic var fileContents: NSAttributedString? 
	@objc dynamic var isFetchingData = false
	
	init(forFile named: String) {
		super.init()
		getServerTextFile(named: named)
	}
		
	func getServerTextFile(named: String) {

		//
		let request = NetworkGovernor.buildTwittarV2Request(withPath:"/api/v2/text/\(named)", query: nil)
		isFetchingData = true
		NetworkGovernor.shared.queue(request) { (data: Data?, response: URLResponse?) in
			if let error = NetworkGovernor.shared.parseServerError(data: data, response: response) {
				self.lastError = error
				self.loadLocallySavedFile(named: named)
			}
			else if let data = data {
				do {
					let decoder = JSONDecoder()
					let response = try decoder.decode(TwitarrV2TextFileResponse.self, from: data)
					self.parseJSONToString(from: response, cachedAtDate: nil)
					self.saveResponseFile(named: named, withData: data)
				}
				catch {
					self.lastError = ServerError()
					self.loadLocallySavedFile(named: named)
				}
			} 
			self.isFetchingData = false
		}
	}
	
	// cachedAtDate is only for when we fail to get a server response, but have a possibly out-of-date version cached locally.
	func parseJSONToString(from response: TwitarrV2TextFileResponse, cachedAtDate: Date?) {
		guard response.count == 1, let sectionDict = response.first?.value, 
				let sections: [TwitarrV2TextFileSection] = sectionDict["sections"] else { return }
				
		let baseFont = UIFont(name:"Georgia", size: 17)
		let headerFont = UIFont(name:"Georgia-Bold", size: 17)

		let headerParaStyle = NSMutableParagraphStyle()
		headerParaStyle.headIndent = 0
		headerParaStyle.paragraphSpacing = 20
		let headerAttrs: [NSAttributedString.Key : Any] = [ .font : headerFont?.withSize(20) as Any, .paragraphStyle : headerParaStyle]
		
		let bodyParaStyle = NSMutableParagraphStyle()
		bodyParaStyle.headIndent = 0
		bodyParaStyle.defaultTabInterval = 28
		bodyParaStyle.paragraphSpacing = 28
		let bodyAttrs: [NSAttributedString.Key : Any] = [ .font : baseFont?.withSize(15) as Any, .paragraphStyle : bodyParaStyle ]

		let listParaStyle = NSMutableParagraphStyle()
		listParaStyle.headIndent = 28
		listParaStyle.defaultTabInterval = 28
		listParaStyle.paragraphSpacing = 28
		let listAttrs: [NSAttributedString.Key : Any] = [ .font : baseFont?.withSize(15) as Any, .paragraphStyle : listParaStyle ]
		
		let resultString = NSMutableAttributedString()

		// Prepend the cachedAtDate warning, if we need to
		if let date = cachedAtDate {
			let dateFormatter = DateFormatter()
			dateFormatter.dateStyle = .medium
			dateFormatter.timeStyle = .medium
			dateFormatter.locale = Locale(identifier: "en_US")
			let dateString = dateFormatter.string(from: date)

			let warningAttrs: [NSAttributedString.Key : Any] = [ .font : baseFont?.withSize(17) as Any, 
					.paragraphStyle : bodyParaStyle, .foregroundColor : UIColor.red ]
			let warningText = NSAttributedString(string: "Showing locally cached file, downloaded \(dateString).\n",
					attributes: warningAttrs)
			resultString.append(warningText)
		}

		for section in sections {
			let sectionStr = NSAttributedString(string: section.header + "\n", attributes: headerAttrs)
			resultString.append(sectionStr)
			
			for paragraph in section.paragraphs {
				if let text = paragraph.text {
					let paragraphText = NSAttributedString(string: text + "\n", attributes: bodyAttrs)
					resultString.append(paragraphText)
				}
				paragraph.list?.forEach { text in
					let paragraphText = NSAttributedString(string: "•\t\(text)\n", attributes: listAttrs)
					resultString.append(paragraphText)
				}
			}
		}
		
		fileContents = resultString
	}
	
	func saveResponseFile(named: String, withData: Data) {
		let context = LocalCoreData.shared.networkOperationContext
		context.perform {
			do {
				let request = LocalCoreData.shared.persistentContainer.managedObjectModel.fetchRequestFromTemplate(withName: "FindServerTextFile", 
						substitutionVariables: [ "fileName" : named ]) as! NSFetchRequest<ServerTextFile>
				let results = try request.execute()
				let serverFile = results.first ?? ServerTextFile(context: context)
				serverFile.buildFromV2Data(context: context, fileName: named, fileData: withData)
				try context.save()
			}
			catch {
				print(error)
			}
		}
	}
	
	func loadLocallySavedFile(named: String) {
		let context = LocalCoreData.shared.networkOperationContext
		context.perform {
			do {
				let request = LocalCoreData.shared.persistentContainer.managedObjectModel.fetchRequestFromTemplate(withName: "FindServerTextFile", 
						substitutionVariables: [ "fileName" : named ]) as! NSFetchRequest<ServerTextFile>
				let results = try request.execute()
				if let serverTextFile = results.first {
					let decoder = JSONDecoder()
					let response = try decoder.decode(TwitarrV2TextFileResponse.self, from: serverTextFile.jsonData)
					self.parseJSONToString(from: response, cachedAtDate: serverTextFile.fetchDate)
				}
			}
			catch {
				print(error)
			}
		}
	}
	
}

typealias TwitarrV2TextFileResponse = [String : [ String : [TwitarrV2TextFileSection]]]

struct TwitarrV2TextFileSection: Codable {
	let header: String
	let paragraphs: [TwitarrV2TextFileParagraph]
}

struct TwitarrV2TextFileParagraph: Codable {
	let text: String?
	let list: [String]?
}
