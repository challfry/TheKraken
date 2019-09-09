//
//  KaraokeRootViewController.swift
//  Kraken
//
//  Created by Chall Fry on 9/6/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit
import Compression

class KaraokeRootViewController: BaseCollectionViewController {
	@IBOutlet weak var filterTextField: UITextField!
	@IBOutlet weak var artistSongSegmentedControl: UISegmentedControl!
	@IBOutlet weak var favoriteFilterButton: UIButton!
	
	enum fileLoadingError: String {
		case findFileError = "Couldn't find compressed Karaoke Song file."
		case decodeError = "Decoding Karaoke Songs file failed."
	}


	var fileLoadError: fileLoadingError?
	var loadingComplete: Bool = false

	private let backgroundQ = DispatchQueue(label:"Karaoke Songfile decompressor")
	
	// These represent the full state of the song catalog.
	var artists: [String : [KaraokeSong]] = [:]
	var artistArray: [String] = []							// All artists, sorted alphabetically
	var songsArray: [KaraokeSong] = []							// All songs, sorted alphabetically
	
	// These represent the state of the current filter
	var filterArtistArray: [String] = []					// These are filtered, but not reordered.
	var filterSongsArray: [KaraokeSong] = []
	
	//
	var sortByArtists = true								// Mirrors state of Artist/Song segmented control
	var expandedArtistSections: Set<String> = Set()			// Which artists have expanded sections.

	override func viewDidLoad() {
        super.viewDidLoad()
        self.title = "Karaoke"

//		compressSongFile()
		loadSongFile()
		
		collectionView.register(UINib(nibName: "KaraokeSongCell", bundle: nil), forCellWithReuseIdentifier: "KaraokeSongCell")
		collectionView.register(UINib(nibName: "KaraokeArtistSectionHeaderView", bundle: nil), 
				forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: "KaraokeArtistSectionHeaderView")
		collectionView.dataSource = self
		collectionView.collectionViewLayout = KaraokeCollectionLayout(self)
		
		if let layout = collectionView.collectionViewLayout as? UICollectionViewFlowLayout {
			layout.itemSize = CGSize(width: collectionView.bounds.size.width, height: 44)
			layout.headerReferenceSize = CGSize(width: collectionView.bounds.size.width, height: 44)
		}
   }

	func loadSongFile() {
		backgroundQ.async {
//			let startTime = ProcessInfo.processInfo.systemUptime
		
			// Step 1: Get the file contents into memory
			guard let fileUrl = Bundle.main.url(forResource: "JoCoKaraokeSongCatalog", withExtension: "lzfse"),
						let encodedFileHandle = try? FileHandle(forReadingFrom: fileUrl) else { 
					self.fileLoadError = .findFileError; return 
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
			var threadArtists: [String : [KaraokeSong]] = [:]
			var threadArtistArray: [String] = []
			let scanner = Scanner(string: fileStr)
			while !scanner.isAtEnd, let nextLine = scanner.scanUpToCharactersFrom(CharacterSet.newlines) {
				let parts = nextLine.split(separator: "\t")
				if parts.count >= 2 {
					let artistName = String(parts[0])
					let modifier: String? = parts.count >= 3 ? String(parts[2]) : nil
					let newSong = KaraokeSong(artistName: String(artistName), songTitle: String(parts[1]), 
							whateverThisModifierIs: modifier, isFavorite: false)
					threadSongs.append(newSong)
					
					if let _ = threadArtists[artistName] {
						threadArtists[artistName]?.append(newSong)
					}
					else {
						threadArtists[artistName] = [newSong]
					}
				}
				
			}
			
			// Step 4: Sort the arrays
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
				self.collectionView.reloadData()
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
		let songCount = artists[artistName]?.count ?? 0
		for (index, artist) in artistArray.enumerated() {
			if artist == artistName {
				collectionView.performBatchUpdates( {
					var indexes: [IndexPath] = []
					(0..<songCount).forEach { indexes.append(IndexPath(row: $0, section: index)) }
					if newState {
						collectionView.insertItems(at: indexes)
					}
					else {
						collectionView.deleteItems(at: indexes)
					}
				}, completion: { completed in
				
				})
	//			collectionView.reloadSections(IndexSet(integer: index))
				break
			}
		}
	}
	
	func processNewFilterValues() {
		
	}

// MARK: Actions

	@IBAction func filterTextChanged(_ sender: UITextField) {
		print("Filter string now \(sender.text ?? "")")
	}
	

	@IBAction func artistSongToggleTapped() {
		sortByArtists = artistSongSegmentedControl.selectedSegmentIndex == 1 
		collectionView.reloadData()
	}

	@IBAction func favoriteFilterButtonTapped(_ sender: Any) {
		favoriteFilterButton.isSelected = !favoriteFilterButton.isSelected
	}
	
}

extension KaraokeRootViewController: UICollectionViewDataSource {
	func numberOfSections(in collectionView: UICollectionView) -> Int {
		return artistArray.count
    }

	func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
		let artistName = artistArray[section]
	//	print("Asking # of items for section \(section), artist \(artistName)")
		if expandedArtistSections.contains(artistName) {
			return artists[artistName]?.count ?? 0
		}
		
		return 0
	}
	
	func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
		let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "KaraokeSongCell", for: indexPath) as! KaraokeSongCell
		cell.songNameLabel.text = artists[artistArray[indexPath.section]]?[indexPath.row].songTitle
		cell.vc = self
		return cell
	}
	
	func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, 
			at indexPath: IndexPath) -> UICollectionReusableView {
		if let newView = collectionView.dequeueReusableSupplementaryView(ofKind: UICollectionView.elementKindSectionHeader,
				withReuseIdentifier: "KaraokeArtistSectionHeaderView", for: indexPath) as? KaraokeArtistSectionHeaderView {
			let artistName = artistArray[indexPath.section]
			newView.artistLabel.text = artistName
			newView.vc = self
			newView.setInitialDisclosureState(expandedArtistSections.contains(artistName))
			return newView
		}
		return UICollectionReusableView()
	}

}



struct KaraokeSong {
	var artistName: String
	var songTitle: String
	var whateverThisModifierIs: String?
	var isFavorite: Bool
}

class KaraokeSongCell: UICollectionViewCell {
	@IBOutlet weak var songNameLabel: UILabel!
	@IBOutlet weak var favoriteButton: UIButton!
	var widthConstraint: NSLayoutConstraint?

	weak var vc: KaraokeRootViewController? {
		didSet {
			if let width = vc?.collectionView.bounds.size.width, width > 0 {
				if let constraint = widthConstraint {
					constraint.constant = width
				}
				else {
					contentView.widthAnchor.constraint(equalToConstant: width).isActive = true
				}
			}
		}	
	}
	
	override func awakeFromNib() {
		translatesAutoresizingMaskIntoConstraints = false
		contentView.translatesAutoresizingMaskIntoConstraints = false
		super.awakeFromNib()
	}
	
	@IBAction func favoriteButtonTapped() {
		favoriteButton.isSelected = !favoriteButton.isSelected
	}
}

class KaraokeArtistSectionHeaderView: UICollectionReusableView {
	@IBOutlet weak var artistLabel: UILabel!
	@IBOutlet weak var disclosureButton: UIButton!
	
	weak var vc: KaraokeRootViewController?
	
	override func awakeFromNib() {
		translatesAutoresizingMaskIntoConstraints = false
		super.awakeFromNib()
	}
	
	@IBAction func disclosureButtonTapped() {
		disclosureButton.isSelected = !disclosureButton.isSelected
		if let artistName = artistLabel.text {
			vc?.setDisclosureState(forArtist: artistName, to: disclosureButton.isSelected)
		}
		
		
		UIView.animate(withDuration: 0.3) {
			self.disclosureButton.imageView?.transform = CGAffineTransform(rotationAngle: self.disclosureButton.isSelected ? .pi : 0.0)
		}
	}
	
	func setInitialDisclosureState(_ newState: Bool) {
		disclosureButton.isSelected = newState
		self.disclosureButton.imageView?.transform = CGAffineTransform(rotationAngle: self.disclosureButton.isSelected ? .pi : 0.0)
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

// MARK: -
class KaraokeCollectionLayout: UICollectionViewLayout {
	var sectionHeaderPositions: [CGFloat] = []
	var cellPositions: [CGFloat] = []
	var privateContentSize: CGSize = CGSize(width: 0, height: 0)
	
	weak var viewController: KaraokeRootViewController?
	
	static let sectionHeaderHeight: CGFloat = 44.0
	static let cellHeight: CGFloat = 44.0
			
// MARK: Methods	
	init(_ vc: KaraokeRootViewController) {
		viewController = vc
		super.init()
	}
	
	required init?(coder aDecoder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}
	
	override func prepare() {
		guard let cv = collectionView, let vc = viewController else { return }
		
		cellPositions.removeAll()
		sectionHeaderPositions.removeAll()
		let cvWidth = cv.bounds.width
		
		// Iterate through each cell in each section, get the cell's size, and place each cell in a big stack.
		var pixelOffset: CGFloat = 0.0
		if vc.sortByArtists {
			for artistName in vc.filterArtistArray {
				sectionHeaderPositions.append(pixelOffset)
				pixelOffset += KaraokeCollectionLayout.sectionHeaderHeight
				if vc.expandedArtistSections.contains(artistName) {
					pixelOffset += CGFloat((vc.artists[artistName]?.count ?? 0)) * KaraokeCollectionLayout.cellHeight
				}
			}
			privateContentSize = CGSize(width: cvWidth, height: pixelOffset)
		}
		else {
			privateContentSize = CGSize(width: cvWidth, height: CGFloat(vc.filterSongsArray.count) * KaraokeCollectionLayout.cellHeight)
		}
				
	}
	
	override var collectionViewContentSize: CGSize {
		return privateContentSize
	}

	override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {	
		var result: [UICollectionViewLayoutAttributes] = []
		
		guard let cv = collectionView, let vc = viewController else { return result }
		let cvWidth = cv.bounds.width
		if vc.sortByArtists {
			if sectionHeaderPositions.count == 0 {
				return nil
			}
			var startSection = sectionHeaderPositions.firstIndex { $0 >= rect.minY } ?? sectionHeaderPositions.count - 1
			if startSection < 0 { startSection = 0 }
			if sectionHeaderPositions[startSection] > rect.minY && startSection > 0 {
				startSection = startSection - 1
			}
			visibleRectDone: for sectionIndex in startSection..<sectionHeaderPositions.count {
				let val = UICollectionViewLayoutAttributes(forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
						with: IndexPath(row: 0, section: sectionIndex))
				val.isHidden = false
				var currentRect =  CGRect(x: 0.0, y: sectionHeaderPositions[sectionIndex], width: cvWidth, 
						height: KaraokeCollectionLayout.sectionHeaderHeight)
				val.frame = currentRect
				result.append(val)
				
				if vc.expandedArtistSections.contains(vc.filterArtistArray[sectionIndex]),
					let songCount = vc.artists[vc.filterArtistArray[sectionIndex]]?.count {
					currentRect.origin.y += KaraokeCollectionLayout.sectionHeaderHeight
					currentRect.size.height = KaraokeCollectionLayout.cellHeight
					for row in 0..<songCount {
						let val = UICollectionViewLayoutAttributes(forCellWith: IndexPath(row: row, section: sectionIndex))
						val.isHidden = false
						val.frame = currentRect
						result.append(val)
						currentRect.origin.y += KaraokeCollectionLayout.cellHeight
						
						if currentRect.origin.y > rect.maxY {
							break visibleRectDone
						}
					}
				}
			}
		} 
		else {
			let startIndex = Int(rect.minY) / Int(KaraokeCollectionLayout.cellHeight)
			let endIndex = Int(rect.maxY) / Int(KaraokeCollectionLayout.cellHeight) + 1
			
			for index in startIndex..<endIndex {
				let val = UICollectionViewLayoutAttributes(forCellWith: IndexPath(row: index, section: 0))
				val.isHidden = false
				val.frame = CGRect(x: 0, y: CGFloat(index) * KaraokeCollectionLayout.cellHeight, 
						width: cvWidth, height: KaraokeCollectionLayout.cellHeight)
				result.append(val)
				
				if index >= vc.filterSongsArray.count {
					break
				}				
			}
		}		
		
		return result
	}
	
	override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
		let result = UICollectionViewLayoutAttributes(forCellWith: indexPath)
		result.isHidden = false
		guard let cv = collectionView, let vc = viewController else { return result }
		let cvWidth = cv.bounds.width
		
		if vc.sortByArtists {
			result.frame = CGRect(x: 0.0, y: CGFloat(indexPath.row) * KaraokeCollectionLayout.cellHeight +
					sectionHeaderPositions[indexPath.section] + KaraokeCollectionLayout.sectionHeaderHeight, 
					width: cvWidth, height: KaraokeCollectionLayout.cellHeight)
		}
		else {
			result.frame = CGRect(x: 0, y: CGFloat(indexPath.row) * KaraokeCollectionLayout.cellHeight, 
					width: cvWidth, height: KaraokeCollectionLayout.cellHeight)
		}
		
		return result
	}
	
	override func layoutAttributesForSupplementaryView(ofKind elementKind: String, at indexPath: IndexPath) 
			-> UICollectionViewLayoutAttributes? {
		guard let cv = collectionView, let vc = viewController else { return nil }
		let cvWidth = cv.bounds.width

		if vc.sortByArtists {
			let result = UICollectionViewLayoutAttributes(forCellWith: indexPath)
			result.isHidden = false
			result.frame = CGRect(x: 0.0, y: sectionHeaderPositions[indexPath.section], width: cvWidth, height:
					KaraokeCollectionLayout.sectionHeaderHeight)
			return result
		}

		return nil
		
	}
	
// MARK: Insert/Delete handling

	var currentUpdateList: [UICollectionViewUpdateItem]?
	override func prepare(forCollectionViewUpdates updateItems: [UICollectionViewUpdateItem]) {
		currentUpdateList = updateItems
	}
	override func finalizeCollectionViewUpdates() {
		currentUpdateList = nil
	}

	override func indexPathsToInsertForSupplementaryView(ofKind elementKind: String) -> [IndexPath] {
		guard let vc = viewController, vc.sortByArtists else { return [] }
		
		var result = [IndexPath]()
		if let updates = currentUpdateList {
			for update in updates {
				if update.updateAction == .insert, update.indexPathAfterUpdate?.count == 1, 
						let section = update.indexPathAfterUpdate?.section  {
					result.append(IndexPath(row: 0, section: section))
				}
			}
		}
		
		return result
	}
	
	override func indexPathsToDeleteForSupplementaryView(ofKind elementKind: String) -> [IndexPath] {
		guard let vc = viewController, vc.sortByArtists else { return [] }

		var result = [IndexPath]()
		if let updates = currentUpdateList {
			for update in updates {
				if update.updateAction == .delete, update.indexPathBeforeUpdate?.count == 1, 
						let section = update.indexPathBeforeUpdate?.section  {
					result.append(IndexPath(row: 0, section: section))
				}
			}
		}
		
		return result
	}
	
// MARK: Invalidation

	override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
		if let cv = collectionView, newBounds.size.width != cv.bounds.size.width {
			return true
		}
		return false
	}
	
//	override func targetContentOffset(forProposedContentOffset proposedContentOffset: CGPoint) -> CGPoint {
//		guard let focusCellModel = focusCellModel, let eventsSegment = eventsSegment else { return proposedContentOffset }
//		
//		if currentUpdateList == nil {
//			return proposedContentOffset
//		}
//		
//		if var focusIndexPath = eventsSegment.indexPathNearest(to: focusCellModel) {
//		
//			// Hack
//			focusIndexPath.section += 1
//		
//			let cellRect = cellPositions[focusIndexPath.section][focusIndexPath.row]
//			return cellRect.origin
//		}
//		
//		return proposedContentOffset
//	}
}

