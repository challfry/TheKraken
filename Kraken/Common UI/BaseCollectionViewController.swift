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
			
			NotificationCenter.default.addObserver(self, selector: #selector(BaseCollectionViewController.keyboardWillShow(notification:)), 
					name: UIResponder.keyboardDidShowNotification, object: nil)
		    NotificationCenter.default.addObserver(self, selector: #selector(BaseCollectionViewController.keyboardWillHide(notification:)), 
					name: UIResponder.keyboardDidHideNotification, object: nil)

		}
    }
        
    @objc func keyboardWillShow(notification: NSNotification) {
		if let keyboardHeight = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue.height {
			collectionView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: keyboardHeight, right: 0)
		}
	}

	@objc func keyboardWillHide(notification: NSNotification) {
		UIView.animate(withDuration: 0.2, animations: {
			self.collectionView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
		})
	}

}
