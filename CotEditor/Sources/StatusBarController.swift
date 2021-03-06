//
//  StatusBarController.swift
//
//  CotEditor
//  https://coteditor.com
//
//  Created by 1024jp on 2014-07-11.
//
//  ---------------------------------------------------------------------------
//
//  © 2014-2020 1024jp
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  https://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Cocoa

final class StatusBarController: NSViewController {
    
    // MARK: Private Properties
    
    private var defaultsObservers: [UserDefaultsObservation] = []
    private let byteCountFormatter = ByteCountFormatter()
    
    @available(macOS, deprecated: 10.15)
    private var appearanceObserver: NSKeyValueObservation?
    
    @objc private dynamic var editorStatus: NSAttributedString?
    @objc private dynamic var documentStatus: NSAttributedString?
    @objc private dynamic var showsReadOnly = false
    
    
    
    // MARK: -
    // MARK: Lifecycle
    
    deinit {
        self.defaultsObservers.forEach { $0.invalidate() }
        self.appearanceObserver?.invalidate()
    }
    
    
    
    // MARK: View Controller Methods
    
    /// setup
    override func viewDidLoad() {
        
        super.viewDidLoad()
        
        self.byteCountFormatter.isAdaptive = false
        
        // set accessibility
        self.view.setAccessibilityElement(true)
        self.view.setAccessibilityRole(.group)
        self.view.setAccessibilityLabel("status bar".localized)
    }
    
    
    /// request analyzer to update editor info
    override func viewWillAppear() {
        
        super.viewWillAppear()
        
        assert(self.documentAnalyzer != nil)
        
        self.documentAnalyzer?.shouldUpdateStatusEditorInfo = true
        self.documentAnalyzer?.invalidateEditorInfo()
        
        // observe change in defaults
        self.defaultsObservers.forEach { $0.invalidate() }
        self.defaultsObservers = []
        let editorDefaultKeys: [DefaultKeys] = [
            .showStatusBarLines,
            .showStatusBarChars,
            .showStatusBarWords,
            .showStatusBarLocation,
            .showStatusBarLine,
            .showStatusBarColumn,
        ]
        self.defaultsObservers += UserDefaults.standard.observe(keys: editorDefaultKeys) { [weak self] (_, _) in
            self?.updateEditorStatus()
        }
        let documentDefaultKeys: [DefaultKeys] = [
            .showStatusBarEncoding,
            .showStatusBarLineEndings,
            .showStatusBarFileSize,
        ]
        self.defaultsObservers += UserDefaults.standard.observe(keys: documentDefaultKeys) { [weak self] (_, _) in
            self?.updateDocumentStatus()
        }
        
        if NSAppKitVersion.current < .macOS10_15 {
            self.appearanceObserver?.invalidate()
            self.appearanceObserver = self.view.observe(\.effectiveAppearance) { [weak self] (_, _) in
                self?.updateEditorStatus()
            }
        }
    }
    
    
    /// request analyzer to stop updating editor info
    override func viewDidDisappear() {
        
        super.viewDidDisappear()
        
        self.documentAnalyzer?.shouldUpdateStatusEditorInfo = false
        
        self.defaultsObservers.forEach { $0.invalidate() }
        self.defaultsObservers = []
        
        self.appearanceObserver?.invalidate()
        self.appearanceObserver = nil
    }
    
    
    
    // MARK: Public Methods
    
    weak var documentAnalyzer: DocumentAnalyzer? {
        
        willSet {
            guard let analyzer = documentAnalyzer else { return }
            
            analyzer.shouldUpdateStatusEditorInfo = false
            
            NotificationCenter.default.removeObserver(self, name: DocumentAnalyzer.didUpdateEditorInfoNotification, object: analyzer)
            NotificationCenter.default.removeObserver(self, name: DocumentAnalyzer.didUpdateFileInfoNotification, object: analyzer)
            NotificationCenter.default.removeObserver(self, name: DocumentAnalyzer.didUpdateModeInfoNotification, object: analyzer)
        }
        
        didSet {
            guard let analyzer = documentAnalyzer else { return }
            
            analyzer.shouldUpdateStatusEditorInfo = self.isViewShown
            
            NotificationCenter.default.addObserver(self, selector: #selector(updateEditorStatus), name: DocumentAnalyzer.didUpdateEditorInfoNotification, object: analyzer)
            NotificationCenter.default.addObserver(self, selector: #selector(updateDocumentStatus), name: DocumentAnalyzer.didUpdateFileInfoNotification, object: analyzer)
            NotificationCenter.default.addObserver(self, selector: #selector(updateDocumentStatus), name: DocumentAnalyzer.didUpdateModeInfoNotification, object: analyzer)
            
            self.updateEditorStatus()
            self.updateDocumentStatus()
        }
    }
    
    
    
    // MARK: Private Methods
    
    /// update left side text
    @objc private func updateEditorStatus() {
        
        assert(Thread.isMainThread)
        
        guard
            self.isViewShown,
            let info = self.documentAnalyzer?.info.editor
            else { return }
        
        let defaults = UserDefaults.standard
        let labelColor = NSColor.statusBarLabelColor(appearance: self.view.effectiveAppearance)
        let status = NSMutableAttributedString()
        
        if defaults[.showStatusBarLines] {
            status.appendFormattedState(value: info.lines, label: (string: "Lines", color: labelColor))
        }
        if defaults[.showStatusBarChars] {
            status.appendFormattedState(value: info.chars, label: (string: "Characters", color: labelColor))
        }
        if defaults[.showStatusBarWords] {
            status.appendFormattedState(value: info.words, label: (string: "Words", color: labelColor))
        }
        if defaults[.showStatusBarLocation] {
            status.appendFormattedState(value: info.location, label: (string: "Location", color: labelColor))
        }
        if defaults[.showStatusBarLine] {
            status.appendFormattedState(value: info.line, label: (string: "Line", color: labelColor))
        }
        if defaults[.showStatusBarColumn] {
            status.appendFormattedState(value: info.column, label: (string: "Column", color: labelColor))
        }
        
        // truncate tail
        let paragraphStyle = NSParagraphStyle.default.mutable
        paragraphStyle.lineBreakMode = .byTruncatingTail
        status.addAttribute(.paragraphStyle, value: paragraphStyle, range: status.range)
        
        self.editorStatus = status
    }
    
    
    /// update right side text and readonly icon state
    @objc private func updateDocumentStatus() {
        
        assert(Thread.isMainThread)
        
        guard
            self.isViewShown,
            let info = self.documentAnalyzer?.info
            else { return }
        
        let defaults = UserDefaults.standard
        let status = NSMutableAttributedString()
        
        if defaults[.showStatusBarEncoding] {
            status.appendFormattedState(value: info.mode.encoding, label: nil)
        }
        if defaults[.showStatusBarLineEndings] {
            status.appendFormattedState(value: info.mode.lineEndings, label: nil)
        }
        if defaults[.showStatusBarFileSize] {
            let fileSize = self.byteCountFormatter.string(for: info.file.fileSize)
            status.appendFormattedState(value: fileSize, label: nil)
        }
        
        self.documentStatus = status
        self.showsReadOnly = info.file.isReadOnly
    }
    
}



// MARK: -

private extension NSColor {
    
    @available(macOS 10.15, *)
    static let statusBarLabelColor = NSColor(name: "statusBarLabelColor") { appearance in
        
        appearance.isDark ? NSColor.secondaryLabelColor : NSColor.labelColor.withAlphaComponent(0.6)
    }
    
    
    @available(macOS, deprecated: 10.15, renamed: "statusBarLabelColor")
    static func statusBarLabelColor(appearance: NSAppearance) -> NSColor {
        
        guard #available(macOS 10.15, *) else {
            return appearance.isDark ? Self.secondaryLabelColor : Self.labelColor.withAlphaComponent(0.6)
        }
        
        return NSColor.statusBarLabelColor
    }
    
}


private extension NSMutableAttributedString {
    
    /// append formatted state
    func appendFormattedState(value: String?, label: (string: String, color: NSColor)?) {
        
        if !self.string.isEmpty {
            self.append(NSAttributedString(string: "   "))
        }
        
        if let label = label {
            let attrLabel = NSAttributedString(string: (label.string + ": ").localized,
                                               attributes: [.foregroundColor: label.color])
            self.append(attrLabel)
        }
        
        let attrValue: NSAttributedString = {
            if let value = value {
                return NSAttributedString(string: value)
            } else {
                return NSAttributedString(string: "-",
                                          attributes: [.foregroundColor: NSColor.disabledControlTextColor])
            }
        }()
        
        self.append(attrValue)
    }
    
}
