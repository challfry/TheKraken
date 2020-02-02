//
//  GamesListStructs.swift
//  Kraken
//
//  Created by Chall Fry on 1/30/20.
//  Copyright © 2020 Chall Fry. All rights reserved.
//

import Foundation

// This file is used by both the Kraken app and the GameFetcher command line tool.
// GameFetcher takes a .txt file with game names, makes some calls to BoardGameGeek.com's XML API,
// and returns a json file full of instances of the struct shown below.


struct JsonGamesListGame: Codable {
	var gameName: String
	var bggGameName: String?
	var yearPublished: String?
	var gameDescription: String?

	var minPlayers: Int?
	var maxPlayers: Int?

	var minPlayingTime: Int?
	var maxPlayingTime: Int?
	var avgPlayingTime: Int?

	var minAge: Int?
	var numRatings: Int?
	var avgRating: Float?
	var complexity: Float?
}
