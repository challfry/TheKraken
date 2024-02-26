import UIKit

@objc protocol ForumSearchBindingProtocol {
	var searchText: String { get set }
}

@objc class ForumSearchCellModel: BaseCellModel, ForumSearchBindingProtocol {
	override class var validReuseIDDict: [String: BaseCollectionViewCell.Type ] { 
		return [ "ForumSearchCell" : ForumSearchCell.self ] 
	}

	@objc dynamic var searchText: String = ""
	var searchAction: (String) -> Void
	
	init(searchAction: @escaping (String) -> Void) {
		self.searchAction = searchAction
		super.init(bindingWith: ForumSearchBindingProtocol.self)
	}
	
	func searchButtonTapped() {
		searchAction(searchText)
	}
}


class ForumSearchCell: BaseCollectionViewCell, ForumSearchBindingProtocol, UITextFieldDelegate {
	private static let cellInfo = [ "ForumSearchCell" : PrototypeCellInfo("ForumSearchCell") ]
	override class var validReuseIDDict: [ String: PrototypeCellInfo] { return ForumSearchCell.cellInfo }
	
	@IBOutlet weak var searchField: UITextField!
	@IBOutlet weak var searchButton: UIButton!
	
	var searchText: String = ""

	override func awakeFromNib() {
		// Font styling
		searchField.styleFor(.body)
		searchButton.styleFor(.body)
		
		searchField.text = searchText
		searchButton.isEnabled = !searchText.isEmpty
	}
	
	@IBAction func searchTextChanged(_ sender: Any) {
		searchButton.isEnabled = searchField.text?.isEmpty == false
		if let m = cellModel as? ForumSearchCellModel {
			m.searchText = searchField.text ?? ""
		}
	}
	
	@IBAction func searchButtonTapped(_ sender: Any) {
		if let m = cellModel as? ForumSearchCellModel {
			searchField.resignFirstResponder()
			m.searchText = searchField.text ?? ""
			m.searchButtonTapped()
		}
	}
	
// MARK: Text Field Delegate
	func textFieldDidBeginEditing(_ textField: UITextField) {
		if let vc = viewController as? BaseCollectionViewController {
			vc.textViewBecameActive(searchField, inCell: self)
		}
	}

	func textFieldDidEndEditing(_ textField: UITextField, reason: UITextField.DidEndEditingReason) {
		if let vc = viewController as? BaseCollectionViewController {
			vc.textViewResignedActive(searchField, inCell: self)
		}
	}


	func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
		var textFieldContents = textField.text ?? ""
		let swiftRange: Range<String.Index> = Range(range, in: textFieldContents)!
		textFieldContents.replaceSubrange(swiftRange, with: string)
		
		searchButton.isEnabled = !textFieldContents.isEmpty
		if let m = cellModel as? ForumSearchCellModel {
			m.searchText = textFieldContents
		}
		
		return true
	}
	
	func textFieldShouldClear(_ textField: UITextField) -> Bool {
		// We'd need a flag for when the search cell should perform a search on clear
		return true
	}
}
