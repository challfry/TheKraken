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

	init() {
		super.init(bindingWith: EmojiSelectionCellProtocol.self)
	}

}

class EmojiSelectionCell: BaseCollectionViewCell, EmojiSelectionCellProtocol, UICollectionViewDataSource, UICollectionViewDelegate {
	@IBOutlet weak var emojiCollection: UICollectionView!
	private static let cellInfo = [ "EmojiSelectionCell" : PrototypeCellInfo("EmojiSelectionCell") ]
	override class var validReuseIDDict: [ String: PrototypeCellInfo ] { return cellInfo }

//	let items = ["😂", "😭", "😍", "❤️", "👉", "💜", ",💕", "😊", "🤔", "🙏", "⌚️", "❤️", "🏁", "🇩🇿" ]
	let items = [ "😂", "❤️", "♻️", "😍", "♥️", "😭", "😊", "😒", "💕", "😘", "😩", "☺️", "👌", "😔", "😁", "😏", "😉", 
			"👍", "⬅️", "😅", "🙏", "😌", "😢", "👀", "💔", "😎", "🎶", "💙", "💜", "🙌", "😳", "✨", "💖", "🙈", "💯", 
			"🔥", "✌️", "😄", "😴", "😑", "😋", "😜", "😕", "😞", "😪", "💗", "👏", "😐", "👉", "💞", "💘", "📷", "😱", 
			"💛", "🌹", "💁", "🌸", "💋", "😡", "🙊", "💀", "😆", "😀", "😈", "🎉", "💪", "😃", "✋", "😫", "▶️", "😝", 
			"💚", "😤", "💓", "🌚", "👊", "✔️", "➡️", "😣", "😓", "☀️", "😻", "😇", "😬", "😥", "✅", "👈", "😛"]
			
	override func awakeFromNib() {
		super.awakeFromNib()
		emojiCollection.register(EmojiButtonCell.self, forCellWithReuseIdentifier: "EmojiButton")
	}
	
	func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
		return items.count
	}
	
	func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
		let cell = emojiCollection.dequeueReusableCell(withReuseIdentifier: "EmojiButton", for: indexPath) as! EmojiButtonCell 
		cell.emoji = items[indexPath.row]
		return cell
	}
	
}

class EmojiButtonCell: UICollectionViewCell {
	var emojiButton = UIButton()
	var emoji: String? {
		didSet {
			emojiButton.setTitle(emoji, for: .normal)
		}
	}
	
	override init(frame: CGRect) {
		super.init(frame: frame)
		emojiButton.frame = self.bounds
		addSubview(emojiButton)
		emojiButton.addTarget(self, action:#selector(buttonHit), for:.touchUpInside)
//		emojiButton.backgroundColor = UIColor.green
		emojiButton.titleLabel?.font = UIFont.systemFont(ofSize: 30.0)
	}
	
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc func buttonHit() {
    	print("button hit")
    }
}


