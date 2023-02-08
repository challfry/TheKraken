//
//  PopupCell.swift
//  Kraken
//
//  Created by Chall Fry on 2/2/23.
//  Copyright © 2023 Chall Fry. All rights reserved.
//

import Foundation
import UIKit
import CoreData

@objc protocol PopupCellBindingProtocol: KrakenCellBindingProtocol {
	var title: String { get set}
	var buttonTitle: String { get set }
	var menuPrompt: String { get set }
	var menuItems: [String] { get set}
	var selectedMenuItem: Int  { get set}
	var singleSelectionMode: Bool { get set }
}

@objc class PopupCellModel: BaseCellModel, PopupCellBindingProtocol {
	override class var validReuseIDDict: [String: BaseCollectionViewCell.Type ] { return [ "PopupCell" : PopupCell.self ] }

	dynamic var title: String = ""
	dynamic var buttonTitle: String = ""
	dynamic var menuPrompt: String = ""
	dynamic var menuItems: [String] = []
	dynamic var selectedMenuItem: Int = 0 
	dynamic var singleSelectionMode: Bool = true
	
	init(title: String, menuPrompt: String, menuItems: [String], singleSelectionMode: Bool = true) {
		self.title = title
		self.menuPrompt = menuPrompt
		self.menuItems = menuItems
		selectedMenuItem = 0
		self.singleSelectionMode = singleSelectionMode
		super.init(bindingWith: PopupCellBindingProtocol.self)
	}
	
	func selectedMenuTitle() -> String {
		if selectedMenuItem >= 0,  selectedMenuItem < menuItems.count {
			return menuItems[selectedMenuItem]
		}
		else if !menuItems.isEmpty {
			return menuItems[0]
		}
		return ""
	}
}

class PopupCell: BaseCollectionViewCell, PopupCellBindingProtocol {
	private static let cellInfo = [ "PopupCell" : PrototypeCellInfo("PopupCell") ]
	override class var validReuseIDDict: [ String: PrototypeCellInfo] { return PopupCell.cellInfo }
	
	@IBOutlet weak var popupButton: UIButton!
	@IBOutlet weak var titleLabel: UILabel!
	
	var title: String = "" {
		didSet { titleLabel.text = title }
	}
	var buttonTitle: String = "" {
		didSet { popupButton.setTitle(buttonTitle, for: .normal) }
	}
	var menuPrompt: String = "" {
		didSet { buildMenu() }
	}
	var singleSelectionMode: Bool = true {
		didSet { buildMenu() }
	}
	var menuItems: [String] = [] {
		didSet { buildMenu() }
	}
	var selectedMenuItem: Int = 0 {
		didSet { 
			if let menu = popupButton.menu, menu.children.count > selectedMenuItem, let action = menu.children[selectedMenuItem] as? UIAction,
					action.state != .on {
				action.state = .on
			}
		}
	}
		
	func buildMenu() {
		let items = menuItems.map { UIAction(title: $0, handler: { [weak self] action in 
			if let self = self, let model = self.cellModel as? PopupCellBindingProtocol {
				model.selectedMenuItem = self.popupButton.menu?.children.firstIndex(of: action) ?? 0
			}
		}) }
		if singleSelectionMode && !items.isEmpty {
			if selectedMenuItem < items.count {
				items[selectedMenuItem].state = .on
			}
			else {
				items[0].state = .on 
			}
		}
		popupButton.changesSelectionAsPrimaryAction = singleSelectionMode
		popupButton.menu = UIMenu(title: menuPrompt, options: singleSelectionMode ? .singleSelection : [], children: items)
	}
}

