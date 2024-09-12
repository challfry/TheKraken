//
//  PerformerBioVC.swift
//  Kraken
//
//  Created by Chall Fry on 9/8/24.
//  Copyright © 2024 Chall Fry. All rights reserved.
//

import Foundation
import UIKit

class PerformerBioViewController: BaseCollectionViewController {
	var performerID: UUID?
	
	let performerDM = PerformerDataManager.shared
	var dataSource = KrakenDataSource()
	var headerSegment = FilteringDataSourceSegment()
		var headerCell: LabelCellModel?
	var eventsSegment = FRCDataSourceSegment<Event>()
	var bioSegment = FilteringDataSourceSegment()
		var bioCell: PerformerBioCellModel?
	
	override func viewDidLoad() {
		super.viewDidLoad()
		guard let performerID = performerID else {
			return
		}
		guard let performer = performerDM.updatePerformer(id: performerID) else {
			return
		}

		let str = NSAttributedString(string: "Events with \(performer.name)", attributes: labelTextAttributes())
		let headerCell = LabelCellModel(str)
		headerCell.bgColor = UIColor(named: "Info Title Background")
		self.headerCell = headerCell
		headerSegment.append(headerCell)
		eventsSegment.loaderDelegate = self
		eventsSegment.activate(predicate: NSPredicate(format: "%@ IN performers", performer), 
						sort: [ NSSortDescriptor(key: "startTime", ascending: true)], 
						cellModelFactory: createCellModel)
		let bioCell = PerformerBioCellModel(performer)
		self.bioCell = bioCell
		bioSegment.append(bioCell)

		dataSource.append(segment: headerSegment)
		dataSource.append(segment: eventsSegment)
		dataSource.append(segment: bioSegment)
  		dataSource.register(with: collectionView, viewController: self)
	}
	
	// Gets called from within collectionView:cellForItemAt:. Creates cell models from FRC result objects.
	func createCellModel(_ model: Event) -> BaseCellModel {
		let cellModel = EventCellModel(withModel: model)
		cellModel.disclosureLevel = 3
		return cellModel
	}
	
	func labelTextAttributes() -> [ NSAttributedString.Key : Any ] {
		let metrics = UIFontMetrics(forTextStyle: .body)
		let baseFont = UIFont(name:"Helvetica-Bold", size: 24) ?? UIFont.preferredFont(forTextStyle: .body)
		let scaledfont = metrics.scaledFont(for: baseFont)
		let result: [NSAttributedString.Key : Any] = [ .font : scaledfont as Any, 
				.foregroundColor : UIColor(named: "Kraken Label Text") as Any ]
		return result
	}
	
	// MARK: Navigation
	override var knownSegues : Set<GlobalKnownSegue> {
		Set<GlobalKnownSegue>([ .modalLogin, .showRoomOnDeckMap, .showForumThread ])
	}
}

extension PerformerBioViewController: FRCDataSourceLoaderDelegate {
	func userIsViewingCell(at indexPath: IndexPath) {
	}
}


// MARK: Bio Cell
@objc protocol PerformerBioCellBindingProtocol: KrakenCellBindingProtocol {
	var model: Performer? { get set }
}

@objc class PerformerBioCellModel: BaseCellModel, PerformerBioCellBindingProtocol {
	private static let validReuseIDs = [ "PerformerBioCell" : PerformerBioCell.self ]
	override class var validReuseIDDict: [String: BaseCollectionViewCell.Type ] { return validReuseIDs }

	@objc dynamic var model: Performer?
	
	init(_ performer: Performer) {
		model = performer
    	super.init(bindingWith: PerformerBioCellBindingProtocol.self)
    }
}

class PerformerBioCell: BaseCollectionViewCell, PerformerBioCellBindingProtocol {
 	private static let cellInfo = [ "PerformerBioCell" : PrototypeCellInfo("PerformerBioCell") ]
	override class var validReuseIDDict: [ String: PrototypeCellInfo ] { return cellInfo }
	
	@IBOutlet weak var nameLabel: UILabel!
	@IBOutlet weak var pronounLabel: UILabel!
	@IBOutlet weak var imageView: UIImageView!
	@IBOutlet weak var bioTextView: UITextView!
	@IBOutlet weak var yearsAttendedLabel: UILabel!
	@IBOutlet weak var yearsAttendedBox: UIView!
	@IBOutlet weak var yearsAttendedHeader: UILabel!
	
	@IBOutlet weak var websiteURL: UIButton!
	@IBOutlet weak var facebookURL: UIButton!
	@IBOutlet weak var instagramURL: UIButton!
	@IBOutlet weak var xURL: UIButton!
	@IBOutlet weak var youtubeURL: UIButton!
	
	override func awakeFromNib() {
		super.awakeFromNib()
		websiteURL.imageView?.tintColor = UIColor.white
		facebookURL.imageView?.tintColor = UIColor.white
		instagramURL.imageView?.tintColor = UIColor.white
		xURL.imageView?.tintColor = UIColor.black
		youtubeURL.imageView?.tintColor = UIColor.red
		
		imageView.layer.cornerRadius = 12
		yearsAttendedBox.layer.cornerRadius = 12
		yearsAttendedBox.layer.borderWidth = 1
		yearsAttendedBox.layer.borderColor = yearsAttendedHeader.backgroundColor?.cgColor
	}
	
	var model: Performer? {
		didSet {
			clearObservations()
			if let model = model {
				addObservation(model.tell(self, when: "name") { observer, observed in 
					observer.nameLabel.text = observed.name
				}?.execute())
				addObservation(model.tell(self, when: "pronouns") { observer, observed in 
					observer.pronounLabel.text = observed.pronouns
				}?.execute())
				addObservation(model.tell(self, when: "bio") { observer, observed in 
					var composed = ""
					if let bio = observed.bio, !bio.isEmpty{
						composed = "**About Me**\n\n\(bio)"
					}
					let markdown = SwiftyMarkdown(string: composed)
					markdown.body.fontName = "Helvetica-Regular"
					markdown.body.color = UIColor(named: "Kraken Label Text") ?? UIColor.black
					observer.bioTextView.attributedText = markdown.attributedString()
				}?.execute())
				addObservation(model.tell(self, when: "yearsAttended") { observer, observed in 
					observer.yearsAttendedLabel.text = observed.yearsAttended
				}?.execute())
				
				// Socials
				addObservation(model.tell(self, when: "website") { observer, observed in 
					observer.websiteURL.isHidden = observed.website?.count ?? 0 == 0
				}?.execute())
				addObservation(model.tell(self, when: "facebookURL") { observer, observed in 
					observer.facebookURL.isHidden = observed.facebookURL?.count ?? 0 == 0
				}?.execute())
				addObservation(model.tell(self, when: "instagramURL") { observer, observed in 
					observer.instagramURL.isHidden = observed.instagramURL?.count ?? 0 == 0
				}?.execute())
				addObservation(model.tell(self, when: "xURL") { observer, observed in 
					observer.xURL.isHidden = observed.xURL?.count ?? 0 == 0
				}?.execute())
				addObservation(model.tell(self, when: "youtubeURL") { observer, observed in 
					observer.youtubeURL.isHidden = observed.youtubeURL?.count ?? 0 == 0
				}?.execute())

				addObservation(model.tell(self, when: "imageFilename") { observer, observed in
					if let imageFilename = observed.imageFilename {
						ImageManager.shared.image(withSize:.medium, forKey: imageFilename) { image in
							observer.imageView.image = image ?? UserManager.shared.noAvatarImage
							observer.cellSizeChanged()
						}
					}
					else {
						observer.imageView.image = UserManager.shared.noAvatarImage
						observer.cellSizeChanged()
					}
				}?.execute())
				
			}
		}
	}
	
	@IBAction func websiteButtonHit(_ sender: Any) {
		if let urlString = model?.website, let url = URL(string: urlString) {
		    UIApplication.shared.open(url, options: [:], completionHandler: nil)
		}
	}
	
	@IBAction func facebookButtonHit(_ sender: Any) {
		if let urlString = model?.facebookURL, let url = URL(string: urlString) {
		    UIApplication.shared.open(url, options: [:], completionHandler: nil)
		}
	}
	
	@IBAction func instagramButtonHit(_ sender: Any) {
		if let urlString = model?.instagramURL, let url = URL(string: urlString) {
		    UIApplication.shared.open(url, options: [:], completionHandler: nil)
		}
	}
	
	@IBAction func xButtonHit(_ sender: Any) {
		if let urlString = model?.xURL, let url = URL(string: urlString) {
		    UIApplication.shared.open(url, options: [:], completionHandler: nil)
		}
	}
	
	@IBAction func youtubeButtonHit(_ sender: Any) {
		if let urlString = model?.youtubeURL, let url = URL(string: urlString) {
		    UIApplication.shared.open(url, options: [:], completionHandler: nil)
		}
	}
}

