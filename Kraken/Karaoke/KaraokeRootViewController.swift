//
//  KaraokeRootViewController.swift
//  Kraken
//
//  Created by Chall Fry on 9/6/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit
import Compression

class KaraokeRootViewController: UIViewController {
	@IBOutlet weak var filterTextField: UITextField!
	@IBOutlet weak var artistSongSegmentedControl: UISegmentedControl!
	@IBOutlet weak var favoriteFilterButton: UIButton!
	@IBOutlet weak var tableView: UITableView!
	@IBOutlet weak var tableIndexView: KaraokeTableIndexView!
	@IBOutlet weak var tableIndexViewTrailing: NSLayoutConstraint!
	
	enum FileLoadingError: String {
		case findFileError = "Error: Couldn't find compressed Karaoke Song file."
		case decodeError   = "Error: Decoding Karaoke Songs file failed."
	}

	var fileLoadError: FileLoadingError?
	var loadingComplete: Bool = false

	private let backgroundQ = DispatchQueue(label:"Karaoke Songfile decompressor")
	
	// These represent the full state of the song catalog.
	var artists: [String : KaraokeArtist] = [:]
	var artistArray: [String] = []							// All artists, sorted alphabetically
	var songsArray: [KaraokeSong] = []							// All songs, sorted alphabetically
	
	// These represent the state of the current filter
	var filterArtistArray: [String] = []					// These are filtered, but not reordered from the full lists
	var filterSongsArray: [KaraokeSong] = []
	
	// These represent other table state
	var sortByArtists = true								// Mirrors state of Artist/Song segmented control
	var expandedArtistSections: Set<String> = Set()			// Which artists have expanded sections.

	override func viewDidLoad() {
        super.viewDidLoad()
        self.title = "Karaoke"

//		compressSongFile()
		loadSongFile()
		
		tableView.dataSource = self
		tableView.delegate = self
		tableView.rowHeight = 44.0
		tableView.estimatedRowHeight = 44.0
		tableView.register(UINib(nibName: "KaraokeLoadingCell", bundle: nil), forCellReuseIdentifier: "KaraokeLoadingCell")
		tableView.register(UINib(nibName: "KaraokeSongCell", bundle: nil), forCellReuseIdentifier: "KaraokeSongCell")
		tableView.register(UINib(nibName: "KaraokeArtistSectionHeaderView", bundle: nil), 
				forHeaderFooterViewReuseIdentifier: "KaraokeArtistSectionHeaderView")
				
		tableIndexView.setup(self)
		
		// Here is where we setup initial state that *could* be done in IB, but doing so makes it hard to edit the views in IB
		tableIndexViewTrailing.constant = tableIndexView.bounds.size.width
	}
	
	// Only works for File Load errors. The cell that displays the error goes away once the load succeeds.
	func showErrorState(_ error: FileLoadingError) {
		DispatchQueue.main.async {
			if let cell = self.tableView.cellForRow(at: IndexPath(row: 0, section: 0)) as? KaraokeLoadingCell {
				cell.showErrorState(error)
			}
		}
	}
   

	func loadSongFile() {
		backgroundQ.async {
//			let startTime = ProcessInfo.processInfo.systemUptime
		
			// Step 1: Get the file contents into memory
			guard let fileUrl = Bundle.main.url(forResource: "JoCoKaraokeSongCatalog", withExtension: "lzfse"),
						let encodedFileHandle = try? FileHandle(forReadingFrom: fileUrl) else { 
					self.showErrorState(.findFileError); return 
			}
			
			let encodedSourceData = encodedFileHandle.readDataToEndOfFile()
			
			// Step 2: Use Apple's Compression lib to decode the LZFSE file
			let fileStr: String = encodedSourceData.withUnsafeBytes { (encodedSourceBuffer: UnsafeRawBufferPointer) -> String in
				let decodedCapacity = 8000000
				let decodedDestinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: decodedCapacity)
				let unsafeBufferPointer = encodedSourceBuffer.bindMemory(to: UInt8.self)
				let encodedSourcePtr = unsafeBufferPointer.baseAddress!
				let decodedCharCount = compression_decode_buffer(decodedDestinationBuffer, decodedCapacity,
						encodedSourcePtr, encodedSourceData.count, nil,  COMPRESSION_LZFSE)
				if decodedCharCount == 0 {
					self.fileLoadError = .decodeError
					return ""
				}

				return String(cString: decodedDestinationBuffer)
			}
//			print ("Decode Time: \(ProcessInfo.processInfo.systemUptime - startTime)")
			
			// Step 3: Parse the file, creating local versions of the 'full state' vars.
			var threadSongs: [KaraokeSong] = []
			var threadArtists: [String : KaraokeArtist] = [:]
			var threadArtistArray: [String] = []
			let scanner = Scanner(string: fileStr)
			while !scanner.isAtEnd, let nextLine = scanner.KscanUpToCharactersFrom(CharacterSet.newlines) {
				let parts = nextLine.split(separator: "\t")
				if parts.count >= 2 {
					let artistName = String(parts[0])
					let modifier: String? = parts.count >= 3 ? String(parts[2]) : nil
					let newSong = KaraokeSong(artistName: String(artistName), songTitle: String(parts[1]), 
							whateverThisModifierIs: modifier)
					threadSongs.append(newSong)
					
					var artist = threadArtists[artistName]
					if artist == nil {
						artist = KaraokeArtist(artistName: artistName)
						threadArtists[artistName] = artist
					}
					artist?.allSongs.append(newSong)
					artist?.filterSongs.append(newSong)
				}
			}
			
			// Step 4: Set up favorites
			let context = LocalCoreData.shared.mainThreadContext
			context.performAndWait {
				do {
					let fetchRequest = NSFetchRequest<KaraokeFavoriteSong>(entityName: "KaraokeFavoriteSong")
					let cdFavoriteSongs = try context.fetch(fetchRequest)
					
					for favoriteSong in cdFavoriteSongs {
						if let artist = threadArtists[favoriteSong.artistName] {
							artist.numFavoriteSongs += 1
							if let song = artist.allSongs.first(where: { $0.songTitle == favoriteSong.songTitle }) {
								song.isFavorite = true
							}
						}
					}
				}	
				catch {
					CoreDataLog.error("Couldn't load Favorite Karaoke Songs from Core Data.", ["Error" : error])
				}
			}

			// Step 5: Sort the arrays
			threadArtistArray = threadArtists.keys.sorted { $0.caseInsensitiveCompare($1) == .orderedAscending }
			threadSongs = threadSongs.sorted { $0.songTitle.caseInsensitiveCompare($1.songTitle) == .orderedAscending }
//			print ("Total Time: \(ProcessInfo.processInfo.systemUptime - startTime)")
			
			// Step 5: Write data back, on the main thread.
			DispatchQueue.main.async {
				self.artists = threadArtists
				self.artistArray = threadArtistArray
				self.songsArray = threadSongs
				self.filterArtistArray = self.artistArray
				self.filterSongsArray = self.songsArray
				self.loadingComplete = true
				self.tableView.reloadData()
				self.showHideTableIndex()
			}
		}
	}
	
	func saveFavoriteSongs() {
		let context = LocalCoreData.shared.networkOperationContext
		context.perform {
			do {
				let fetchRequest = NSFetchRequest<KaraokeFavoriteSong>(entityName: "KaraokeFavoriteSong")
				let cdFavoriteSongs = try context.fetch(fetchRequest)
				for song in cdFavoriteSongs {
					context.delete(song)
				}
				let favoriteSongs = self.songsArray.filter { $0.isFavorite == true }
				for fav in favoriteSongs {
					let newSong = KaraokeFavoriteSong(context: context)
					newSong.artistName = fav.artistName
					newSong.songTitle = fav.songTitle
				}
				try context.save()
			}
			catch {
				CoreDataLog.error("Couldn't save Favorite Karaoke Songs to Core Data.", ["Error" : error])
			}
		}
	}
	
	func setDisclosureState(forArtist artistName: String, to newState: Bool) {
		if newState {
			expandedArtistSections.insert(artistName)
		}
		else {
			expandedArtistSections.remove(artistName)
		}

		if sortByArtists {
			let songCount = artists[artistName]?.filterSongs.count ?? 0
			
			for (index, artist) in filterArtistArray.enumerated() {
				if artist == artistName {
					tableView.performBatchUpdates( {
						var indexes: [IndexPath] = []
						(0..<songCount).forEach { indexes.append(IndexPath(row: $0, section: index)) }
						if newState {
							tableView.insertRows(at: indexes, with: .fade)
						}
						else {
							tableView.deleteRows(at: indexes, with: .fade)
						}
					}, completion: { completed in
					
					})
					break
				}
			}
		}
	}
	
	func processNewFilterValues() {
		let filterString = filterTextField.text
		let onlyFavorites = favoriteFilterButton.isSelected
		
		var newArtistsFilter: [String] = []					
		var newSongsFilter: [KaraokeSong] = []
		
		if let filterString = filterString?.lowercased(), filterString.count > 0 {
			for artistName in artistArray {
				guard let artist = artists[artistName] else { continue }
				var songsToAdd: [KaraokeSong]
				if artistName.lowercased().contains(filterString) {
					songsToAdd = artist.allSongs.filter({ onlyFavorites ? $0.isFavorite : true })
				}
				else {
					songsToAdd = artist.allSongs.filter({ 
							(onlyFavorites ? $0.isFavorite : true) && $0.songTitle.lowercased().contains(filterString) })
				}
				if songsToAdd.count > 0 {
					newArtistsFilter.append(artistName)
					newSongsFilter.append(contentsOf: songsToAdd)
					artist.filterSongs = songsToAdd
				}
				else {
					artist.filterSongs = []
				}
			}
		}
		else if onlyFavorites {
			for artistName in artistArray {
				guard let artist = artists[artistName] else { continue }
				let songsToAdd = artist.allSongs.filter({ $0.isFavorite }) 
				if songsToAdd.count > 0 {
					newArtistsFilter.append(artistName)
					newSongsFilter.append(contentsOf: songsToAdd)
					artist.filterSongs = songsToAdd
				}
				else {
					artist.filterSongs = []
				}
			}
		}
		else {
			newArtistsFilter = artistArray
			newSongsFilter = songsArray
			for (_, artist) in artists {
				artist.filterSongs = artist.allSongs
			}
		}
		
		// Artists is already correctly sorted; songs may need to get sorted again.
		newSongsFilter = newSongsFilter.sorted { $0.songTitle.caseInsensitiveCompare($1.songTitle) == .orderedAscending }

		filterArtistArray = newArtistsFilter
		filterSongsArray = newSongsFilter
		tableView.reloadData()
		
		tableIndexView.filterUpdated()
		showHideTableIndex()
	}
	
	func showHideTableIndex() {
		let numCells = sortByArtists ? filterArtistArray.count : filterSongsArray.count
		let newOffset = numCells > 100 ? 0 : tableIndexView.bounds.size.width
		if newOffset != tableIndexViewTrailing.constant {
			UIView.animate(withDuration: 0.3, animations: {
				self.tableIndexViewTrailing.constant = numCells > 100 ? 0 : self.tableIndexView.bounds.size.width
				self.view.layoutIfNeeded()
			})
		}
	}
	
	func itemNameAt(percentage: CGFloat) -> String {
		if sortByArtists, filterArtistArray.count > 0 {
			var index = Int(CGFloat(filterArtistArray.count) * percentage)
			if index >= filterArtistArray.count { index = filterArtistArray.count - 1 }
			if index < 0 { index = 0 }
			return filterArtistArray[index]
		}
		else if filterSongsArray.count > 0 {
			var index = Int(CGFloat(filterSongsArray.count) * percentage)
			if index >= filterSongsArray.count { index = filterSongsArray.count - 1 }
			if index < 0 { index = 0 }
			return filterSongsArray[index].songTitle
		}
		else {
			return ""
		}
	}
	
	func scrollToPercentage(_ percentage: CGFloat) {
		if sortByArtists, filterArtistArray.count > 0 {
			var index = Int(CGFloat(filterArtistArray.count) * percentage)
			if index >= filterArtistArray.count { index = filterArtistArray.count - 1 }
			if index < 0 { index = 0 }
			tableView.scrollToRow(at: IndexPath(row: NSNotFound, section: index), at: .middle, animated: true)
		}
		else if filterSongsArray.count > 0 {
			var index = Int(CGFloat(filterSongsArray.count) * percentage)
			if index >= filterSongsArray.count { index = filterSongsArray.count - 1 }
			if index < 0 { index = 0 }
			tableView.scrollToRow(at: IndexPath(row: index, section: 0), at: .middle, animated: true)
		}
	}

// MARK: Actions

	@IBAction func filterTextChanged(_ sender: UITextField) {
		processNewFilterValues()
	}
	

	@IBAction func artistSongToggleTapped() {
		sortByArtists = artistSongSegmentedControl.selectedSegmentIndex == 0
		tableView.reloadData()
	}

	@IBAction func favoriteFilterButtonTapped(_ sender: Any) {
		favoriteFilterButton.isSelected = !favoriteFilterButton.isSelected
		processNewFilterValues()
	}
	
}

extension KaraokeRootViewController: UITableViewDataSource, UITableViewDelegate {
	func numberOfSections(in tableView: UITableView) -> Int {
		if !loadingComplete {
			return 1
		} 
		else if sortByArtists {
			return filterArtistArray.count
		}
		else {
			return 1
		}
    }

	func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		if !loadingComplete {
			return 1
		} 
		else if sortByArtists {
			let artistName = filterArtistArray[section]
			if expandedArtistSections.contains(artistName) {
				return artists[artistName]?.filterSongs.count ?? 0
			}
		}
		else {
			return filterSongsArray.count
		}
		
		return 0
	}
	
	func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		if !loadingComplete {
  			let cell = tableView.dequeueReusableCell(withIdentifier: "KaraokeLoadingCell", for: indexPath)
			return cell
		}
		
  		let cell = tableView.dequeueReusableCell(withIdentifier: "KaraokeSongCell", for: indexPath) as! KaraokeSongCell
		if sortByArtists {
			if let song = artists[filterArtistArray[indexPath.section]]?.filterSongs[indexPath.row] {
				cell.setup(song, showArtist: false)
			}
		}
		else {
			cell.setup(filterSongsArray[indexPath.row], showArtist: true)
		}
		cell.vc = self
		return cell
	}

	func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
		if !loadingComplete {
			return nil
		}
		
		if sortByArtists, let newView = tableView.dequeueReusableHeaderFooterView(withIdentifier:"KaraokeArtistSectionHeaderView")
				as? KaraokeArtistSectionHeaderView {
			if let artist = artists[filterArtistArray[section]] {
				newView.setup(for: artist, vc: self)
			}
			return newView
		}
		return nil
	}
	
	func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
		if loadingComplete && sortByArtists {
			return 44.0
		} 
		else {
			return 0.0
		}
	}
	
	func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
		return 44.0
	}

	func tableView(_ tableView: UITableView, estimatedHeightForHeaderInSection section: Int) -> CGFloat {
		if loadingComplete &&  sortByArtists {
			return 44.0
		} 
		else {
			return 0.0
		}
	}
}

// MARK: -
class KaraokeArtist: NSObject {
	var artistName: String
	var numFavoriteSongs: Int = 0
	var allSongs: [KaraokeSong] = []
	var filterSongs: [KaraokeSong] = []

	init(artistName: String) {
		self.artistName = artistName
		numFavoriteSongs = 0
		super.init()
	}
}

class KaraokeSong: NSObject {
	var artistName: String
	var songTitle: String
	var whateverThisModifierIs: String?
	var isFavorite: Bool
	
	init(artistName: String, songTitle: String, whateverThisModifierIs: String?) {
		self.artistName = artistName
		self.songTitle = songTitle
		self.whateverThisModifierIs	= whateverThisModifierIs
		isFavorite = false
		super.init()
	}
}

@objc(KaraokeFavoriteSong) public class KaraokeFavoriteSong: KrakenManagedObject {
    @NSManaged public var artistName: String
    @NSManaged public var songTitle: String
}

//
class KaraokeLoadingCell: UITableViewCell {
	@IBOutlet weak var loadingLabel: UILabel!
	@IBOutlet weak var spinner: UIActivityIndicatorView!
	
	func showErrorState(_ error: KaraokeRootViewController.FileLoadingError) {
		spinner.isHidden = true
		loadingLabel.text = error.rawValue
	}
}

// All the songs in the table use this cell class--that means both Artist View and Song View.
class KaraokeSongCell: UITableViewCell {
	@IBOutlet weak var songNameLabel: UILabel!
	@IBOutlet weak var artistNameLabel: UILabel!
	@IBOutlet weak var favoriteButton: UIButton!
	@IBOutlet weak var songNameLabelTopConstraint: NSLayoutConstraint!
	
	weak var vc: KaraokeRootViewController?
	var song: KaraokeSong?
	
	override func awakeFromNib() {
		super.awakeFromNib()

		// Font styling
		songNameLabel.styleFor(.body)
		artistNameLabel.styleFor(.body)
		favoriteButton.styleFor(.body)
	}

	func setup(_ song: KaraokeSong, showArtist: Bool) {
		self.song = song
		songNameLabel.text = song.songTitle
		favoriteButton.isSelected = song.isFavorite
		artistNameLabel.text = showArtist ? "By: \(song.artistName)" : ""
		self.setNeedsLayout()
		self.layoutIfNeeded()
		if songNameLabel.bounds.size.height > 25 {
			songNameLabelTopConstraint.constant = 2
			
			// If we're crunched for space and need to show the artist, rejigger w/smaller font and all in 1 label.
			if vc?.sortByArtists == false {
				let longNameAttrs: [NSAttributedString.Key : Any] = [ .font : UIFont.systemFont(ofSize: 14) as Any ]
				songNameLabelTopConstraint.constant = 2
				let combinedString = NSMutableAttributedString(string: song.songTitle, attributes: longNameAttrs)
				let greyAttrs: [NSAttributedString.Key : Any] = [ .font : UIFont.systemFont(ofSize: 14) as Any, 
						.foregroundColor : UIColor.gray]
				combinedString.append(NSAttributedString(string: " By: \(song.artistName)", attributes: greyAttrs))
				songNameLabel.attributedText = combinedString
				artistNameLabel.text = ""
			}
		}
		else {
			songNameLabelTopConstraint.constant = showArtist ? 2 : 11.5
		}
	}
	
	@IBAction func favoriteButtonTapped() {
		favoriteButton.isSelected = !favoriteButton.isSelected
		if let song = song {
			song.isFavorite = favoriteButton.isSelected
			if let artist = vc?.artists[song.artistName] {
				artist.numFavoriteSongs += favoriteButton.isSelected ? 1 : -1
			}
			vc?.saveFavoriteSongs()
		}
	}
}

// Section header view.
class KaraokeArtistSectionHeaderView: UITableViewHeaderFooterView {
	@IBOutlet weak var artistLabel: UILabel!
	@IBOutlet weak var disclosureButton: UIButton!
	@IBOutlet weak var numFavoritesLabel: UILabel!
	
	weak var viewController: KaraokeRootViewController?
	weak var artist: KaraokeArtist?

	override func awakeFromNib() {
		super.awakeFromNib()

		// Font styling
		artistLabel.styleFor(.body)
		disclosureButton.styleFor(.body)
	}

	func setup(for artist: KaraokeArtist, vc: KaraokeRootViewController) {
		self.artist = artist
		self.viewController = vc
		artistLabel.text = artist.artistName
		disclosureButton.isSelected = vc.expandedArtistSections.contains(artist.artistName)
		self.disclosureButton.imageView?.transform = CGAffineTransform(rotationAngle: self.disclosureButton.isSelected ? .pi : 0.0)

		if !disclosureButton.isSelected, artist.numFavoriteSongs > 0 {
			numFavoritesLabel.text =  "\(artist.numFavoriteSongs) 💛"
			numFavoritesLabel.isHidden = false
		}
		else {
			numFavoritesLabel.isHidden = true
		}
		
	}

	@IBAction func disclosureButtonTapped(_ sender: UIButton) {
		disclosureButton.isSelected = !disclosureButton.isSelected
		if let artistName = artistLabel.text {
			viewController?.setDisclosureState(forArtist: artistName, to: disclosureButton.isSelected)
		}
		
		UIView.animate(withDuration: 0.3) {
			self.disclosureButton.imageView?.transform = CGAffineTransform(rotationAngle: self.disclosureButton.isSelected ? .pi : 0.0)
			if !self.disclosureButton.isSelected, let artist = self.artist, artist.numFavoriteSongs > 0 {
				self.numFavoritesLabel.text =  "\(artist.numFavoriteSongs) 💛"
				self.numFavoritesLabel.isHidden = false
			}
			else {
				self.numFavoritesLabel.isHidden = true
			}
		}
	}
		
}

class KaraokeTableIndexView: UIView, UIGestureRecognizerDelegate {
//	static let fullIndexChars = "1234567890ABCDEFGHIJKLMNOPQRSTUVWXYZ"
	static let fullIndexChars = "1ABCDEFGHIJKLMNOPQRSTUVWXYZ"
	static let halfIndexChars = "1BDFHJLNPRTVXZ"

	weak var viewController: KaraokeRootViewController?
	var floatingLabel: UILabel?
	
	func setup(_ vc: KaraokeRootViewController) {
		viewController = vc
		let label = UILabel()
		label.backgroundColor = UIColor(named: "Overlay Label Background")
		label.textAlignment	= .right
		label.isHidden = true
		self.addSubview(label)
		floatingLabel = label
	}
	
	func filterUpdated() {
		
	}
	
	override func draw(_ rect: CGRect) {
		// Background first
		if let color = UIColor(named: "VC Background")?.cgColor {
			UIGraphicsGetCurrentContext()?.setFillColor(color)
			UIGraphicsGetCurrentContext()?.fill(rect)
		}
		
		// 
		var indexString = KaraokeTableIndexView.fullIndexChars
		if bounds.size.height < 360 {
			indexString = KaraokeTableIndexView.halfIndexChars
		}
		let stepSize = bounds.size.height / CGFloat(indexString.count)
		let textAttrs: [NSAttributedString.Key : Any] = [ .foregroundColor : UIColor(named: "Kraken Label Text") as Any ]
		for index in 0..<indexString.count {
		
			let str = NSAttributedString(string: String(Array(indexString)[index]), attributes: textAttrs)
			let strSize = str.size()
			let position = CGPoint(x: 8 - (strSize.width / 2), y: CGFloat(index) * stepSize)
			str.draw(at: position)
		}
	}
	
	func positionLabel(yPos: CGFloat) {
		let percentage = yPos / (bounds.size.height - 10)
		if let stringToShow = viewController?.itemNameAt(percentage: percentage), let label = floatingLabel {
			let textAttrs: [NSAttributedString.Key : Any] = [ .foregroundColor : UIColor(named: "Kraken Label Text") as Any ]
			let labelString = NSAttributedString(string: stringToShow, attributes: textAttrs)
			label.attributedText = labelString
			label.sizeToFit()

			label.frame = CGRect(x: 0 - label.bounds.size.width - 35, y: yPos - 10,
					width: label.bounds.size.width, height: label.bounds.size.height)
		}
	}
	
	override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
		if let touch = touches.first {
			floatingLabel?.isHidden = false
			positionLabel(yPos: touch.location(in: self).y) 
		}
	}

	override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
		if let touch = touches.first {
			positionLabel(yPos: touch.location(in: self).y) 
		}
	}
	
	override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
		floatingLabel?.isHidden = true
		if let touch = touches.first {
			let percentage = touch.location(in: self).y / (bounds.size.height - 10)
			viewController?.scrollToPercentage(percentage)
		}
	}

	override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
		floatingLabel?.isHidden = true
	}

}


// MARK: - Special Use Code
extension KaraokeRootViewController {
	// DO NOT CALL THIS METHOD AS PART OF NORMAL APP EXECUTION!
	// This is a utility fn that's here to compress the Karaoke source file. To use, add the Karaoke TEXT file
	// to the app as a Resource file, add a call to this method somewhere, and run the app on the simulator. 
	// After this method runs, look at the console output and grab the file URL to the compressed file (which will point 
	// to somewhere inside /Library/Developer/CoreSimulator) and copy the new compressed file into the Git repo.
	func compressSongFile() {
		do {
			if let fileUrl = Bundle.main.url(forResource: "JoCoKaraokeSongCatalog", withExtension: "txt"),
					let fileContents = try? String(contentsOf: fileUrl, encoding: .utf8) {
				var sourceBuffer = Array(fileContents.utf8)
				let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: sourceBuffer.count)
				let compressedSize = compression_encode_buffer(destinationBuffer, sourceBuffer.count,
						&sourceBuffer, sourceBuffer.count, nil, COMPRESSION_LZFSE)
				print(compressedSize)
				
				let writeUrl = fileUrl.deletingPathExtension().appendingPathExtension("lzfse")
				let compressedData = Data(bytes: destinationBuffer, count: compressedSize)
				try compressedData.write(to: writeUrl)
				print (writeUrl)
			}
		}
		catch {
			print("Songlist compression failed, somehow.")
		}
	}
}
