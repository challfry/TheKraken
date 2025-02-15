//
//  KaraokeRootViewController.swift
//  Kraken
//
//  Created by Chall Fry on 9/6/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit

class KaraokeRootViewController: UIViewController, TableIndexDelegate {
	@IBOutlet weak var filterTextField: UITextField!
	@IBOutlet weak var artistSongSegmentedControl: UISegmentedControl!
	@IBOutlet weak var favoriteFilterButton: UIButton!
	@IBOutlet weak var tableView: UITableView!
	@IBOutlet weak var tableIndexView: TableIndexView!
	@IBOutlet weak var tableIndexViewTrailing: NSLayoutConstraint!
	
	// Our connection to the song data
	let songData = KaraokeDataManager.shared
	
	// These represent the state of the current filter
	var filterArtistArray: [String] = []					// These are filtered, but not reordered from the full lists
	var filterSongsArray: [KaraokeSong] = []
	
	// These represent other table state
	var sortByArtists = true								// Mirrors state of Artist/Song segmented control
	var expandedArtistSections: Set<String> = Set()			// Which artists have expanded sections.
	
	var sectionHeaderPrototype: KaraokeArtistSectionHeaderView?

// MARK: Methods
	override func viewDidLoad() {
        super.viewDidLoad()
        self.title = "Karaoke"

	// DO NOT CALL THIS METHOD AS PART OF NORMAL APP EXECUTION!
	// This is a utility fn that's here to compress the Karaoke source file. To use, add the Karaoke TEXT file
	// to the app as a Resource file, add a call to this method somewhere, and run the app on the simulator. 
	// After this method runs, look at the console output and grab the file URL to the compressed file (which will point 
	// to somewhere inside /Library/Developer/CoreSimulator) and copy the new compressed file into the Git repo.
//		KaraokeDataManager.shared.compressSongFile()


		songData.loadSongFile {
			if let err = self.songData.fileLoadError {
				self.showErrorState(err)
				return
			}
			
			self.filterArtistArray = self.songData.artistArray
			self.filterSongsArray = self.songData.songsArray
			self.tableView.reloadData()
			self.showHideTableIndex()
			self.estimateHeights()
		}
		
		tableView.dataSource = self
		tableView.delegate = self
		tableView.rowHeight = 44.0
		tableView.estimatedRowHeight = 44.0
		tableView.register(UINib(nibName: "KaraokeLoadingCell", bundle: nil), forCellReuseIdentifier: "KaraokeLoadingCell")
		tableView.register(UINib(nibName: "KaraokeSongCell", bundle: nil), forCellReuseIdentifier: "KaraokeSongCell")
		let headerViewNib = UINib(nibName: "KaraokeArtistSectionHeaderView", bundle: nil)
		tableView.register(headerViewNib, forHeaderFooterViewReuseIdentifier: "KaraokeArtistSectionHeaderView")
				
		tableIndexView.setup(self)
		
		// Here is where we setup initial state that *could* be done in IB, but doing so makes it hard to edit the views in IB
		tableIndexViewTrailing.constant = tableIndexView.bounds.size.width
		
		let headerViewContents = headerViewNib.instantiate(withOwner: nil, options: nil)
		sectionHeaderPrototype = headerViewContents[0] as? KaraokeArtistSectionHeaderView
		sectionHeaderPrototype?.contentView.widthAnchor.constraint(equalToConstant: 414).isActive = true
		sectionHeaderPrototype?.isHidden = true
		self.view.addSubview(sectionHeaderPrototype!)

		// Set reasonable defaults for cell and section header sizes
		tableView.sectionHeaderHeight = 0
		tableView.estimatedSectionHeaderHeight = 0
		tableView.rowHeight = UITableView.automaticDimension
		tableView.estimatedRowHeight = 44
	}
	
	override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
		super.traitCollectionDidChange(previousTraitCollection)
		DispatchQueue.main.async {
			self.estimateHeights()
		}
	}
	
	func estimateHeights() {
		if songData.loadingComplete, let proto = sectionHeaderPrototype {
			if sortByArtists {
				let protoArtist = KaraokeArtist(artistName: "Proto Proto Proto Proto Proto Proto Proto Proto")
				proto.setup(for: protoArtist, vc: self)
				var labelHeight = proto.artistLabel.font.lineHeight
				
				// All section headers are the same size. Make that size be 2 lines of text for large fonts,
				// one line for smaller fonts. Note: Self-sizing headers *works*, but it unacceptably slow
				// for the ~6000 sections our dataset has.
				if tableView.traitCollection.preferredContentSizeCategory > .extraExtraLarge {
					labelHeight = labelHeight * 2.05 + 4 + 4
				}
				else {
					labelHeight = labelHeight + 4 + 4
				}
				tableView.sectionHeaderHeight = labelHeight < 44 ? 44 : labelHeight
				tableView.estimatedSectionHeaderHeight = labelHeight < 44 ? 44 : labelHeight
			}
			else {
				tableView.sectionHeaderHeight = 0
				tableView.estimatedSectionHeaderHeight = 0
			}
			tableView.reloadData()
	//		print("Size is now \(tableView.traitCollection.preferredContentSizeCategory), font lineheight is \(proto.artistLabel.font.lineHeight)")
		} 
		else {
			self.tableView.estimatedSectionHeaderHeight = 44.0
		}
		
	}
	
	// Only works for File Load errors. The cell that displays the error goes away once the load succeeds.
	func showErrorState(_ error: KaraokeDataManager.FileLoadingError) {
		DispatchQueue.main.async {
			if let cell = self.tableView.cellForRow(at: IndexPath(row: 0, section: 0)) as? KaraokeLoadingCell {
				cell.showErrorState(error)
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
			let songCount = songData.artists[artistName]?.filterSongs.count ?? 0
			
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
						self.tableView.scrollToRow(at: IndexPath(row: NSNotFound, section: index), at: .none, animated: false)
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
			for artistName in songData.artistArray {
				guard let artist = songData.artists[artistName] else { continue }
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
			for artistName in songData.artistArray {
				guard let artist = songData.artists[artistName] else { continue }
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
			newArtistsFilter = songData.artistArray
			newSongsFilter = songData.songsArray
			for (_, artist) in songData.artists {
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
		estimateHeights()
	}

	@IBAction func favoriteFilterButtonTapped(_ sender: Any) {
		favoriteFilterButton.isSelected = !favoriteFilterButton.isSelected
		processNewFilterValues()
	}
	
}

extension KaraokeRootViewController: UITableViewDataSource, UITableViewDelegate {
	func numberOfSections(in tableView: UITableView) -> Int {
		if !songData.loadingComplete {
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
		if !songData.loadingComplete {
			return 1
		} 
		else if sortByArtists {
			let artistName = filterArtistArray[section]
			if expandedArtistSections.contains(artistName) {
				return songData.artists[artistName]?.filterSongs.count ?? 0
			}
		}
		else {
			return filterSongsArray.count
		}
		
		return 0
	}
	
	func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		if !songData.loadingComplete {
  			let cell = tableView.dequeueReusableCell(withIdentifier: "KaraokeLoadingCell", for: indexPath)
			return cell
		}
		
  		let cell = tableView.dequeueReusableCell(withIdentifier: "KaraokeSongCell", for: indexPath) as! KaraokeSongCell
		if sortByArtists {
			if let song = songData.artists[filterArtistArray[indexPath.section]]?.filterSongs[indexPath.row] {
				cell.setup(song, showArtist: false)
			}
		}
		else {
			cell.setup(filterSongsArray[indexPath.row], showArtist: true)
		}
		return cell
	}

	func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
		if !songData.loadingComplete {
			return nil
		}
		
		if sortByArtists, let newView = tableView.dequeueReusableHeaderFooterView(withIdentifier:"KaraokeArtistSectionHeaderView")
				as? KaraokeArtistSectionHeaderView {
			if let artist = songData.artists[filterArtistArray[section]] {
				newView.setup(for: artist, vc: self)
			}
			return newView
		}
		return nil
	}
	
	// For self-sizing cells to work, I believe these methods need to remain unimplemented.
//	func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
//	}
	
//	func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
//		return 44.0
//	}

//	func tableView(_ tableView: UITableView, estimatedHeightForHeaderInSection section: Int) -> CGFloat {
//	}
}

//
class KaraokeLoadingCell: UITableViewCell {
	@IBOutlet weak var loadingLabel: UILabel!
	@IBOutlet weak var spinner: UIActivityIndicatorView!
	
	override func awakeFromNib() {
		super.awakeFromNib()

		// Font styling
		loadingLabel.styleFor(.body)
	}
	
	func showErrorState(_ error: KaraokeDataManager.FileLoadingError) {
		spinner.isHidden = true
		loadingLabel.text = error.rawValue
	}
}

// All the songs in the table use this cell class--that means both Artist View and Song View.
// We use a UITableView here because the performance of UICollectionView was ... really bad. 
// Probably fixable with a custom layout that had internal knowledge of the cell sizes.
class KaraokeSongCell: UITableViewCell {
	@IBOutlet weak var songNameLabel: UILabel!
	@IBOutlet weak var artistNameLabel: UILabel!
	@IBOutlet weak var favoriteButton: UIButton!
	@IBOutlet weak var songNameLabelTopConstraint: NSLayoutConstraint!
	
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
		
		//
		let songNameTextAttrs: [NSAttributedString.Key : Any] = [ .font : UIFont.systemFont(ofSize: 17) as Any ]
		let songModifierAttrs: [NSAttributedString.Key : Any] = [ .font : UIFont.systemFont(ofSize: 17) as Any,
				.foregroundColor : UIColor(named: "Red Alert Text") as Any ]
		let songNameStr = NSMutableAttributedString(string: song.songTitle, attributes: songNameTextAttrs)
		if song.isMidiTrack {
			songNameStr.append(NSAttributedString(string: " MIDI", attributes: songModifierAttrs))
		}
		if song.isVoiceReduced {
			songNameStr.append(NSAttributedString(string: " VoiceReduced", attributes: songModifierAttrs))
		}
		songNameLabel.attributedText = songNameStr
		songNameLabel.accessibilityLabel = "Song: \(songNameStr.string)"
		
		favoriteButton.isSelected = song.isFavorite
		artistNameLabel.text = showArtist ? "By: \(song.artistName)" : ""
		self.setNeedsLayout()
		self.layoutIfNeeded()
		
		// SongNameLabel has both an Align Center Y and Align Top constraint, both going to the left icon.
		// The Center constraint has priority 500. So, you can change the Top constraint priority to move the labe.
		
		// If the song name takes 2 lines--rejigger.
		if songNameLabel.bounds.size.height > 36 {
			songNameLabelTopConstraint.priority = UILayoutPriority(rawValue: 700)
//			songNameLabelTopConstraint.constant = 2
			
			// If we're crunched for space and need to show the artist, rejigger w/smaller font and all in 1 label.
//			if showArtist {
//				let longNameAttrs: [NSAttributedString.Key : Any] = [ .font : songNameLabel.font as Any ]
//				songNameLabelTopConstraint.constant = 2
//				let combinedString = NSMutableAttributedString(string: song.songTitle, attributes: longNameAttrs)
//				let greyAttrs: [NSAttributedString.Key : Any] = [ .font : songNameLabel.font as Any, 
//						.foregroundColor : UIColor.gray]
//				combinedString.append(NSAttributedString(string: " By: \(song.artistName)", attributes: greyAttrs))
//				songNameLabel.attributedText = combinedString
//				artistNameLabel.text = ""
//			}
		}
		else {
//			songNameLabelTopConstraint.constant = showArtist ? 2 : 11.5
			songNameLabelTopConstraint.priority = UILayoutPriority(rawValue: 200)
		}
	}
	
	@IBAction func favoriteButtonTapped() {
		favoriteButton.isSelected = !favoriteButton.isSelected
		KaraokeDataManager.shared.setFavoriteSongStatus(for: song, to: favoriteButton.isSelected)
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
		numFavoritesLabel.styleFor(.body)
		
		accessibilityElements = [artistLabel!, numFavoritesLabel!, disclosureButton!]
	}

	func setup(for artist: KaraokeArtist, vc: KaraokeRootViewController) {
		self.artist = artist
		self.viewController = vc
		artistLabel.text = artist.artistName
		artistLabel.accessibilityLabel = "Artist: \(artist.artistName)"
		disclosureButton.isSelected = vc.expandedArtistSections.contains(artist.artistName)
		self.disclosureButton.imageView?.transform = CGAffineTransform(rotationAngle: self.disclosureButton.isSelected ? .pi : 0.0)

		if !disclosureButton.isSelected, artist.numFavoriteSongs > 0 {
			numFavoritesLabel.text =  "\(artist.numFavoriteSongs) 💛"
			numFavoritesLabel.isHidden = false
			numFavoritesLabel.accessibilityLabel = "\(artist.numFavoriteSongs) favorite songs"
		}
		else {
			numFavoritesLabel.isHidden = true
		}
		self.contentView.backgroundColor = self.disclosureButton.isSelected ? UIColor(named: "VC Background") : 
				UIColor(named: "Cell Background")
		disclosureButton.accessibilityLabel = disclosureButton.isSelected ? "Hide Songs" : "Show Songs"
	}

	@IBAction func disclosureButtonTapped(_ sender: UIButton) {
		disclosureButton.isSelected = !disclosureButton.isSelected
		disclosureButton.accessibilityLabel = disclosureButton.isSelected ? "Hide Songs" : "Show Songs"
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

			//
			self.contentView.backgroundColor = self.disclosureButton.isSelected ? UIColor(named: "VC Background") : 
					UIColor(named: "Cell Background")
		}
	}
	
	override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
		disclosureButtonTapped(disclosureButton)
	}
		
}

