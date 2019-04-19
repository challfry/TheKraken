//
//  BaseCollectionViewCell.swift
//  Kraken
//
//  Created by Chall Fry on 4/16/19.
//  Copyright © 2019 Chall Fry. All rights reserved.
//

import UIKit

protocol CellModelProtocol {
	associatedtype Cell
	var storyboardId: String { get set }
	func makeCell(for collectionView: UICollectionView, indexPath: IndexPath) -> UICollectionViewCell
	func cellTapped()
}

extension CellModelProtocol where Cell: BaseCollectionViewCell, Self: BaseCollectionViewCell.BaseCellModel {
	func makeCell(for collectionView: UICollectionView, indexPath: IndexPath) -> UICollectionViewCell {
		let cell = collectionView.dequeueReusableCell(withReuseIdentifier: storyboardId, for: indexPath) as! Cell
		cell.setCellModel(newModel: self)
		return cell
	}
	
}

class BaseCollectionViewCell: UICollectionViewCell {
	var observations = [EBNObservation]()
	    
	class BaseCellModel: CellModelProtocol {
		typealias Cell = BaseCollectionViewCell
		var storyboardId = ""

		func cellTapped() {
			// Do nothing by default
		}

	}
	var cellModel: BaseCellModel?
	func setCellModel(newModel: BaseCellModel) { cellModel = newModel }

	override func preferredLayoutAttributesFitting(_ layoutAttributes: UICollectionViewLayoutAttributes) 
			-> UICollectionViewLayoutAttributes {
		setNeedsLayout()
		layoutIfNeeded()
		let size = contentView.systemLayoutSizeFitting(layoutAttributes.size)
		var frame = layoutAttributes.frame
		frame.size.height = ceil(size.height)
		layoutAttributes.frame = frame
//		print(frame)
		return layoutAttributes
	}
	
	func addObservation(_ observation: EBNObservation?) {
		guard let obs = observation else { return }
		
		observations.append(obs)
	}
	
	func clearObservations() {
		observations.forEach { $0.stopObservations() } 
	}

	override func prepareForReuse() {
		super.prepareForReuse()
		clearObservations()
	}
}
