import SwiftUI
import AppKit

// MARK: - Settings Window Controller

class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 450, height: 340),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Leo Settings"
        window.center()
        window.isReleasedWhenClosed = false
        window.level = .floating

        let settingsView = SettingsView()
        window.contentView = NSHostingView(rootView: settingsView)

        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError() }
}

// MARK: - Settings View

struct SettingsView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gear") }
                .tag(0)

            HotkeySettingsTab()
                .tabItem { Label("Hotkey", systemImage: "keyboard") }
                .tag(1)

            EditorsSettingsTab()
                .tabItem { Label("Editors", systemImage: "laptopcomputer") }
                .tag(2)

            AboutTab()
                .tabItem { Label("About", systemImage: "info.circle") }
                .tag(3)
        }
        .frame(width: 420, height: 300)
        .padding(20)
    }
}

// MARK: - General Tab

struct GeneralSettingsTab: View {
    @State private var settings = SettingsManager.shared

    var body: some View {
        Form {
            Toggle("Show notch overlay", isOn: Bindable(settings).$showNotch)
            Text("Display the Leo pill in the MacBook notch area")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            Toggle("Enable notification sounds", isOn: Bindable(settings).$soundEnabled)
            Text("Play a sound when Claude completes a task")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            Toggle("Auto-launch Claude Code", isOn: Bindable(settings).$claudeIntegrationEnabled)
            Text("Automatically start Claude when opening a terminal in a project with CLAUDE.md")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            Toggle("Launch at login", isOn: Bindable(settings).$launchAtLogin)

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("Default panel size")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Text("Width:")
                        .font(.caption)
                    TextField("", value: Bindable(settings).$panelWidth, format: .number)
                        .frame(width: 60)
                    Text("Height:")
                        .font(.caption)
                    TextField("", value: Bindable(settings).$panelHeight, format: .number)
                        .frame(width: 60)
                }
            }
        }
    }
}

// MARK: - Hotkey Tab

struct HotkeySettingsTab: View {
    @State private var settings = SettingsManager.shared
    @State private var isRecording = false

    var body: some View {
        Form {
            VStack(alignment: .leading, spacing: 12) {
                Text("Toggle Hotkey")
                    .font(.headline)

                HStack {
                    Text("Current:")
                    Text(currentHotkeyDisplay)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(4)
                        .font(.system(.body, design: .monospaced))
                }

                Button(isRecording ? "Press your shortcut…" : "Change Hotkey") {
                    isRecording = true
                }
                .disabled(isRecording)

                if isRecording {
                    Text("Press any key combination, or Esc to cancel")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ShortcutRecorder { keyCode, modifiers in
                        settings.hotkeyKeyCode = keyCode
                        settings.hotkeyModifiers = modifiers.rawValue
                        isRecording = false
                    } onCancel: {
                        isRecording = false
                    }
                    .frame(width: 0, height: 0)
                }
            }
        }
    }

    private var currentHotkeyDisplay: String {
        let modifiers = NSEvent.ModifierFlags(rawValue: UInt(settings.hotkeyModifiers))
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("⌃") }
        if modifiers.contains(.option) { parts.append("⌥") }
        if modifiers.contains(.shift) { parts.append("⇧") }
        if modifiers.contains(.command) { parts.append("⌘") }

        let keyName = keyCodeToString(settings.hotkeyKeyCode)
        parts.append(keyName)
        return parts.joined()
    }

    private func keyCodeToString(_ keyCode: UInt16) -> String {
        let map: [UInt16: String] = [
            50: "`", 18: "1", 19: "2", 20: "3", 21: "4", 23: "5",
            22: "6", 26: "7", 28: "8", 25: "9", 29: "0",
            0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F",
            5: "G", 4: "H", 34: "I", 38: "J", 40: "K", 37: "L",
            46: "M", 45: "N", 31: "O", 35: "P", 12: "Q", 15: "R",
            1: "S", 17: "T", 32: "U", 9: "V", 13: "W", 7: "X",
            16: "Y", 6: "Z", 49: "Space", 36: "Return", 48: "Tab",
            51: "Delete", 53: "Esc", 27: "-", 24: "=",
            33: "[", 30: "]", 42: "\\", 41: ";", 39: "'",
            43: ",", 47: ".", 44: "/",
        ]
        return map[keyCode] ?? "Key\(keyCode)"
    }
}

// MARK: - Shortcut Recorder

struct ShortcutRecorder: NSViewRepresentable {
    let onRecord: (UInt16, NSEvent.ModifierFlags) -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = RecorderView()
        view.onRecord = onRecord
        view.onCancel = onCancel
        DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

class RecorderView: NSView {
    var onRecord: ((UInt16, NSEvent.ModifierFlags) -> Void)?
    var onCancel: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel?()
            return
        }
        let modifiers = event.modifierFlags.intersection([.control, .option, .shift, .command])
        if !modifiers.isEmpty {
            onRecord?(event.keyCode, modifiers)
        }
    }
}

// MARK: - Editors Tab

struct EditorsSettingsTab: View {
    @State private var settings = SettingsManager.shared

    var body: some View {
        Form {
            Text("Detect projects from these editors:")
                .font(.headline)

            editorToggle("Xcode", key: "xcode")
            editorToggle("Visual Studio Code", key: "vscode")
            editorToggle("Cursor", key: "cursor")
            editorToggle("JetBrains IDEs", key: "jetbrains")
            editorToggle("Terminal", key: "terminal")
        }
    }

    private func editorToggle(_ label: String, key: String) -> some View {
        Toggle(label, isOn: Binding(
            get: { settings.enabledEditors.contains(key) },
            set: { enabled in
                if enabled {
                    settings.enabledEditors.insert(key)
                } else {
                    settings.enabledEditors.remove(key)
                }
            }
        ))
    }
}

// MARK: - About Tab

struct AboutTab: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("🔮")
                .font(.system(size: 48))

            Text("Leo")
                .font(.title)
                .fontWeight(.bold)

            Text("Get back to shipping")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("Claude Code in your notch")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Divider()

            Text("MIT License")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
