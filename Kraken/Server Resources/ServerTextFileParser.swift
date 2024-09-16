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
	@objc dynamic var lastError: String?
	@objc dynamic var fileContents: NSAttributedString? 
	@objc dynamic var isFetchingData = false
	
	init(forPath path: String) {
		super.init()
		getServerTextFile(path: path)
	}
		
	func getServerTextFile(path: String) {
	
		guard let fn = path.split(separator: "/").last else {
			lastError = "Invalid path."
			return
		}
		let filename = String(fn)

		// 
		let request = NetworkGovernor.buildTwittarRequest(withPath: path, query: nil)
		isFetchingData = true
		NetworkGovernor.shared.queue(request) { (package: NetworkResponse) in
			if let error = package.getAnyError() {
				self.lastError = error.getErrorString()
				self.loadLocallySavedFile(named: filename)
			}
			else if let data = package.data {
				do {
					try self.parseFile(fileName: filename,  fileData: data)
					self.saveResponseFile(named: filename, withData: data)
				}
				catch {
					self.lastError = error.localizedDescription
					self.loadLocallySavedFile(named: filename)
				}
			} 
			self.isFetchingData = false
		}
	}
	
	// Takes the file data (from the server, CoreData, or the local fs) and fills in the fileContents attributed string.
	func parseFile(fileName: String, fileData: Data) throws {
		if fileName.hasSuffix("md"), let markdownText = String(data: fileData, encoding: .utf8) {
			let markdown = SwiftyMarkdown(string: markdownText)
			markdown.body.fontName = "Georgia"
			markdown.body.color = UIColor(named: "Kraken Label Text") ?? UIColor.black
			fileContents = markdown.attributedString()
		}
		else if fileName.hasSuffix("json") {
			let decoder = JSONDecoder()
			do {
				let response = try decoder.decode(TwitarrV2TextFileResponse.self, from: fileData)
				try self.parseJSONToString(from: response, cachedAtDate: nil) 
			}
			catch {
				print(error)
			}
		}
		else if fileName.hasSuffix("html") {
			
		}
		else {
			// Throw?
		}
	}
	
	// cachedAtDate is only for when we fail to get a server response, but have a possibly out-of-date version cached locally.
	func parseJSONToString(from response: TwitarrV2TextFileResponse, cachedAtDate: Date?) throws {
				
		let baseFont = UIFont(name:"Georgia", size: 17)
		let headerFont = UIFont(name:"Georgia-Bold", size: 17)

		let headerParaStyle = NSMutableParagraphStyle()
		headerParaStyle.headIndent = 0
		headerParaStyle.paragraphSpacing = 20
		let headerAttrs: [NSAttributedString.Key : Any] = [ .font : headerFont?.withSize(20) as Any, 
				.paragraphStyle : headerParaStyle, .foregroundColor : UIColor(named: "Kraken Label Text") as Any]

		let header2ParaStyle = NSMutableParagraphStyle()
		header2ParaStyle.headIndent = 0
		header2ParaStyle.paragraphSpacing = 15
		let header2Attrs: [NSAttributedString.Key : Any] = [ .font : headerFont?.withSize(17) as Any, 
				.paragraphStyle : header2ParaStyle, .foregroundColor : UIColor(named: "Kraken Label Text") as Any]
		
		let bodyParaStyle = NSMutableParagraphStyle()
		bodyParaStyle.headIndent = 0
		bodyParaStyle.defaultTabInterval = 28
		bodyParaStyle.paragraphSpacing = 28
		let bodyAttrs: [NSAttributedString.Key : Any] = [ .font : baseFont?.withSize(15) as Any, 
				.paragraphStyle : bodyParaStyle, .foregroundColor : UIColor(named: "Kraken Label Text") as Any ]

		let listParaStyle = NSMutableParagraphStyle()
		listParaStyle.headIndent = 28
		listParaStyle.defaultTabInterval = 28
		listParaStyle.paragraphSpacing = 28
		let listAttrs: [NSAttributedString.Key : Any] = [ .font : baseFont?.withSize(15) as Any,
				.paragraphStyle : listParaStyle, .foregroundColor : UIColor(named: "Kraken Label Text") as Any]
		
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

		for (sectionName, superSection) in response {
			if let header = superSection.header {
				let superSectionStr = NSAttributedString(string: header + "\n", attributes: headerAttrs)
				resultString.append(superSectionStr)
			}
			
			if let sections = superSection.sections {
				for section in sections {
					if let headerStr = section.header {
						let sectionStr = NSAttributedString(string: headerStr + "\n", attributes: header2Attrs)
						resultString.append(sectionStr)
					}
					
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
				CoreDataLog.error("Failed to save context for server file.", ["error" : error])
			}
		}
	}
	
	// When we get here, we've already set the error state with the network error. If this code succeeds it needs
	// to clear the error.
	func loadLocallySavedFile(named: String) {
	
		// If we have a cached copy, use that
		let context = LocalCoreData.shared.networkOperationContext
		context.perform {
			do {
				let request = LocalCoreData.shared.persistentContainer.managedObjectModel.fetchRequestFromTemplate(withName: "FindServerTextFile", 
						substitutionVariables: [ "fileName" : named ]) as! NSFetchRequest<ServerTextFile>
				let results = try request.execute()
				var fileData: Data?
				if let serverTextFile = results.first {
					fileData = serverTextFile.jsonData
				}
				else if let localTextFileURL = Bundle.main.url(forResource: named, withExtension: "") {
					fileData = try Data(contentsOf: localTextFileURL)
				}
				guard let fileData = fileData else {
					return
				}
				
				try self.parseFile(fileName: named, fileData: fileData)
				}
			catch {
				CoreDataLog.error("Failed to load server file from CD.", ["error" : error])
			}
		}
		
	}
	
}

typealias TwitarrV2TextFileResponse = [String : TwitarrV2TextFileSuperSection]

struct TwitarrV2TextFileSuperSection: Codable {
	var header: String?
	var sections: [TwitarrV2TextFileSection]?
}

struct TwitarrV2TextFileSection: Codable {
	let header: String?
	let paragraphs: [TwitarrV2TextFileParagraph]
}

struct TwitarrV2TextFileParagraph: Codable {
	let text: String?
	let list: [String]?
}
