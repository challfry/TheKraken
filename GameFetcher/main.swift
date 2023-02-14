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
			print ("\(gameName)\t\(isExtendedSearch ? "FuzzySearch:" : "") No ID Found")
		}
		else if objectIDs.count == 1 {
			print ("\(gameName)\t\(objectIDs[0])\t\(isExtendedSearch ? "FuzzySearch:" : "")")
		}
		else {
			print ("\(gameName)\t\(objectIDs[0])\t\(isExtendedSearch ? "FuzzySearch:" : "") \(objectIDs.count) IDs Found")
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
	var isParsingSuggestedPlayers = false
	var currentSuggestedPlayers = 0
	var suggestedPlayersBestNumVotes = 0
	var bestSuggestedPlayers = 0
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
		if elementName == "poll" && attributeDict["name"] == "suggested_numplayers" {
			isParsingSuggestedPlayers = true
		}
		if isParsingSuggestedPlayers {
			switch elementName {
			case "results":	
				let numPlayersStr = attributeDict["numplayers"] ?? "0"
				let numPlayers = numPlayersStr == "6+" ? 6 : Int(numPlayersStr) ?? 0
				currentSuggestedPlayers = numPlayers
			case "result" where attributeDict["value"] == "Best":
				if let numVotes = Int(attributeDict["numvotes"] ?? "0"), numVotes > suggestedPlayersBestNumVotes {
					suggestedPlayersBestNumVotes = numVotes
					bestSuggestedPlayers = currentSuggestedPlayers
				}
			default: break 
			}
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
		else if isParsingSuggestedPlayers && elementName == "poll", bestSuggestedPlayers != 0 {
			gameObj.suggestedPlayers = bestSuggestedPlayers
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
		if elementName == "poll" { isParsingSuggestedPlayers = false }
		
	}
}

guard CommandLine.argc >= 2 else { exit(0) }
let fileUrl = URL(fileURLWithPath: CommandLine.arguments[1])
var fileContents = try? String(contentsOf: fileUrl)
if fileContents == nil {
	print ("Couldn't load file.")
	exit(0)
}

// Shortened contents for testing
if false {
	fileContents = """
	Blood Bowl: Team Manager - The Card Game	1
	"""

let xtra = """
	Elder Sign
	Eldritch Horror
	Epic Spell Wars
	Evolution
	Evolution: Climate
	Exoplanets
	Exploding Kittens
	Exploding Kittens NSFW
	Fake News
	"""
}

// HOW TO USE:
//	Use a spreadsheet to make a list of games with numCopies and donatedBy fields. JoCo releases a list like this every year.
//	Add in any notes, and manually fill in the expandsGaneNamed colum. Copy the 5-column list into a tab-delimited text file.
// 	Run GameFetcher on that text file. 
//
//	You'll need to run the script several times, adjusting game names each time, to find matches for as many game titles as possible.
// 
// Input file is "<Name>\t<NumCopies>\t<DonatedBy>\t<Notes>\t<ExpandsGameNamed>"

// Get the XML for each record, convert to JSON, store in gamesList array
let scanner = Scanner(string: fileContents!)
while !scanner.isAtEnd, let thisLine = scanner.scanUpToCharacters(from: CharacterSet.newlines) {
	let tabFields = thisLine.split(separator: "\t", maxSplits: 8, omittingEmptySubsequences: false)
	let thisGame = String(tabFields[0])
	var strippedName = thisGame.replacingOccurrences(of: " – ", with: " ").replacingOccurrences(of: " - ", with: " ")

	var numCopies = 1
	if tabFields.count >= 2 {
		numCopies = Int(tabFields[1]) ?? 1
	}
	
	var donatedBy: String? = nil
	if tabFields.count >= 3, !tabFields[2].isEmpty {
		donatedBy = String(tabFields[2])
	}
	
	var notes: String? = nil
	if tabFields.count >= 4, !tabFields[3].isEmpty {
		notes = String(tabFields[3])
	}
	
	var expands: String? = nil
	if tabFields.count >= 5, !tabFields[4].isEmpty {
		expands = String(tabFields[4])
	}
		
	var gameObj = getGame(named: strippedName)
//	var gameObj = getGameInfo(from: "230305", gameName: String(tabFields[0]))
	
	gameObj.gameName = thisGame
	gameObj.numCopies = numCopies
	gameObj.donatedBy = donatedBy
	gameObj.notes = notes
	gameObj.expands = expands
	
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
