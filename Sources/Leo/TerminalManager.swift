import AppKit
import SwiftTerm

// MARK: - Click-Through Terminal View

class ClickThroughTerminalView: LocalProcessTerminalView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var localKeyMonitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        setupArrowKeyInterception()
    }

    private func setupArrowKeyInterception() {
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.window?.firstResponder === self else { return event }
            let arrowCodes: [UInt16: String] = [126: "A", 125: "B", 124: "C", 123: "D"]
            guard let arrow = arrowCodes[event.keyCode] else { return event }

            var modifier = 0
            if event.modifierFlags.contains(.shift) { modifier += 1 }
            if event.modifierFlags.contains(.option) { modifier += 2 }
            if event.modifierFlags.contains(.control) { modifier += 4 }

            let sequence: String
            if modifier > 0 {
                sequence = "\u{1b}[1;\(modifier + 1)\(arrow)"
            } else {
                sequence = "\u{1b}[\(arrow)"
            }

            self.send(txt: sequence)
            return nil
        }
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        return .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let items = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [URL] else {
            return false
        }
        let paths = items.map { shellEscape($0.path) }.joined(separator: " ")
        send(txt: paths)
        return true
    }

    private func shellEscape(_ path: String) -> String {
        return "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    deinit {
        if let monitor = localKeyMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}

// MARK: - Terminal Manager

final class TerminalManager: NSObject {
    static let shared = TerminalManager()
    private var terminals: [UUID: ClickThroughTerminalView] = [:]
    private var statusDebounce: [UUID: DispatchWorkItem] = [:]
    private var statusTimers: [UUID: Timer] = [:]

    private override init() { super.init() }

    func terminal(for session: TerminalSession) -> ClickThroughTerminalView {
        if let existing = terminals[session.id] { return existing }

        let terminal = ClickThroughTerminalView(frame: .zero)
        terminal.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        terminal.nativeForegroundColor = NSColor(white: 0.9, alpha: 1.0)
        terminal.nativeBackgroundColor = NSColor(white: 0.1, alpha: 1.0)

        terminals[session.id] = terminal

        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        var env = Terminal.getEnvironmentVariables(termName: "xterm-256color")
        env.append("LANG=en_US.UTF-8")

        terminal.startProcess(
            executable: shell,
            args: ["--login"],
            environment: env,
            execName: nil
        )

        if SettingsManager.shared.claudeIntegrationEnabled {
            let dir = session.workingDirectory
            let claudeMdPath = (dir as NSString).appendingPathComponent("CLAUDE.md")
            if FileManager.default.fileExists(atPath: claudeMdPath) {
                let escaped = shellEscape(dir)
                terminal.send(txt: "cd \(escaped) && clear && claude\r")
            } else {
                let escaped = shellEscape(dir)
                terminal.send(txt: "cd \(escaped) && clear\r")
            }
        }

        startStatusMonitoring(for: session.id, terminal: terminal)

        return terminal
    }

    func removeTerminal(for sessionId: UUID) {
        statusDebounce[sessionId]?.cancel()
        statusDebounce.removeValue(forKey: sessionId)
        statusTimers[sessionId]?.invalidate()
        statusTimers.removeValue(forKey: sessionId)
        terminals.removeValue(forKey: sessionId)
    }

    // MARK: - Status Detection

    private func startStatusMonitoring(for sessionId: UUID, terminal: ClickThroughTerminalView) {
        let timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self, weak terminal] _ in
            guard let self, let terminal else { return }
            self.debounceStatusCheck(sessionId: sessionId, terminal: terminal)
        }
        statusTimers[sessionId] = timer
    }

    private func debounceStatusCheck(sessionId: UUID, terminal: ClickThroughTerminalView) {
        statusDebounce[sessionId]?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.checkTerminalStatus(sessionId: sessionId, terminal: terminal)
        }
        statusDebounce[sessionId] = work
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    private func checkTerminalStatus(sessionId: UUID, terminal: ClickThroughTerminalView) {
        let lines = extractVisibleLines(from: terminal)
        guard lines.count >= 5 else { return }

        let text = lines.joined(separator: "\n")
        let status: TerminalStatus

        let spinnerChars: Set<Character> = ["·", "✢", "✳", "✶", "✻", "✽"]
        let hasSpinner = text.contains(where: { spinnerChars.contains($0) })
        let hasEllipsis = text.contains("…")

        if (hasSpinner && hasEllipsis) || text.contains("esc to interrupt") {
            status = .working
        } else if text.contains("Esc to cancel") || text.range(of: "❯ \\d", options: .regularExpression) != nil {
            status = .waitingForInput
        } else if text.contains("Interrupted") {
            status = .interrupted
        } else {
            status = .idle
        }

        DispatchQueue.main.async {
            SessionStore.shared.updateStatus(sessionId: sessionId, status: status)
        }
    }

    private func extractVisibleLines(from terminal: ClickThroughTerminalView) -> [String] {
        let terminalAccess = terminal.getTerminal()
        let rows = terminalAccess.rows
        let cols = terminalAccess.cols
        var lines: [String] = []

        for row in max(0, rows - 30)..<rows {
            var line = ""
            for col in 0..<cols {
                let ch = terminalAccess.getCharacter(col: col, row: row)
                let scalar = ch.flatMap({ String($0) }) ?? " "
                line += scalar
            }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                lines.append(trimmed)
            }
        }
        return lines
    }

    private func shellEscape(_ path: String) -> String {
        return "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
