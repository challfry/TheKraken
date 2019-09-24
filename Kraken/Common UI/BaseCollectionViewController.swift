//
//  BaseCollectionViewController.swift
//  Kraken
//
//  Created by Chall Fry on 4/27/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit

class BaseCollectionViewController: UIViewController {
	@IBOutlet var collectionView: UICollectionView!
	@objc dynamic var activeTextEntry: UITextInput?
		
	var customGR: UILongPressGestureRecognizer?
	var tappedCell: UICollectionViewCell?
	var indexPathToScrollToVisible: IndexPath?

    override func viewDidLoad() {
        super.viewDidLoad()
     	let keyboardCanceler = UITapGestureRecognizer(target: view, action: #selector(UIView.endEditing(_:)))
 //    	keyboardCanceler.cancelsTouchesInView = false
	 	view.addGestureRecognizer(keyboardCanceler)
               
 		if let layout = collectionView.collectionViewLayout as? UICollectionViewFlowLayout {
			layout.itemSize = UICollectionViewFlowLayout.automaticSize
			let width = self.view.frame.size.width
			layout.estimatedItemSize = CGSize(width: width, height: 52 )
			
			layout.minimumLineSpacing = 0
		}
 
		NotificationCenter.default.addObserver(self, selector: #selector(BaseCollectionViewController.keyboardWillShow(notification:)), 
				name: UIResponder.keyboardDidShowNotification, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(BaseCollectionViewController.keyboardDidShowNotification(notification:)), 
				name: UIResponder.keyboardDidShowNotification, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(BaseCollectionViewController.keyboardWillHide(notification:)), 
				name: UIResponder.keyboardDidHideNotification, object: nil)
   }
        
    @objc func keyboardWillShow(notification: NSNotification) {
		if let keyboardHeight = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue.height {
			collectionView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: keyboardHeight, right: 0)
		}
	}

    @objc func keyboardDidShowNotification(notification: NSNotification) {
    	if let indexPath = indexPathToScrollToVisible {
			collectionView.scrollToItem(at: indexPath, at: .centeredVertically, animated: true)
		}
	}

	@objc func keyboardWillHide(notification: NSNotification) {
		UIView.animate(withDuration: 0.2, animations: {
			self.collectionView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
		})
	}
	
	func textViewBecameActive(_ field: UITextInput, inCell: BaseCollectionViewCell) {
		activeTextEntry = field
		if let indexPath = collectionView.indexPath(for: inCell) {
			indexPathToScrollToVisible = indexPath
		}
	}
	
	func textViewResignedActive(_ field: UITextInput, inCell: BaseCollectionViewCell) {
		activeTextEntry = nil
		indexPathToScrollToVisible = nil
	}

}

extension BaseCollectionViewController: UIGestureRecognizerDelegate {

	func setupGestureRecognizer() {	
		let tapper = UILongPressGestureRecognizer(target: self, action: #selector(BaseCollectionViewController.cellTapped))
		tapper.minimumPressDuration = 0.05
		tapper.numberOfTouchesRequired = 1
		tapper.numberOfTapsRequired = 0
		tapper.allowableMovement = 10.0
		tapper.delegate = self
		tapper.name = "BaseCollectionViewController Long Press"
		collectionView.addGestureRecognizer(tapper)
		customGR = tapper
	}

	func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
		// need to call super if it's not our recognizer
		if gestureRecognizer != customGR {
			return false
		}
		let hitPoint = gestureRecognizer.location(in: collectionView)
		if !collectionView.point(inside:hitPoint, with: nil) {
			return false
		}
		
		// Only take the tap if the cell isn't already selected. This ensures taps on widgets inside the cell go through
		// once the cell is selected.
		if let path = collectionView.indexPathForItem(at: hitPoint), let cell = collectionView.cellForItem(at: path),
				let c = cell as? BaseCollectionViewCell, !c.privateSelected {
			return true
		}
		
		return false
	}

	@objc func cellTapped(_ sender: UILongPressGestureRecognizer) {
		if sender.state == .began {
			if let indexPath = collectionView.indexPathForItem(at: sender.location(in:collectionView)) {
				tappedCell = collectionView.cellForItem(at: indexPath)
				tappedCell?.isHighlighted = true
			}
			else {
				tappedCell = nil
			}
		}
		guard let tappedCell = tappedCell else { return }
		
		if sender.state == .changed {
			tappedCell.isHighlighted = tappedCell.point(inside:sender.location(in: tappedCell), with: nil)
		}
		else if sender.state == .ended {
			if tappedCell.isHighlighted {				
				if let tc = tappedCell as? BaseCollectionViewCell {
					tc.privateSelectCell()
				}
			}
		} 
		
		if sender.state == .ended || sender.state == .cancelled || sender.state == .failed {
			tappedCell.isHighlighted = false
			
			// Stop the scroll view's odd scrolling behavior that happens when cell tap resizes the cell.
			collectionView.setContentOffset(collectionView.contentOffset, animated: false)
		}
	}
	
}

