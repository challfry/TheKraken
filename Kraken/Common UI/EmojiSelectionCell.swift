//
//  EmojiSelectionCell.swift
//  Kraken
//
//  Created by Chall Fry on 5/27/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit

@objc protocol EmojiSelectionCellProtocol {
	
}

@objc class EmojiSelectionCellModel: BaseCellModel, EmojiSelectionCellProtocol {
	private static let validReuseIDs = [ "EmojiSelectionCell" : EmojiSelectionCell.self ]
	override class var validReuseIDDict: [String: BaseCollectionViewCell.Type ] { return validReuseIDs }
	
	var textToPasteCallback: (String?) -> Void

	init(paster: @escaping (String?) -> Void) {
		textToPasteCallback = paster
		super.init(bindingWith: EmojiSelectionCellProtocol.self)
	}
	
}

class EmojiSelectionCell: BaseCollectionViewCell, EmojiSelectionCellProtocol, UICollectionViewDataSource, UICollectionViewDelegate {
	@IBOutlet weak var emojiCollection: UICollectionView!
	private static let cellInfo = [ "EmojiSelectionCell" : PrototypeCellInfo("EmojiSelectionCell") ]
	override class var validReuseIDDict: [ String: PrototypeCellInfo ] { return cellInfo }

	@objc dynamic var buttonEnableState: Bool = false

//	let items = ["😂", "😭", "😍", "❤️", "👉", "💜", ",💕", "😊", "🤔", "🙏", "⌚️", "❤️", "🏁", "🇩🇿" ]
	let items = [ "😂", "❤️", "♻️", "😍", "♥️", "😭", "😊", "😒", "💕", "😘", "😩", "☺️", "👌", "😔", "😁", "😏", "😉", 
			"👍", "⬅️", "😅", "🙏", "😌", "😢", "👀", "💔", "😎", "🎶", "💙", "💜", "🙌", "😳", "✨", "💖", "🙈", "💯", 
			"🔥", "✌️", "😄", "😴", "😑", "😋", "😜", "😕", "😞", "😪", "💗", "👏", "😐", "👉", "💞", "💘", "📷", "😱", 
			"💛", "🌹", "💁", "🌸", "💋", "😡", "🙊", "💀", "😆", "😀", "😈", "🎉", "💪", "😃", "✋", "😫", "▶️", "😝", 
			"💚", "😤", "💓", "🌚", "👊", "✔️", "➡️", "😣", "😓", "☀️", "😻", "😇", "😬", "😥", "✅", "👈", "😛"]
			
	override func awakeFromNib() {
		super.awakeFromNib()
		emojiCollection.register(EmojiButtonCell.self, forCellWithReuseIdentifier: "EmojiButton")
		
		self.tell(self, when: "viewController.activeTextEntry") { observer, observed in 
			observer.buttonEnableState = observed.viewController?.activeTextEntry != nil
		}
	}
	
	func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
		return items.count
	}
	
	func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
		let cell = emojiCollection.dequeueReusableCell(withReuseIdentifier: "EmojiButton", for: indexPath) as! EmojiButtonCell 
		cell.emoji = items[indexPath.row]
		cell.ownerCell = self
		return cell
	}
	
	func buttonTapped(withString: String?) {
		if let model = cellModel as? EmojiSelectionCellModel {
			model.textToPasteCallback(withString)
		}
	}
}

@objc class EmojiButtonCell: UICollectionViewCell {
	@objc dynamic var ownerCell: EmojiSelectionCell?
	var emojiButton = UIButton()
	var emoji: String? {
		didSet {
			if let em = emoji {
				emojiButton.setImage(emojiImage(for:em), for: .normal)
			}
		}
	}
	
	override init(frame: CGRect) {
		super.init(frame: frame)
		emojiButton.frame = self.bounds
		addSubview(emojiButton)
		emojiButton.addTarget(self, action:#selector(buttonHit), for:.touchUpInside)
//		emojiButton.showsTouchWhenHighlighted = true
		emojiButton.adjustsImageWhenHighlighted = true
		emojiButton.adjustsImageWhenDisabled = true
		emojiButton.setBackgroundImage(UIImage(named:"BlueButtonHighlight"), for: .highlighted)

		self.tell(self, when:"ownerCell.buttonEnableState") { observer, observed in 
			if let enableState = observed.ownerCell?.buttonEnableState {
				observer.emojiButton.isEnabled = enableState
			}
		}?.schedule()
	}
	
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc func buttonHit() {
    	ownerCell?.buttonTapped(withString:emoji)
    }
    
    func emojiImage(for emoji: String) -> UIImage {
		UIGraphicsBeginImageContextWithOptions(CGSize(width: 30, height: 30), false, 0.0)
		let str = emoji as NSString
		str.draw(at:CGPoint(x: -1.5, y: -3.0), withAttributes: [.font : UIFont.systemFont(ofSize: 30.0) ])
		let resultImage = UIGraphicsGetImageFromCurrentImageContext()
    	UIGraphicsEndImageContext()
    	return resultImage ?? UIImage()
    }
}


