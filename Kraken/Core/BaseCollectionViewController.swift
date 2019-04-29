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
		
    override func viewDidLoad() {
        super.viewDidLoad()
     	view.addGestureRecognizer(UITapGestureRecognizer(target: view, action: #selector(UIView.endEditing(_:))))
               
 		if let layout = collectionView.collectionViewLayout as? UICollectionViewFlowLayout {
			layout.itemSize = UICollectionViewFlowLayout.automaticSize
			let width = self.view.frame.size.width
			layout.estimatedItemSize = CGSize(width: width, height: 52 )
			
			layout.minimumLineSpacing = 0
		}
    }

}
