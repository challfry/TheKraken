//
//  main.swift
//  GameFetcher
//
//  Created by Chall Fry on 1/30/20.
//  Copyright © 2020 Chall Fry. All rights reserved.
//

import Cocoa
import Foundation
import Compression

// https://boardgamegeek.com/wiki/page/BGG_XML_API#
// Basically, make calls to http://www.boardgamegeek.com/xmlapi/search?search=Crossbows%20and%20Catapults sub in game names, get a number back
// then: https://www.boardgamegeek.com/xmlapi/boardgame/2860?stats=1 


let queryBaseURL = "http://www.boardgamegeek.com/xmlapi"
var gamesList: [JsonGamesListGame] = []

func getGame(named: String) -> JsonGamesListGame {
	var resultGame = JsonGamesListGame(gameName: named)
	var queryItems = [URLQueryItem(name:"search", value: named), URLQueryItem(name:"exact", value: "1")]
	guard var components = URLComponents(string: "\(queryBaseURL)/search") else { return resultGame }
	components.queryItems = queryItems
	if let url = components.url {
		var xmlResponse = try! String(contentsOf: url)
		var del = ParserDelegate(xml: xmlResponse, for: named, isExtended: false)
		if del.objectIDs.count > 0 {
			resultGame = getGameInfo(from: del)
		}
		else {
			// Fuzzy search. Very vew games end with " Game" and if they do, we can still lop it off
			var fuzzyNamed = named
			if fuzzyNamed.hasSuffix(" Game") {
				fuzzyNamed.removeLast(5)
			}
		
			queryItems = [URLQueryItem(name:"search", value: fuzzyNamed)]
			components.queryItems = queryItems
			if let url = components.url {
				Thread.sleep(forTimeInterval: 2.0)
				xmlResponse = try! String(contentsOf: url)
				del = ParserDelegate(xml: xmlResponse, for: named, isExtended: true)
				resultGame = getGameInfo(from: del)
			}
		}
	}
	
	return resultGame
}
		
func getGameInfo(from del: ParserDelegate) -> JsonGamesListGame {	
	if del.objectIDs.count > 0 {
		return getGameInfo(from: del.objectIDs[0], gameName: del.gameName)
	}
	else {
		// Couldn't find game in BGG.
		return JsonGamesListGame(gameName: del.gameName)
	}
}

func getGameInfo(from objectID: String, gameName: String)	-> JsonGamesListGame {
	let queryItems = [URLQueryItem(name:"stats", value: "1")]
	var resultGame: JsonGamesListGame
	if var components = URLComponents(string: "\(queryBaseURL)/boardgame/\(objectID)") {
		components.queryItems = queryItems
		if let bgURL = components.url {
			Thread.sleep(forTimeInterval: 2.0)
			let xmlResponse = try! String(contentsOf: bgURL)
			let boardGameDel = BoardGameParserDelegate(gameName, xml: xmlResponse)
			resultGame = boardGameDel.gameObj
		}
		else {
			resultGame = JsonGamesListGame(gameName: gameName)
		}
	}
	else {
		// Couldn't find game in BGG.
		resultGame = JsonGamesListGame(gameName: gameName)
	}
	return resultGame
}

// Parses "/search" response
class ParserDelegate: NSObject, XMLParserDelegate {
	var gameName = ""
	var objectIDs: [String] = []
	var isExtendedSearch = false
	
	init(xml: String, for game: String, isExtended: Bool) {
		gameName = game
		isExtendedSearch = isExtended
		super.init()
		let xmlData = xml.data(using: .utf8)!
		let parser = XMLParser(data: xmlData)
		parser.delegate = self
		parser.parse()
	}

	func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String]) {
		if elementName == "boardgame" {
			if let id = attributeDict["objectid"] {
				objectIDs.append(id)
			}
		}
	}
	
	func parserDidEndDocument(_ parser: XMLParser) {
		if objectIDs.count == 0 {
			print ("\(gameName)\t \(isExtendedSearch ? "FuzzySearch:" : "") No ID Found")
		}
		else if objectIDs.count == 1 {
			print ("\(gameName)\t\(objectIDs[0]) \(isExtendedSearch ? "FuzzySearch:" : "")")
		}
		else {
			print ("\(gameName)\t\(objectIDs[0]) -- \(isExtendedSearch ? "FuzzySearch:" : "") \(objectIDs.count) IDs Found")
		}
	}
}

// Parses "/boardgame/<boardgameID>" response
class BoardGameParserDelegate: NSObject, XMLParserDelegate {
	var gameName = ""
	var objectIDs: [String] = []
	var gameObj: JsonGamesListGame
	
	init(_ gameNamed: String, xml: String) {
		gameName = gameNamed
		gameObj = JsonGamesListGame(gameName: gameNamed)
		super.init()

		let xmlData = xml.data(using: .utf8)!
		let parser = XMLParser(data: xmlData)
		parser.delegate = self
		parser.parse()
	}

	var isParsingRatings = false
	var isParsingPrimaryName = false
	func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String]) {
		if elementName == "ratings" { isParsingRatings = true }
		if elementName == "name" {
			if attributeDict["primary"] == "true" {
				isParsingPrimaryName = true
			}
		}
		if ["name", "description", "yearpublished"].contains(elementName) {
			tempChars = ""
		}
	}
	
	func parserDidEndDocument(_ parser: XMLParser) {
	}
	
	var tempChars: String = ""
	var numberConversionChars: String = ""
	func parser(_ parser: XMLParser, foundCharacters string: String) {
		tempChars.append(string)
		numberConversionChars = string
	}
	
	func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
		if isParsingPrimaryName	 {
			gameObj.bggGameName = tempChars
		}
		else if isParsingRatings {
			switch elementName {
			case "usersrated": gameObj.numRatings = Int(numberConversionChars)
			case "average": gameObj.avgRating = Float(numberConversionChars)
			case "averageweight": gameObj.complexity = Float(numberConversionChars)
			default: break
			}
		}
		else {
			switch elementName {
			case "yearpublished": gameObj.yearPublished	= tempChars
			case "minplayers": gameObj.minPlayers = Int(numberConversionChars)
			case "maxplayers": gameObj.maxPlayers = Int(numberConversionChars)
			case "minplaytime": gameObj.minPlayingTime = Int(numberConversionChars)
			case "maxplaytime": gameObj.maxPlayingTime = Int(numberConversionChars)
			case "playingtime": gameObj.avgPlayingTime = Int(numberConversionChars)
			case "age": gameObj.minAge = Int(numberConversionChars)
			case "description": gameObj.gameDescription = tempChars
			default: break
			}
		}
		
		if elementName == "ratings" { isParsingRatings = false }
		if elementName == "name" { isParsingPrimaryName = false }
		
	}
}

guard CommandLine.argc >= 2 else { exit(0) }
let fileUrl = URL(fileURLWithPath: CommandLine.arguments[1])
guard var fileContents = try? String(contentsOf: fileUrl) else { 
	print ("Couldn't load file.")
	exit(0)
}

// Shortened contents for testing
if false {
	fileContents = """
	Elder Sign	2				
	Eldritch Horror	2				
	Epic Spell Wars	1				
	Evolution	1				
	Evolution: Climate	1				
	Exoplanets	2				
	Exploding Kittens	3				
	Exploding Kittens NSFW	3				
	Fake News	1				
	"""
}

// Get the XML for each record, convert to JSON, store in gamesList array
let scanner = Scanner(string: fileContents)
while !scanner.isAtEnd, let nextLine = scanner.scanUpToCharacters(from: CharacterSet.newlines) {
	let tabFields = nextLine.split(separator: "\t", maxSplits: 8, omittingEmptySubsequences: false)
	var gameObj = getGame(named: String(tabFields[0]))
//	var gameObj = getGameInfo(from: "230305", gameName: String(tabFields[0]))
	
	gameObj.numCopies = Int(String(tabFields[1])) ?? 1
	gameObj.donatedBy = tabFields[2].isEmpty ? nil : String(tabFields[2])
	gameObj.notes = tabFields[3].isEmpty ? nil : String(tabFields[3])
	gameObj.expands = tabFields[4].isEmpty ? nil : String(tabFields[4])
	
	gamesList.append(gameObj)
	Thread.sleep(forTimeInterval: 2.0)
}

//let outputFileData = try JSONEncoder().encode(gamesList)
//print(String(data: outputFileData, encoding: .utf8)!)


do {
	// Save JSON to file
	let outputFileData = try JSONEncoder().encode(gamesList)
	let outputFileUrl = URL(fileURLWithPath: "/Users/cfry/Documents/GamesListGames.json")
	try outputFileData.write(to: outputFileUrl, options: [])
	
	guard let outputFileData = try? Data(contentsOf: outputFileUrl) else { 
		print ("Couldn't load file.")
		exit(0)
	}

	// Compress the data into .lzfse, save again
	let sourceBufferMutable = UnsafeMutablePointer<UInt8>.allocate(capacity: outputFileData.count)
	outputFileData.copyBytes(to: sourceBufferMutable, count: outputFileData.count)
	let sourceBuffer = UnsafePointer(sourceBufferMutable)
	let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: outputFileData.count)
	let compressedSize = compression_encode_buffer(destinationBuffer, outputFileData.count,
			sourceBuffer, outputFileData.count, nil, COMPRESSION_LZFSE)
	let writeUrl = outputFileUrl.deletingPathExtension().appendingPathExtension("lzfse")
	let compressedData = Data(bytes: destinationBuffer, count: compressedSize)
	try compressedData.write(to: writeUrl)
	print (writeUrl)
}
catch {	
	print(error)
}
