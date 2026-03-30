import AppKit
import SwiftUI

class TerminalPanel: NSPanel {
    private let sessionStore: SessionStore
    private var hostingView: NSHostingView<PanelContentView>?
    var isExpanded = true
    private var expandedHeight: CGFloat

    init(sessionStore: SessionStore) {
        self.sessionStore = sessionStore
        self.expandedHeight = SettingsManager.shared.panelHeight

        let width = SettingsManager.shared.panelWidth
        let rect = NSRect(x: 0, y: 0, width: width, height: expandedHeight)

        super.init(
            contentRect: rect,
            styleMask: [.borderless, .resizable, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = false
        minSize = NSSize(width: 480, height: 300)

        let content = PanelContentView(sessionStore: sessionStore)
        let host = NSHostingView(rootView: content)
        host.frame = rect
        host.autoresizingMask = [.width, .height]
        contentView = host
        hostingView = host

        contentView?.wantsLayer = true
        contentView?.layer?.cornerRadius = 8.5
        contentView?.layer?.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        contentView?.layer?.masksToBounds = true

        setupObservers()
    }

    private func setupObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeKey),
            name: NSWindow.didBecomeKeyNotification,
            object: self
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidResignKey),
            name: NSWindow.didResignKeyNotification,
            object: self
        )
    }

    @objc private func windowDidBecomeKey() {
        alphaValue = 1.0
    }

    @objc private func windowDidResignKey() {
        guard !sessionStore.isPinned else { return }
        if isExpanded {
            alphaValue = 0.8
        } else {
            orderOut(nil)
        }
    }

    func showBelow(rect: NSRect) {
        let x = rect.midX - frame.width / 2
        let y = rect.minY - frame.height - 4
        setFrameOrigin(NSPoint(x: x, y: y))
        orderFront(nil)
        makeKey()
    }

    func toggleExpanded() {
        if isExpanded {
            expandedHeight = frame.height
            let collapsed = NSRect(
                x: frame.minX,
                y: frame.maxY - 44,
                width: frame.width,
                height: 44
            )
            setFrame(collapsed, display: true, animate: true)
            minSize = NSSize(width: 480, height: 44)
            isExpanded = false
        } else {
            minSize = NSSize(width: 480, height: 300)
            let expanded = NSRect(
                x: frame.minX,
                y: frame.maxY - expandedHeight,
                width: frame.width,
                height: expandedHeight
            )
            setFrame(expanded, display: true, animate: true)
            isExpanded = true
        }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        makeKey()
    }

    override func keyDown(with event: NSEvent) {
        if let appDelegate = NSApp.delegate as? AppDelegate,
           appDelegate.handleKeyDown(event) {
            return
        }
        super.keyDown(with: event)
    }
}
