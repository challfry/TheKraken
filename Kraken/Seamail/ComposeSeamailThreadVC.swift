//
//  ComposeSeamailThreadVC.swift
//  Kraken
//
//  Created by Chall Fry on 7/8/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit

class ComposeSeamailThreadVC: BaseCollectionViewController {
	// PostOp for thread creation

	let dataManager = SeamailDataManager.shared
	let composeDataSource = FilteringDataSource()
 
 // Recipient Chooser textfield?
 // Recipient List smallUser cells?
	var subjectCell: TextFieldCellModel?
	var messageCell: TextViewCellModel?
	var postButtonCell: ButtonCellModel?
	var postStatusCell: OperationStatusCellModel?
	
	
	override func viewDidLoad() {
        super.viewDidLoad()
        title = "New Seamail"

		composeDataSource.register(with: collectionView, viewController: self)
		let composeSection = composeDataSource.appendSection(named: "ComposeSection")
		subjectCell = TextFieldCellModel("Subject:")
		composeSection.append(subjectCell!)
		
		messageCell = TextViewCellModel("Initial Message:")
		composeSection.append(messageCell!)
		
		postButtonCell = ButtonCellModel()
		postButtonCell!.setupButton(2, title:"Post", action: postAction)
		composeSection.append(postButtonCell!)

        let statusCell = OperationStatusCellModel()
        statusCell.shouldBeVisible = false
        statusCell.showSpinner = true
        statusCell.statusText = "Sending..."
        postStatusCell = statusCell
    }
    

    func postAction() {

	}
	
	/*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destination.
        // Pass the selected object to the new view controller.
    }
    */

}
