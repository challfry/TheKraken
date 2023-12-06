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
	
	let textToPasteCallback: (String?) -> Void

	init(paster: @escaping (String?) -> Void) {
		textToPasteCallback = paster
		super.init(bindingWith: EmojiSelectionCellProtocol.self)
	}
	
}

class EmojiSelectionCell: BaseCollectionViewCell, EmojiSelectionCellProtocol, UICollectionViewDataSource, UICollectionViewDelegate {
	@IBOutlet weak var emojiCollection: UICollectionView!
	@IBOutlet weak var cellHeightConstraint: NSLayoutConstraint!
	private static let cellInfo = [ "EmojiSelectionCell" : PrototypeCellInfo("EmojiSelectionCell") ]
	override class var validReuseIDDict: [ String: PrototypeCellInfo ] { return cellInfo }

	@objc dynamic var buttonEnableState: Bool = false

//	let items = ["😂", "😭", "😍", "❤️", "👉", "💜", ",💕", "😊", "🤔", "🙏", "⌚️", "❤️", "🏁", "🇩🇿" ]
	let jocomoji = [ ":buffet:", ":die-ship:", ":die:", ":fez:", ":hottub:", ":joco:", ":pirate:", ":ship-front:",
			":ship:", ":towel-monkey:", ":tropical-drink:", ":zombie:" ]
	let starterEmoji = [ "😂", "❤️", "♻️", "😍", "♥️", "😭", "😊", "😒", "💕", "😘", "😩", "☺️", "👌", "😔", "😁", "😏", "😉", 
			"👍", "⬅️", "😅", "🙏", "😌", "😢", "👀", "💔", "😎", "🎶", "💙", "💜", "🙌", "😳", "✨", "💖", "🙈", "💯", 
			"🔥", "✌️", "😄", "😴", "😑", "😋", "😜", "😕", "😞", "😪", "💗", "👏", "😐", "👉", "💞", "💘", "📷", "😱", 
			"💛", "🌹", "💁", "🌸", "💋", "😡", "🙊", "💀", "😆", "😀", "😈", "🎉", "💪", "😃", "✋", "😫", "▶️", "😝", 
			"💚", "😤", "💓", "🌚", "👊", "✔️", "➡️", "😣", "😓", "☀️", "😻", "😇", "😬", "😥", "✅", "👈", "😛"]
	
	lazy var items: [String] = {
		var allItems: [String] = EmojiDataManager.shared.recentEmoji
		allItems.append(contentsOf: self.jocomoji)
		allItems.append(contentsOf: self.starterEmoji)
		return allItems
	}()
			
	override func awakeFromNib() {
		super.awakeFromNib()
		EmojiDataManager.shared.getRecentlyUsedEmoji()
		emojiCollection.register(EmojiButtonCell.self, forCellWithReuseIdentifier: "EmojiButton")
		(emojiCollection.collectionViewLayout as? UICollectionViewFlowLayout)?.itemSize = CGSize(width: 41, height: 41)
		cellHeightConstraint.constant = 41 * 3
		
		self.tell(self, when: "viewController.activeTextEntry") { observer, observed in 
			if let vc = observed.viewController as? BaseCollectionViewController {
				observer.buttonEnableState = vc.activeTextEntry != nil
			}
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

@objc class EmojiButtonCell: UICollectionViewCell, UIGestureRecognizerDelegate, UIPopoverPresentationControllerDelegate {
	@objc dynamic weak var ownerCell: EmojiSelectionCell?
	var emojiButton = UIButton()
	var emoji: String? {
		didSet {
			if let em = emoji {
				emojiButton.setImage(emojiImage(for:em), for: .normal)
			}
			else {
				emojiButton.setImage(nil, for: .normal)
			}
		}
	}
	
	override init(frame: CGRect) {
		super.init(frame: frame)
		
		emojiButton.frame = self.bounds
		emojiButton.addTarget(self, action:#selector(buttonTapStart), for:.touchDown)
		emojiButton.addTarget(self, action:#selector(buttonTapEnd), for:.touchUpOutside)
		emojiButton.addTarget(self, action:#selector(buttonTapEnd), for:.touchCancel)
		emojiButton.addTarget(self, action:#selector(buttonHit), for:.touchUpInside)
		emojiButton.setBackgroundImage(UIImage(named:"BlueButtonHighlight"), for: .highlighted)
		addSubview(emojiButton)

		let longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(showEmojiOptions))
		longPressGesture.minimumPressDuration = 0.7
		longPressGesture.numberOfTapsRequired = 0
		longPressGesture.delegate = self
		longPressGesture.cancelsTouchesInView = true
		emojiButton.addGestureRecognizer(longPressGesture)

		self.tell(self, when:"ownerCell.buttonEnableState") { observer, observed in 
			if let enableState = observed.ownerCell?.buttonEnableState {
				observer.emojiButton.isEnabled = enableState
			}
		}?.schedule()
	}
	
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc func buttonTapStart() {
    	if let vc = ownerCell?.viewController as? BaseCollectionViewController {
    		vc.enableKeyboardCanceling = false
    	}
    }
    
    @objc func buttonHit() {
    	ownerCell?.buttonTapped(withString:emoji)
    	if let vc = ownerCell?.viewController as? BaseCollectionViewController {
    		vc.enableKeyboardCanceling = true
    	}
    }
    
    @objc func buttonTapEnd() {
    	if let vc = ownerCell?.viewController as? BaseCollectionViewController {
    		vc.enableKeyboardCanceling = true
    	}
    }
    
    // Pure glue for the popup's buttons
    func buttonHitInPopup(withString: String) {
		ownerCell?.buttonTapped(withString:withString)
    }
    
    var emojiPopupVC: EmojiPopupViewController?
    @objc func showEmojiOptions(_ sender: UILongPressGestureRecognizer) {
		if sender.state == .began {
			if emojiPopupVC == nil {
				let storyboard = UIStoryboard(name: "Main", bundle: nil)
				let emojiPopup = storyboard.instantiateViewController(withIdentifier: "EmojiPopup") as? EmojiPopupViewController
				emojiPopupVC = emojiPopup
				
			}
			if let emojiPopup = emojiPopupVC, let vc = ownerCell?.viewController {
				emojiPopup.modalPresentationStyle = .popover
				emojiPopup.popoverPresentationController?.sourceView = self
				emojiPopup.popoverPresentationController?.sourceRect = CGRect(x: self.bounds.width / 2 - 1, y: 0, width: 1, height: self.bounds.height)
				emojiPopup.popoverPresentationController?.permittedArrowDirections = .down
				emojiPopup.popoverPresentationController?.delegate = self
				emojiPopup.parentButtonCell = self
				emojiPopup.emoji = emoji
				vc.present(emojiPopup, animated: true, completion: nil)
			}
		}
    }
    
    func emojiImage(for emoji: String) -> UIImage {
    	if emoji.hasPrefix(":") {
    		let imageName = emoji.dropFirst(1).dropLast(1).appending(".png")
    		return UIImage(named: imageName) ?? UIImage()
    	}
		let imgSize = CGSize(width: self.bounds.size.width - 6, height: self.bounds.size.height - 6)
		UIGraphicsBeginImageContextWithOptions(CGSize(width: imgSize.width, height: imgSize.height), false, 0.0)
		let str = emoji as NSString
		str.draw(at:CGPoint(x: -1.5, y: -3.0), withAttributes: [.font : UIFont.systemFont(ofSize: imgSize.height) ])
		let resultImage = UIGraphicsGetImageFromCurrentImageContext()
    	UIGraphicsEndImageContext()
    	return resultImage ?? UIImage()
    }
    
	override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
		if let unicodeValue = emoji?.unicodeScalars.first {
			return unicodeValue.properties.isEmojiModifierBase
		}
		return false
	}
    
	func adaptivePresentationStyle(for controller: UIPresentationController) -> UIModalPresentationStyle {
		return .none
	}
	
	override func prepareForReuse() {
		super.prepareForReuse()
		emoji = nil
	}
}


class EmojiPopupViewController: UIViewController {
	@IBOutlet var stackView: UIStackView!
	@IBOutlet var button1: UIButton!
	@IBOutlet var button2: UIButton!
	@IBOutlet var button3: UIButton!
	@IBOutlet var button4: UIButton!
	@IBOutlet var button5: UIButton!
	@IBOutlet var button6: UIButton!
	
	weak var parentButtonCell: EmojiButtonCell?
	static let swatches = [ "", "\u{1F3FB}", "\u{1F3FC}", "\u{1F3FD}", "\u{1F3FE}",  "\u{1F3FF}" ]
	
	var emoji: String? {
		didSet {
			setupButtons()
		}
	}
	
	override func viewDidLoad() {
		setupButtons()
	}
	
	var alreadySetupButtons = false
	func setupButtons() {
		guard isViewLoaded, !alreadySetupButtons else { return }
		alreadySetupButtons = true
		
		// Heh. No binding IBOutlets into arrays.
		setupButton(button: button1, index: 0)
		setupButton(button: button2, index: 1)
		setupButton(button: button3, index: 2)
		setupButton(button: button4, index: 3)
		setupButton(button: button5, index: 4)
		setupButton(button: button6, index: 5)
	}
	
	func setupButton(button: UIButton, index: Int) {
		if let em = emoji {
			button.setImage(parentButtonCell?.emojiImage(for:em + EmojiPopupViewController.swatches[index]), for: .normal)
		}
	}
	
	@IBAction func buttonTapped(sender: UIButton) {
		if let emojiChar = emoji {
			var emojiCompoundString: String
			if sender === button1 { emojiCompoundString = emojiChar + EmojiPopupViewController.swatches[0] }
			else if sender === button2 { emojiCompoundString = emojiChar + EmojiPopupViewController.swatches[1] }
			else if sender === button3 { emojiCompoundString = emojiChar + EmojiPopupViewController.swatches[2] }
			else if sender === button4 { emojiCompoundString = emojiChar + EmojiPopupViewController.swatches[3] }
			else if sender === button5 { emojiCompoundString = emojiChar + EmojiPopupViewController.swatches[4] }
			else if sender === button6 { emojiCompoundString = emojiChar + EmojiPopupViewController.swatches[5] }
			else { emojiCompoundString = emojiChar }
				
			parentButtonCell?.buttonHitInPopup(withString: emojiCompoundString)
			dismiss(animated: true, completion: nil)
		}
	}

}
