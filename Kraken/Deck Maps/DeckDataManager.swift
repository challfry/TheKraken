//
//  DeckDataManager.swift
//  Kraken
//
//  Created by Chall Fry on 11/2/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit
import PDFKit


/// Okay. Why does this exist? It's here so that there's a globally-accessible place to check whether a string that probably refers to a place on-ship
/// can be resolved to a place we can point to on the deck maps.
class DeckDataManager: NSObject {
	static let shared = DeckDataManager()

	struct RoomLocation {
		var name: String				// The colloquial name for the room. User searches match against this.
										// MAY match the actual room name. 
		var alternateNames: [String]?	// Names that are CLOSE matches for the above name. Also matched in searches.
										// 1. If a user searches for a name in this list, they shouldn't be suprised to 
										//	  see the colloquial name in results instead.
										// 2. We don't want users to see 2 results for the same room.
		var deck: Int
		var isPortSide: Bool
		var location: PDFSelection 		// Selection.string MAY be the full room name. WILL be at least a substring.
		var isFullDeck = false			// TRUE iff this 'room' refers to the entire deck
		
		// Used to initialize named rooms
		init(_ roomName: String, _ deck: Int, in doc: PDFDocument, searchString: String? = nil, altNames: [String]? = nil) {
			name = roomName
			alternateNames = altNames
			let searchStr = searchString ?? roomName			
			let selections = doc.findString(searchStr, withOptions: .caseInsensitive)
			for sel in selections {
				if sel.pages.count > 1 {
					// log it
					continue
				}
				if let firstPage = sel.pages.first {
					let pageIndex = doc.index(for: firstPage)
					if deck == -1 || deck == pageIndex + 1 {
						self.deck = pageIndex +  1
						location = sel
						let selBounds = sel.bounds(for: firstPage)
						let pageBounds = firstPage.bounds(for: .cropBox)
						isPortSide = selBounds.midX < pageBounds.midX
						return
					}
				}
			}
			
			self.deck = 1
			location = PDFSelection(document: doc)
			isPortSide = true
		}
		
		// Used to create a RoomLocation from a selection in the doc. Hence, used to create RoomLocations for 
		// numbered suites.
		init(_ roomName: String, from sel: PDFSelection) {
			name = roomName
			location = sel
			deck = 1
			isPortSide = true

			if let firstPage = sel.pages.first, let doc = firstPage.document {
				deck = doc.index(for: firstPage) + 1
				let selBounds = sel.bounds(for: firstPage)
				let pageBounds = firstPage.bounds(for: .cropBox)
				isPortSide = selBounds.midX < pageBounds.midX
			}
		}
		
		//
		init(deckName: String, _ deck: Int, in doc: PDFDocument) {
			name = deckName
			self.deck = deck
			isFullDeck = true
			isPortSide = true

			location = PDFSelection(document: doc)
			if let page = doc.page(at: deck - 1) {
				let bounds = page.bounds(for: .cropBox)
				if let sel = page.selection(for: bounds) {
					location = sel
				}
			}
		}
		
		// TRUE if the room name or its aliases contain the given string
		func matchAgainst(_ str: String) -> Bool {
			if let _ = name.range(of: str, options: .caseInsensitive) {
				return true
			}
			var returnValue = false
			alternateNames?.forEach { 
				if let _ = $0.range(of: str, options: .caseInsensitive) {
					returnValue = true
				}
			}
			
			return returnValue
		}
	}
	
	/// The PDFDoc of all the decks on the ship. This source file is pretty closely bonded with the exact contents of this PDF.
	var document: PDFDocument?
	
	/// The Data Manager maintains a single annotation, which is a red arrow that points at a room on the ship. Multiple VCs use this 
	/// data manager, each of them can save an annotation that they want to be visible when they're active.
	var roomPointer: PDFAnnotation?

	var namedRooms: [RoomLocation] = []		

	override init() {
		super.init()
		if let docURL = Bundle.main.url(forResource: "Decks", withExtension: "pdf"),
				let pdfDoc = PDFDocument(url: docURL) {
			document = pdfDoc
			
			// 1
			namedRooms.append(RoomLocation("The Mainstage", 1, in: pdfDoc, altNames: ["The Main Stage"]))
			namedRooms.append(RoomLocation("Atrium Bar", 1, in: pdfDoc))
			namedRooms.append(RoomLocation("Atrium", 1, in: pdfDoc))
			namedRooms.append(RoomLocation("Guest Services", 1, in: pdfDoc, searchString: "Guest"))
			
			// 2
			namedRooms.append(RoomLocation("The Mainstage", 2, in: pdfDoc, altNames: ["The Main Stage"]))
			namedRooms.append(RoomLocation("Casino", 2, in: pdfDoc))
			namedRooms.append(RoomLocation("Billboard Onboard", 2, in: pdfDoc))
			namedRooms.append(RoomLocation("Gallery Bar", 2, in: pdfDoc))
			namedRooms.append(RoomLocation("B.B. King’s Blues Club", 2, in: pdfDoc, altNames: ["B.B. King’s", "B.B. King's"]))
			namedRooms.append(RoomLocation("America’s Test Kitchen", 2, in: pdfDoc))
			namedRooms.append(RoomLocation("Pinnacle Grill", 2, in: pdfDoc))
			namedRooms.append(RoomLocation("Pinnacle Bar", 2, in: pdfDoc))
			namedRooms.append(RoomLocation("Art Gallery", 2, in: pdfDoc))
			namedRooms.append(RoomLocation("Lincoln Center Stage", 2, in: pdfDoc))
			namedRooms.append(RoomLocation("Explorer’s Lounge", 2, in: pdfDoc))
			namedRooms.append(RoomLocation("Digital Workshop", 2, in: pdfDoc, searchString: "DIGITAL E EWORKSHOP"))
			namedRooms.append(RoomLocation("Crafting Room", 2, in: pdfDoc, searchString: "DIGITAL E EWORKSHOP"))
			namedRooms.append(RoomLocation("The Dining Room", 2, in: pdfDoc))
			
			// 3
			namedRooms.append(RoomLocation("The Mainstage", 3, in: pdfDoc, altNames: ["The Main Stage"]))
			namedRooms.append(RoomLocation("Hudson", 3, in: pdfDoc))
			namedRooms.append(RoomLocation("Tasman", 3, in: pdfDoc))
			namedRooms.append(RoomLocation("Half Moon", 3, in: pdfDoc))
			namedRooms.append(RoomLocation("Stuyvesant", 3, in: pdfDoc))
			namedRooms.append(RoomLocation("Merabella Luxury Collection", 3, in: pdfDoc, searchString: "MERABELLA"))
			namedRooms.append(RoomLocation("Ocean Bar", 3, in: pdfDoc))
			namedRooms.append(RoomLocation("Photo Gallery", 3, in: pdfDoc))
			namedRooms.append(RoomLocation("The Dining Room", 3, in: pdfDoc))
			
			// 7
			namedRooms.append(RoomLocation("Neptune Lounge", 7, in: pdfDoc))
			
			// 8
			namedRooms.append(RoomLocation("Bridge", 8, in: pdfDoc))
			
			// 9
			namedRooms.append(RoomLocation("Fitness Center", 9, in: pdfDoc))
			namedRooms.append(RoomLocation("Greenhouse Spa & Salon", 9, in: pdfDoc, searchString: "GREENHOUSE"))
			namedRooms.append(RoomLocation("Hydro Pool", 9, in: pdfDoc))
			namedRooms.append(RoomLocation("Lido Pool", 9, in: pdfDoc, altNames: ["Lido Pool Area"]))
			namedRooms.append(RoomLocation("Lido Bar", 9, in: pdfDoc))
			namedRooms.append(RoomLocation("Dive-In", 9, in: pdfDoc))
			namedRooms.append(RoomLocation("Canaletto", 9, in: pdfDoc))
			namedRooms.append(RoomLocation("Lido Market", 9, in: pdfDoc))
			namedRooms.append(RoomLocation("Sea View Bar", 9, in: pdfDoc))
			namedRooms.append(RoomLocation("New York Pizza", 9, in: pdfDoc))
			namedRooms.append(RoomLocation("Sea View Pool", 9, in: pdfDoc))
			
			// 10
			namedRooms.append(RoomLocation("Club HAL", 10, in: pdfDoc))
			namedRooms.append(RoomLocation("The Loft", 10, in: pdfDoc, searchString: "Loft"))

			// 11
	//		namedRooms.append(RoomLocation("Explorations Central & Café/Crow’s Nest", 11, in: pdfDoc))
			namedRooms.append(RoomLocation("Explorations Central", 11, in: pdfDoc, searchString: "Explorations Central & Café/Crow’s Nest"))
			namedRooms.append(RoomLocation("Café", 11, in: pdfDoc, searchString: "Explorations Central & Café/Crow’s Nest"))
			namedRooms.append(RoomLocation("Crow’s Nest", 11, in: pdfDoc, searchString: "Explorations Central & Café/Crow’s Nest"))
			namedRooms.append(RoomLocation("Ten Forward", 11, in: pdfDoc, searchString: "Explorations Central & Café/Crow’s Nest"))
			namedRooms.append(RoomLocation("The Retreat", 11, in: pdfDoc))
			namedRooms.append(RoomLocation("Tamarind Bar", 11, in: pdfDoc))
			namedRooms.append(RoomLocation("Tamarind", 11, in: pdfDoc))
			namedRooms.append(RoomLocation("Sports Courts", 11, in: pdfDoc))
			
			// Deck Names
			namedRooms.append(RoomLocation(deckName:"Main Deck", 1, in: pdfDoc))
			namedRooms.append(RoomLocation(deckName:"Lower Promenade Deck", 2, in: pdfDoc))
			namedRooms.append(RoomLocation(deckName:"Promenade Deck", 3, in: pdfDoc))
			namedRooms.append(RoomLocation(deckName:"Upper Promenade Deck", 4, in: pdfDoc))
			namedRooms.append(RoomLocation(deckName:"Verandah Deck", 5, in: pdfDoc))
			namedRooms.append(RoomLocation(deckName:"Upper Verandah Deck", 6, in: pdfDoc))
			namedRooms.append(RoomLocation(deckName:"Rotterdam Deck", 7, in: pdfDoc))
			namedRooms.append(RoomLocation(deckName:"Navigation Deck", 8, in: pdfDoc))
			namedRooms.append(RoomLocation(deckName:"Lido Deck", 9, in: pdfDoc))
			namedRooms.append(RoomLocation(deckName:"Panorama Deck", 10, in: pdfDoc))
			namedRooms.append(RoomLocation(deckName:"Observation Deck", 11, in: pdfDoc))
		}
	}
	
	// TRUE if the we can show where the given room is on the ship. That is, the string roughly resolves to 
	// exactly one named ship room or suite.
	func isValidRoom(name: String) -> Bool {
		return findRoom(named: name) != nil
	}
	
	// For this fn, the given name is the *full* name of a room, and we expect to find and return exactly one
	// result. We do some massaging to get this to happen, as with "Atrium" and "Atrium Bar"
	func findRoom(named nameToMatch: String) -> RoomLocation? {
		guard let pdfDoc = document else { return nil }
		var firstPhrase = nameToMatch
		var expectedDeck: Int?

		// Events often have a location of the form: "Stuyvesant Room, Deck 3, Forward"
		// We want to isolate just the room name, but without the word "Room"
		let phrases = nameToMatch.split(separator: ",")
		if let phrase = phrases.first {
			firstPhrase = String(phrase)
		}
		if firstPhrase.hasSuffix(" Room") {
			firstPhrase.removeLast(5)
		}
		
		// Parse out the deck the room is on. Only works if the string is of the form "<Room Name>, Deck <#>"
		if phrases.count > 1 {
			let deckScanner = Scanner(string: String(phrases[1]))
			deckScanner.KscanString("Deck")
			expectedDeck = deckScanner.KscanInt()
		}
			
		
		// Special Cases. In these cases, there is such variety in Event Location names, we're just looking for specific
		// substrings.
		if firstPhrase.contains("Dining") {
			firstPhrase = "The Dining Room"
		}
		if firstPhrase.contains("Ten Forward") {
			firstPhrase = "Ten Forward"
		}
	
		// Is this a named room? Named rooms don't have digits, so a match here implies alpha entry.
		let matchingRooms = namedRooms.filter { $0.matchAgainst(firstPhrase) }
		if matchingRooms.count > 0 {
			if let expectedDeck = expectedDeck, let roomOnFloor = matchingRooms.first(where: { $0.deck == expectedDeck }) {
				return roomOnFloor
			}
			else {
				return matchingRooms.first
			}
		}
		for room in namedRooms {
			if room.matchAgainst(firstPhrase) {
				return room
			}
		}
		
		// If we're matching a room number, that number must be the entire number for the room. But, some valid room
		// numbers contain other valid room numbers as substrings.
		let scanner = Scanner(string: firstPhrase)
		scanner.KscanUpToCharactersFrom(CharacterSet.decimalDigits)
		if let numberString = scanner.KscanCharactersFrom(CharacterSet.decimalDigits) {
			if numberString.count == 4 || (numberString.count == 5 && numberString.starts(with: "1")) {
				let selections = pdfDoc.findString(String(numberString), withOptions: .caseInsensitive)
				if let sel = selections.first, let firstPage = sel.pages.first {
					let pageIndex = pdfDoc.index(for: firstPage)
								
					// Validate that the room is on the page that matches its floor number. Oddly, the PDF
					// has a bunch of room-strings that fail this test.
					if numberString.hasPrefix("\(pageIndex + 1)") {
						var room = RoomLocation("Suite \(numberString)", from: sel)
						room.location = sel
						return room
					}
				}
			}
		}
		
		return nil
	}

	let maxMatchingRooms = 12
	func findRooms(matching nameToMatch: String) -> [RoomLocation] {
		guard let pdfDoc = document else { return [] }

		// First, is this a named room? Named rooms don't have digits, so a match here implies alpha entry.
		var result: [RoomLocation] = []
		for room in namedRooms {
			if room.matchAgainst(nameToMatch) {
				result.append(room)
			}
		}
		
		// Next, is it something else room-like in the PDF? This could match a room number or a type+room string. 
		if result.count == 0 {
			let selections = pdfDoc.findString(nameToMatch, withOptions: .caseInsensitive)
			if selections.count <= maxMatchingRooms {
				for sel in selections {
					var extendedSelection: PDFSelection = sel
					// Extend the selection to include adjacent digits
					for _ in 1...5 {
						let testSel = extendedSelection.copy() as! PDFSelection
						testSel.extend(atEnd: 1)
						if testSel.string?.last?.isWholeNumber == true {
							extendedSelection = testSel
						}
						else {
							break
						}
					} 
					
					for _ in 1...5 {
						let testSel = extendedSelection.copy() as! PDFSelection
						testSel.extend(atStart: 1)
						if testSel.string?.first?.isWholeNumber == true {
							extendedSelection = testSel
						}
						else {
							break
						}
					}
				
					if let roomName = extendedSelection.string, let firstPage = extendedSelection.pages.first {
						let pageIndex = pdfDoc.index(for: firstPage)
						
						// Validate that the room is on the page that matches its floor number. Oddly, the PDF
						// has a bunch of room-strings that don't match.
						if roomName.hasPrefix("\(pageIndex + 1)") {
							var room = RoomLocation("Suite \(roomName)", from: extendedSelection)
							room.location = extendedSelection
							result.append(room)
						}
					}
				}
				
				result.sort { $0.name < $1.name }
			}
		}
		
		switch result.count {
		case (maxMatchingRooms + 1)...:	return []
		case 1...maxMatchingRooms: return result
		default: return []
		}
	}
	
	// Returns the deck number
	func pointAtRoom(_ room: DeckDataManager.RoomLocation, forView pdfView: PDFView) -> Int {	
		guard let pdfDoc = document else { return 1 }
		var deck = 1

		removePointer()
	
		if let page = room.location.pages.first {
			var bounds = room.location.bounds(for: page)
			let pageBounds = page.bounds(for: .cropBox)
			if room.isPortSide {
				bounds.origin.x = pageBounds.minX
			}
			else {
				bounds.origin.x = pageBounds.maxX - 20
			}
			bounds.size.width = 20.0
			let line = PDFAnnotation(bounds: bounds, forType: .line, withProperties: nil)
			if room.isPortSide {
				line.endLineStyle = .openArrow
			}
			else {
				line.startLineStyle = .openArrow
			}
			line.color = .red
			line.startPoint = CGPoint(x: 0, y: bounds.size.height / 2.0)
			line.endPoint = CGPoint(x: bounds.size.width, y: bounds.size.height / 2.0)
			page.addAnnotation(line)
			roomPointer = line

			// Nav the view so that the annotation is visible
			var navBounds = bounds.insetBy(dx: 0.0, dy: 0 - pdfView.bounds.size.height / (pdfView.maxScaleFactor * 2))
			navBounds = navBounds.intersection(pageBounds)
			pdfView.scaleFactor = room.isFullDeck ? pdfView.minScaleFactor : pdfView.maxScaleFactor
			pdfView.go(to: navBounds, on: page)
		}
		
		if let curPage = pdfView.currentPage {
			deck = pdfDoc.index(for: curPage) + 1
		}
		return deck
	}
	
	func removePointer() {
		if let pointer = roomPointer, let annotatedPage = pointer.page {
			annotatedPage.removeAnnotation(pointer)
		}
	}
	

	func findBounds(_ forString: String) -> PDFSelection? {
		let selections = document?.findString(forString, withOptions: .caseInsensitive)
		if let sel = selections?.first, let page = sel.pages.first {
			print (sel.bounds(for: page))
			return sel
		}
		return nil
	}

}


/* Deck 1
	Mainstage
	Atrium Bar
	Atrium
	Guest Services
Deck 2
	Mainstage
	Casino
	Billboard Onboard
	Gallery Bar
	B.B King's
	Pinnacle Grill
	Pinnacle Bar
	Art Gallery
	Lincoln Center State
	Explorer's Lounge
	Digital Workshop
	Dining Room
Deck 3
	Mainstage
	Hudson
	Tasman Room
	Half Moon
	Stuyvesant
	Merabella luxury collection
	The Shops
	Ocean Bar
	Photo Gallery
	Dining Room
Deck 7
	Neptune Lounge
Deck 9
	Fitness Center
	Greenhouse Spa
	Hydro Pool
	Lido Pool
	Lido Bar
	Dive-In Bar
	Canaletto
	Lido Market
	New York Pizza
	Sea View Bar
	Sea View Pool
Deck 10
	Club Hal
	The Loft
Deck 11
	Explorations Central
	The Retreat
	Tamarind Bar
	Tamarind
	Sports Courts


*/
