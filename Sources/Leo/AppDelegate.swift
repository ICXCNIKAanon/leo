import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let sessionStore = SessionStore.shared
    private let settings = SettingsManager.shared

    var notchWindow: NotchWindow?
    var terminalPanel: TerminalPanel?
    var hotkeyManager: HotkeyManager?

    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    var panelOpenedViaHover = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        setupNotchWindow()
        setupTerminalPanel()
        setupMouseTracking()
        setupHotkey()
        setupNotificationObservers()
    }

    // MARK: - Menu Bar

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.title = "🔮"
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        showMenu()
    }

    private func showMenu() {
        let menu = NSMenu()

        for session in sessionStore.sessions {
            let item = NSMenuItem(
                title: session.projectName,
                action: #selector(selectSession(_:)),
                keyEquivalent: ""
            )
            item.representedObject = session.id
            if session.id == sessionStore.activeSessionId {
                item.state = .on
            }
            menu.addItem(item)
        }

        if !sessionStore.sessions.isEmpty {
            menu.addItem(NSMenuItem.separator())
        }

        menu.addItem(NSMenuItem(title: "New Session", action: #selector(newSession), keyEquivalent: "n"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Leo", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func selectSession(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        sessionStore.activeSessionId = id
    }

    @objc private func newSession() {
        sessionStore.createSession(
            projectName: "New Session",
            workingDirectory: FileManager.default.homeDirectoryForCurrentUser.path
        )
        showPanel()
    }

    @objc private func openSettings() {
        SettingsWindowController.shared.showWindow(nil)
    }

    // MARK: - Notch Window

    private func setupNotchWindow() {
        notchWindow = NotchWindow(
            onHover: { [weak self] in
                self?.panelOpenedViaHover = true
                self?.showPanelBelowNotch()
            },
            onEndHover: { [weak self] in
                guard let self, self.panelOpenedViaHover else { return }
                self.hidePanel()
                self.panelOpenedViaHover = false
            },
            sessionStore: sessionStore
        )
    }

    // MARK: - Terminal Panel

    private func setupTerminalPanel() {
        terminalPanel = TerminalPanel(sessionStore: sessionStore)
    }

    func showPanel() {
        guard let panel = terminalPanel, let button = statusItem.button,
              let buttonWindow = button.window else { return }
        let buttonRect = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        panel.showBelow(rect: buttonRect)
    }

    func showPanelBelowNotch() {
        guard let panel = terminalPanel, let screen = NSScreen.main else { return }
        let screenFrame = screen.frame
        let panelWidth = panel.frame.width
        let x = screenFrame.midX - panelWidth / 2
        let notchHeight: CGFloat = 38
        let y = screenFrame.maxY - notchHeight - panel.frame.height
        panel.setFrameOrigin(NSPoint(x: x, y: y))
        panel.orderFront(nil)
    }

    func hidePanel() {
        guard !sessionStore.isPinned else { return }
        terminalPanel?.orderOut(nil)
    }

    // MARK: - Mouse Tracking

    private func setupMouseTracking() {
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged]
        ) { [weak self] event in
            self?.notchWindow?.checkMouse(event: event)
        }

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged]
        ) { [weak self] event in
            self?.notchWindow?.checkMouse(event: event)
            return event
        }
    }

    // MARK: - Hotkey

    private func setupHotkey() {
        hotkeyManager = HotkeyManager { [weak self] in
            self?.togglePanel()
        }
    }

    func togglePanel() {
        guard let panel = terminalPanel else { return }
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            showPanel()
        }
    }

    // MARK: - Notifications

    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleHidePanel),
            name: .leoHidePanel,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleExpandPanel),
            name: .leoExpandPanel,
            object: nil
        )
    }

    @objc private func handleHidePanel() {
        hidePanel()
    }

    @objc private func handleExpandPanel() {
        showPanel()
    }

    // MARK: - Keyboard Shortcuts

    func handleKeyDown(_ event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command) && event.keyCode == 1 {
            if let sessionId = sessionStore.activeSessionId,
               let session = sessionStore.sessions.first(where: { $0.id == sessionId }) {
                Task {
                    await CheckpointManager.shared.createCheckpoint(
                        projectName: session.projectName,
                        workingDirectory: session.workingDirectory
                    )
                }
            }
            return true
        }
        return false
    }

    deinit {
        if let monitor = globalMouseMonitor { NSEvent.removeMonitor(monitor) }
        if let monitor = localMouseMonitor { NSEvent.removeMonitor(monitor) }
    }
}
