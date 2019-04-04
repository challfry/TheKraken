//
//  TwitarrViewController.swift
//  Kraken
//
//  Created by Chall Fry on 3/22/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit

class TwitarrViewController: UIViewController, UICollectionViewDelegate, UICollectionViewDataSource, 
		UICollectionViewDelegateFlowLayout {

	@IBOutlet var collectionView: UICollectionView!

    override func viewDidLoad() {
        super.viewDidLoad()
        
		if let layout = collectionView.collectionViewLayout as? UICollectionViewFlowLayout {
			layout.itemSize = UICollectionViewFlowLayout.automaticSize
			layout.estimatedItemSize = CGSize(width: 375, height: 52 )
			
			layout.minimumLineSpacing = 0
		}

        // Do any additional setup after loading the view.
		TwitarrDataManager.shared.loadNewestTweets() {
			DispatchQueue.main.async {
				self.collectionView.reloadData()
			}
		}
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
		return TwitarrDataManager.shared.totalTweets
	}
	
    /*
    	In cellForItemAt:
    	Save the index path of the last cell we built, the tweet attached to the cell, and
    	the chunk and index of that tweet. 
    	
		If the tweet is still at the same location, we should be able to do index math and get the loc
		for the tweet the new cell should use. If it isn't, we should be able to use the tweet's timestamp,
		find the nearest tweet, and do index math from that.
    */
    
	func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
		let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "tweet", for: indexPath) as! TwitarrTweetCell

		if let index = indexPath.last {
			cell.tweetModel = TwitarrDataManager.shared.tweetStream[0].tweets[index]
		}

		return cell
	}

}
