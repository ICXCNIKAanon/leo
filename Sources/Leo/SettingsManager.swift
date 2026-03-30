import Foundation
import AppKit

@Observable
final class SettingsManager {
    static let shared = SettingsManager()

    var showNotch: Bool {
        didSet { UserDefaults.standard.set(showNotch, forKey: "showNotch") }
    }
    var soundEnabled: Bool {
        didSet { UserDefaults.standard.set(soundEnabled, forKey: "soundEnabled") }
    }
    var claudeIntegrationEnabled: Bool {
        didSet { UserDefaults.standard.set(claudeIntegrationEnabled, forKey: "claudeIntegrationEnabled") }
    }
    var panelWidth: CGFloat {
        didSet { UserDefaults.standard.set(Double(panelWidth), forKey: "panelWidth") }
    }
    var panelHeight: CGFloat {
        didSet { UserDefaults.standard.set(Double(panelHeight), forKey: "panelHeight") }
    }
    var hotkeyModifiers: UInt {
        didSet { UserDefaults.standard.set(hotkeyModifiers, forKey: "hotkeyModifiers") }
    }
    var hotkeyKeyCode: UInt16 {
        didSet { UserDefaults.standard.set(Int(hotkeyKeyCode), forKey: "hotkeyKeyCode") }
    }
    var enabledEditors: Set<String> {
        didSet {
            UserDefaults.standard.set(Array(enabledEditors), forKey: "enabledEditors")
        }
    }
    var launchAtLogin: Bool {
        didSet { UserDefaults.standard.set(launchAtLogin, forKey: "launchAtLogin") }
    }

    private init() {
        let defaults = UserDefaults.standard
        self.showNotch = defaults.object(forKey: "showNotch") as? Bool ?? true
        self.soundEnabled = defaults.object(forKey: "soundEnabled") as? Bool ?? true
        self.claudeIntegrationEnabled = defaults.object(forKey: "claudeIntegrationEnabled") as? Bool ?? true
        self.panelWidth = CGFloat(defaults.object(forKey: "panelWidth") as? Double ?? 480)
        self.panelHeight = CGFloat(defaults.object(forKey: "panelHeight") as? Double ?? 500)
        self.hotkeyModifiers = defaults.object(forKey: "hotkeyModifiers") as? UInt ?? NSEvent.ModifierFlags.control.rawValue
        self.hotkeyKeyCode = UInt16(defaults.object(forKey: "hotkeyKeyCode") as? Int ?? 50)
        self.enabledEditors = Set(defaults.object(forKey: "enabledEditors") as? [String] ?? ["xcode", "vscode", "cursor", "jetbrains", "terminal"])
        self.launchAtLogin = defaults.object(forKey: "launchAtLogin") as? Bool ?? false
    }
}
