//
//  TerminalViewController.swift
//  OpenTerm
//
//  Created by Louis D'hauwe on 07/12/2017.
//  Copyright © 2017 Silver Fox. All rights reserved.
//

import Foundation
import CoreFoundation
import Darwin
import UIKit
import ios_system
import PanelKit
import StoreKit
import MobileCoreServices

class TerminalViewController: UIViewController {

	let terminalView: TerminalView

	let contentWrapperView: UIView

	let historyViewController: HistoryViewController
	var historyPanelViewController: PanelViewController!

	let scriptsViewController: ScriptsViewController
	var scriptsPanelViewController: PanelViewController!

	var bookmarkViewController: BookmarkViewController!
	var bookmarkPanelViewController: PanelViewController!

	var cubPanels = [PanelViewController]()
	
	private var overflowItems: [OverflowItem] = [] {
		didSet {
			applyOverflowState()
		}
	}
	
	private var overflowState: OverflowState = .compact {
		didSet {
			applyOverflowState()
		}
	}

	var overflowItem: UIBarButtonItem!

	init() {
		terminalView = TerminalView()
		contentWrapperView = UIView()

		let storyboard = UIStoryboard(name: "Main", bundle: nil)
		historyViewController = storyboard.instantiateViewController(withIdentifier: "HistoryViewController") as! HistoryViewController
		scriptsViewController = storyboard.instantiateViewController(withIdentifier: "ScriptsViewController") as! ScriptsViewController
		bookmarkViewController = storyboard.instantiateViewController(withIdentifier: "BookmarkViewController") as! BookmarkViewController

		super.init(nibName: nil, bundle: nil)
		
		scriptsViewController.panelManager = self

		let openFolderItem = OverflowItem(visibleInBar: true, icon: #imageLiteral(resourceName: "Open"), title: "Open", action: { [weak self] sender in
			self?.showDocumentPicker(sender)
		})
		
		let bookmarksItem = OverflowItem(visibleInBar: true, icon: #imageLiteral(resourceName: "Bookmarks"), title: "Bookmarks", action: { [weak self] sender in
			self?.showBookmarks(sender)
		})
		
		let historyItem = OverflowItem(visibleInBar: true, icon: #imageLiteral(resourceName: "History"), title: "History", action: { [weak self] sender in
			self?.showHistory(sender)
		})
		
		let scriptsItem = OverflowItem(visibleInBar: true, icon: #imageLiteral(resourceName: "Script"), title: "Scripts", action: { [weak self] sender in
			self?.showScripts(sender)
		})

		overflowItems = [
			openFolderItem,
			bookmarksItem,
			historyItem,
			scriptsItem
		]

		historyPanelViewController = PanelViewController(with: historyViewController, in: self)
		historyPanelViewController.panelNavigationController.view.backgroundColor = .panelBackgroundColor
		historyPanelViewController.view.backgroundColor = .clear
		
		scriptsPanelViewController = PanelViewController(with: scriptsViewController, in: self)
		scriptsPanelViewController.panelNavigationController.view.backgroundColor = .panelBackgroundColor
		scriptsPanelViewController.view.backgroundColor = .clear

		bookmarkPanelViewController = PanelViewController(with: bookmarkViewController, in: self)
		bookmarkPanelViewController.panelNavigationController.view.backgroundColor = .panelBackgroundColor
		bookmarkPanelViewController.view.backgroundColor = .clear

		historyViewController.delegate = self
		bookmarkViewController.delegate = self
		terminalView.delegate = self
		
		overflowItem = UIBarButtonItem(image: #imageLiteral(resourceName: "More"), style: .plain, target: self, action: #selector(showOverflowMenu(_:)))
	}

	required init?(coder aDecoder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	override func viewDidLoad() {
		super.viewDidLoad()

		// Content wrapper is root view
		contentWrapperView.translatesAutoresizingMaskIntoConstraints = false
		view.addSubview(contentWrapperView)
		
		NSLayoutConstraint.activate([
			contentWrapperView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			contentWrapperView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
			contentWrapperView.topAnchor.constraint(equalTo: view.layoutMarginsGuide.topAnchor),
			contentWrapperView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
			])

		contentWrapperView.backgroundColor = .black
		
		terminalView.translatesAutoresizingMaskIntoConstraints = false
		contentWrapperView.addSubview(terminalView)
		
		NSLayoutConstraint.activate([
			terminalView.leadingAnchor.constraint(equalTo: contentWrapperView.leadingAnchor),
			terminalView.trailingAnchor.constraint(equalTo: contentWrapperView.trailingAnchor),
			terminalView.topAnchor.constraint(equalTo: contentWrapperView.topAnchor),
			terminalView.bottomAnchor.constraint(equalTo: contentWrapperView.bottomAnchor)
			])
		
		updateTitle()

		NotificationCenter.default.addObserver(self, selector: #selector(didDismissKeyboard), name: UIResponder.keyboardDidHideNotification, object: nil)

		NotificationCenter.default.addObserver(self, selector: #selector(applicationDidEnterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)

		initializeEnvironment()
		replaceCommand("open-url", "openUrl", true)
		replaceCommand("share", "shareFile", true)
		replaceCommand("pbcopy", "pbcopy", true)
		replaceCommand("pbpaste", "pbpaste", true)
		replaceCommand("cub", "cub", true)
		replaceCommand("credits", "credits", true)
		replaceCommand("say", "say", true)
		replaceCommand("sleep", "sleepCMD", true)

		// Call reloadData for the added commands.
		terminalView.autoCompleteManager.reloadData()

		shareFileViewController = self // shareFile needs to know which view controller to present share sheet from

		setSSLCertIfNeeded()
	}

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)

		self.terminalView.becomeFirstResponder()

	}

	var didFirstLayout = false

	override func viewDidLayoutSubviews() {
		super.viewDidLayoutSubviews()

		if !didFirstLayout {
			restorePanelStatesFromDisk()

			didFirstLayout = true
		}

	}

	override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
		super.viewWillTransition(to: size, with: coordinator)

		coordinator.animate(alongsideTransition: { (_) in

		}, completion: { (_) in

			if !self.allowFloatingPanels {
				self.closeAllFloatingPanels()
			}

			if !self.allowPanelPinning {
				self.closeAllPinnedPanels()
			}

		})

	}

	override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
		super.traitCollectionDidChange(previousTraitCollection)

		self.overflowState = self.traitCollection.horizontalSizeClass == .compact ? .compact : .expanded
	}

	func setSSLCertIfNeeded() {

		guard let cString = getenv("SSL_CERT_FILE") else {
			return
		}

		guard let str = NSString(cString: cString, encoding: String.Encoding.utf8.rawValue) as String? else {
			return
		}

		let fileManager = DocumentManager.shared.fileManager

		if !fileManager.fileExists(atPath: str) {

			guard let url = Bundle.main.url(forResource: "cacert", withExtension: "pem") else {
				return
			}

			guard let data = try? Data(contentsOf: url) else {
				return
			}

			let certsFolderURL = DocumentManager.shared.activeDocumentsFolderURL.appendingPathComponent(".certs")

			let iCloudURL = certsFolderURL.appendingPathComponent("cacert.pem.icloud")
			
			if fileManager.fileExists(atPath: iCloudURL.path) {
				try? fileManager.startDownloadingUbiquitousItem(at: iCloudURL)
				return
			}

			let newURL = certsFolderURL.appendingPathComponent("cacert.pem")

			do {

				try fileManager.createDirectory(at: certsFolderURL, withIntermediateDirectories: true, attributes: nil)

				try data.write(to: newURL)
				setenv("SSL_CERT_FILE", newURL.path.toCString(), 1)

			} catch {
				print(error)
			}

		}

	}

	@objc
	func didDismissKeyboard() {

		StoreReviewPrompter.promptIfNeeded()
	}

	@objc
	func applicationDidEnterBackground() {

		savePanelStates()

	}
	func availableCommands() -> [String] {

		let commands = String(commandsAsString())

		guard let data = commands.data(using: .utf8) else {
			assertionFailure("Expected valid data")
			return []
		}

		guard let json = try? JSONSerialization.jsonObject(with: data, options: []) else {
			assertionFailure("Expected valid json")
			return []
		}

		guard var arr = (json as? [String]) else {
			assertionFailure("Expected String Array")
			return []
		}

		arr.append("clear")
		arr.append("help")

		return arr.sorted()
	}

	func printCommands() {

		print(availableCommands().joined(separator: "\n"))

	}

	func updateTitle() {
		self.title = terminalView.executor.currentWorkingDirectory.lastPathComponent
	}

	var commandIndex = 0

	@objc func selectPreviousCommand() {

		guard commandIndex < HistoryManager.history.count else {
			return
		}

		commandIndex += 1

		terminalView.currentCommand = HistoryManager.history[commandIndex - 1]

	}

	@objc func selectNextCommand() {

		guard commandIndex > 0 else {
			return
		}

		commandIndex -= 1

		if commandIndex == 0 {
			terminalView.currentCommand = ""
		} else {
			terminalView.currentCommand = HistoryManager.history[commandIndex - 1]
		}

	}

	override var keyCommands: [UIKeyCommand]? {
		return [
			// Navigation between commands
			UIKeyCommand(input: UIKeyCommand.inputUpArrow, modifierFlags: UIKeyModifierFlags(rawValue: 0), action: #selector(selectPreviousCommand), discoverabilityTitle: "Previous command"),
			UIKeyCommand(input: UIKeyCommand.inputDownArrow, modifierFlags: UIKeyModifierFlags(rawValue: 0), action: #selector(selectNextCommand), discoverabilityTitle: "Next command")
		]
	}

	private func presentPopover(_ viewController: UIViewController, from presentingView: UIView) {
		viewController.modalPresentationStyle = .popover
		viewController.popoverPresentationController?.sourceView = presentingView
		viewController.popoverPresentationController?.sourceRect = presentingView.bounds
		viewController.popoverPresentationController?.permittedArrowDirections = .up
		viewController.popoverPresentationController?.backgroundColor = viewController.view.backgroundColor

		present(viewController, animated: true, completion: nil)
	}

	private func showDocumentPicker(_ sender: UIView) {
		terminalView.resignFirstResponder()

		let picker = UIDocumentPickerViewController(documentTypes: [kUTTypeFolder as String], in: .open)
		picker.allowsMultipleSelection = true
		picker.delegate = self

		self.present(picker, animated: true, completion: nil)
	}
	
	private func showHistory(_ sender: UIView) {
		presentPopover(historyPanelViewController, from: sender)
	}
	
	private func showScripts(_ sender: UIView) {
		
		// modalPresentationStyle needs to be overFullScreen so
		// we can have a nice transition when switching from the fullscreen mode
		// to the floating mode.
		scriptsPanelViewController.modalPresentationStyle = .overFullScreen
		scriptsPanelViewController.modalTransitionStyle = .coverVertical
		
		// A view controller with presentation style "overFullScreen" will
		// cause the keyboard of the terminalView to be presented again
		// when it's dismissed (which we don't want when switching from fullscreen mode
		// to the floating mode).
		terminalView.resignFirstResponder()

		present(scriptsPanelViewController, animated: true, completion: nil)
		
	}
	
	private func showBookmarks(_ sender: UIView) {
		presentPopover(bookmarkPanelViewController, from: sender)
	}
	
}

extension TerminalViewController: UIDocumentPickerDelegate {

	func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {

		guard let firstFolder = urls.first else {
			return
		}

		let success = firstFolder.startAccessingSecurityScopedResource()
		let isReadable = DocumentManager.shared.fileManager.isReadableFile(atPath: firstFolder.path)
		
		guard success && isReadable else {
			showAlert("Error", message: "Could not access folder.")
			return
		}
		
		self.terminalView.executor.currentWorkingDirectory = firstFolder
		self.terminalView.executor.setLocalMiniRoot()
	}

}

extension TerminalViewController: BookmarkViewControllerDelegate {

	var currentDirectoryURL: URL {
		get {
			return self.terminalView.executor.currentWorkingDirectory
		}
		set {
			// TODO: Only allow this while command is not running

			//  Access the URL
			_ = newValue.startAccessingSecurityScopedResource()

			//  Change the directory to the path.
			self.terminalView.executor.currentWorkingDirectory = newValue
			self.terminalView.executor.setLocalMiniRoot()

			self.terminalView.newLine()
			self.terminalView.writeOutput("Current directory changed to \"\(newValue.path)\"")
			self.terminalView.writePrompt()
		}
	}

}

extension TerminalViewController: TerminalViewDelegate {

	func commandDidEnd() {
		self.updateTitle()
	}

	func didEnterCommand(_ command: String) {

		HistoryManager.add(command)
		commandIndex = 0

		processCommand(command)
	}

	func didChangeCurrentWorkingDirectory(_ workingDirectory: URL) {
		updateTitle()
	}

	private func processCommand(_ command: String) {

		// Trim leading/trailing space
		let command = command.trimmingCharacters(in: .whitespacesAndNewlines)

		// Special case for clear
		if command == "clear" {
			terminalView.clearScreen()
			terminalView.writePrompt()
			return
		}

		// Special case for help
		if command == "help" || command == "?" {
			let commands = availableCommands().joined(separator: ", ")
			terminalView.writeOutput(commands)
			terminalView.writePrompt()
			return
		}

		if command == "exit" {
			if let parent = self.parent as? TerminalTabViewController {
				terminalView.executor.closeSession()
				parent.closeTab(self)
			}
			return
		}

		#if DEBUG
			if command == "debug-colors" {
				terminalView.writeOutput(String.colorTestingString)
				terminalView.writePrompt()
				return
			}
		#endif

		// Dispatch the command to the executor
		terminalView.executor.dispatch(command)
	}

}

extension TerminalViewController: HistoryViewControllerDelegate {

	func didSelectCommand(command: String) {

		terminalView.currentCommand = command

	}

}

extension TerminalViewController: PanelManager {

	var panels: [PanelViewController] {
		return [historyPanelViewController, scriptsPanelViewController, bookmarkPanelViewController] + cubPanels
	}

	var panelContentWrapperView: UIView {
		return contentWrapperView
	}

	var panelContentView: UIView {
		return terminalView
	}

	func didUpdatePinnedPanels() {

		savePanelStates()

	}
	
	func maximumNumberOfPanelsPinned(at side: PanelPinSide) -> Int {
		return 2
	}

}

extension TerminalViewController {

	@objc
	func savePanelStates() {

		let states = self.panelStates

		let encoder = PropertyListEncoder()

		guard let data = try? encoder.encode(states) else {
			return
		}

		UserDefaults.standard.set(data, forKey: "panelStates")

	}

	func getStatesFromDisk() -> [Int: PanelState]? {

		guard let data = UserDefaults.standard.data(forKey: "panelStates") else {
			return nil
		}

		let decoder = PropertyListDecoder()

		guard let states = try? decoder.decode([Int: PanelState].self, from: data) else {
			return nil
		}

		return states
	}

	func restorePanelStatesFromDisk() {

		let states: [Int: PanelState]

		if let statesFromDisk = getStatesFromDisk() {
			states = statesFromDisk
			restorePanelStates(states)

		}

	}

}

private extension TerminalViewController {

	/// State of the overflow button items
	enum OverflowState: Int {
		/// All items are visible
		case expanded

		/// All items are in an overflow menu
		case compact
	}

	/// Item to display in either the right bar button items or in an overflow menu
	struct OverflowItem {
		let visibleInBar: Bool
		let icon: UIImage
		let title: String
		let action: (_ sender: UIView) -> Void
	}

	func applyOverflowState() {
		switch self.overflowState {
		case .expanded:
			let visibleItems = overflowItems.filter { $0.visibleInBar }.map { OverflowBarButtonItem(item: $0) }
			self.navigationItem.rightBarButtonItems = visibleItems + (visibleItems.count != overflowItems.count ? [overflowItem] : [])
		case .compact:
			if self.navigationItem.rightBarButtonItems != [overflowItem] {
				self.navigationItem.rightBarButtonItems = [overflowItem]
			}
		}
	}

	@objc
	private func showOverflowMenu(_ sender: UIView) {
		let items: [OverflowItem]
		switch self.overflowState {
		case .expanded:
			items = overflowItems.filter { !$0.visibleInBar }
		case .compact:
			items = overflowItems
		}

		let menu = OverflowMenuViewController(items: items)
		menu.modalPresentationStyle = .popover
		menu.popoverPresentationController?.delegate = menu
		self.presentPopover(menu, from: sender)
	}

	private class OverflowMenuViewController: UITableViewController, UIPopoverPresentationControllerDelegate {

		let items: [OverflowItem]
		init(items: [OverflowItem]) {
			self.items = items
			super.init(style: .plain)
			tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
			tableView.alwaysBounceVertical = false
		}

		required init?(coder aDecoder: NSCoder) {
			fatalError("init(coder:) has not been implemented")
		}

		override func viewDidLayoutSubviews() {
			super.viewDidLayoutSubviews()

			self.preferredContentSize = CGSize(width: 240, height: tableView.contentSize.height)
		}

		override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
			return items.count
		}
		
		override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
			let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)

			let item = items[indexPath.row]
			cell.textLabel?.text = item.title
			cell.imageView?.image = item.icon
			cell.imageView?.backgroundColor = .darkGray
			cell.imageView?.layer.cornerRadius = 5
			cell.backgroundColor = .clear
			cell.selectionStyle = .default

			return cell
		}

		override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
			tableView.deselectRow(at: indexPath, animated: true)

			tableView.cellForRow(at: indexPath)?.imageView?.backgroundColor = .darkGray

			// Get the view that presented this popover
			guard let presentingView = popoverPresentationController?.sourceView else { return }

			// Dismiss ourself, and run action with presenting view
			let item = items[indexPath.row]
			presentingViewController?.dismiss(animated: true, completion: {
				item.action(presentingView)
			})
		}

		override func tableView(_ tableView: UITableView, didHighlightRowAt indexPath: IndexPath) {
			tableView.cellForRow(at: indexPath)?.imageView?.backgroundColor = .darkGray
		}

		// Always show in popover, even on iPhone
		func adaptivePresentationStyle(for controller: UIPresentationController) -> UIModalPresentationStyle {
			return .none
		}
		func adaptivePresentationStyle(for controller: UIPresentationController, traitCollection: UITraitCollection) -> UIModalPresentationStyle {
			return .none
		}
	}

	private class OverflowBarButtonItem: UIBarButtonItem {
		
		var item: OverflowItem?
		
		convenience init(item: OverflowItem) {
			self.init(image: item.icon, style: .plain, target: nil, action: #selector(onTap))
			self.target = self
			self.item = item
		}

		@objc private func onTap(_ sender: UIView) {
			item?.action(sender)
		}
	}
}
