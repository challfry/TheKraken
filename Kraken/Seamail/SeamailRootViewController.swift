//
//  SeamailRootViewController.swift
//  Kraken
//
//  Created by Chall Fry on 3/29/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit

//class SeamailRootViewController: UITableViewController {
class SeamailRootViewController: UIViewController, UICollectionViewDelegate, UICollectionViewDataSource {
	@IBOutlet weak var collectionView: UICollectionView!
	
    override func viewDidLoad() {
        super.viewDidLoad()

  // 	tableView.registerNib(UINib(nibName: "MyCell", bundle: nil), forCellWithReuseIdentifier: "cell")
    }
    

    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destination.
        // Pass the selected object to the new view controller.
    }
    */
	
	func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
		return 1
	}
	    
	func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
		let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "login3", for: indexPath)
		return cell
	}
	


}
