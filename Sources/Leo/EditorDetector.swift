import Foundation
import AppKit
import CoreGraphics

struct DetectedProject {
    let name: String
    let path: String?

    var directoryPath: String {
        guard let path else {
            return FileManager.default.homeDirectoryForCurrentUser.path
        }
        let url = URL(fileURLWithPath: path)
        if ["xcodeproj", "xcworkspace"].contains(url.pathExtension) {
            return url.deletingLastPathComponent().path
        }
        return path
    }
}

actor EditorDetector {
    static let shared = EditorDetector()
    private init() {}

    func detectProjects() async -> [DetectedProject] {
        let settings = SettingsManager.shared
        var projects: [DetectedProject] = []

        if settings.enabledEditors.contains("xcode") {
            projects.append(contentsOf: detectXcode())
        }
        if settings.enabledEditors.contains("vscode") {
            projects.append(contentsOf: detectElectronEditor(processName: "Electron", appName: "Visual Studio Code"))
        }
        if settings.enabledEditors.contains("cursor") {
            projects.append(contentsOf: detectElectronEditor(processName: "Cursor", appName: "Cursor"))
        }
        if settings.enabledEditors.contains("jetbrains") {
            projects.append(contentsOf: detectJetBrains())
        }
        if settings.enabledEditors.contains("terminal") {
            projects.append(contentsOf: detectTerminal())
        }

        var seen = Set<String>()
        return projects.filter { seen.insert($0.name).inserted }
    }

    // MARK: - Xcode Detection

    private func detectXcode() -> [DetectedProject] {
        let apps = NSWorkspace.shared.runningApplications
        guard apps.contains(where: { $0.bundleIdentifier == "com.apple.dt.Xcode" }) else { return [] }

        let script = """
        tell application "Xcode"
            set docs to workspace documents
            set result to ""
            repeat with doc in docs
                set docName to name of doc
                set docPath to path of doc
                set result to result & docName & "|||" & docPath & ":::"
            end repeat
            return result
        end tell
        """

        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            let result = appleScript.executeAndReturnError(&error)
            if error == nil, let output = result.stringValue, !output.isEmpty {
                return parseAppleScriptResult(output)
            }
        }

        return detectFromWindowTitles(bundleId: "com.apple.dt.Xcode")
    }

    private func parseAppleScriptResult(_ output: String) -> [DetectedProject] {
        output.split(separator: ":::").compactMap { entry in
            let parts = entry.split(separator: "|||", maxSplits: 1)
            guard parts.count == 2 else { return nil }
            var name = String(parts[0])
            let path = String(parts[1])

            for ext in [".xcodeproj", ".xcworkspace"] {
                if name.hasSuffix(ext) {
                    name = String(name.dropLast(ext.count))
                }
            }
            return DetectedProject(name: name, path: path)
        }
    }

    // MARK: - VS Code / Cursor Detection

    private func detectElectronEditor(processName: String, appName: String) -> [DetectedProject] {
        let apps = NSWorkspace.shared.runningApplications
        guard let app = apps.first(where: {
            $0.localizedName == appName || $0.bundleIdentifier?.contains(processName.lowercased()) == true
        }) else { return [] }

        return detectFromWindowTitles(pid: app.processIdentifier)
    }

    // MARK: - JetBrains Detection

    private func detectJetBrains() -> [DetectedProject] {
        let configDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/JetBrains")

        guard FileManager.default.fileExists(atPath: configDir.path) else { return [] }

        let jetbrainsApps = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier?.contains("jetbrains") == true ||
            $0.localizedName?.contains("IntelliJ") == true ||
            $0.localizedName?.contains("WebStorm") == true ||
            $0.localizedName?.contains("PyCharm") == true ||
            $0.localizedName?.contains("CLion") == true ||
            $0.localizedName?.contains("GoLand") == true
        }
        guard !jetbrainsApps.isEmpty else { return [] }

        var projects: [DetectedProject] = []
        if let contents = try? FileManager.default.contentsOfDirectory(at: configDir, includingPropertiesForKeys: nil) {
            for dir in contents {
                let recentFile = dir.appendingPathComponent("options/recentProjects.xml")
                if let data = try? String(contentsOf: recentFile, encoding: .utf8) {
                    projects.append(contentsOf: parseJetBrainsRecent(data))
                }
            }
        }
        return projects
    }

    private func parseJetBrainsRecent(_ xml: String) -> [DetectedProject] {
        var projects: [DetectedProject] = []
        let pattern = #"projectPath="([^"]+)"#
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let matches = regex.matches(in: xml, range: NSRange(xml.startIndex..., in: xml))
            for match in matches.prefix(5) {
                if let range = Range(match.range(at: 1), in: xml) {
                    let path = String(xml[range]).replacingOccurrences(of: "$USER_HOME$", with: FileManager.default.homeDirectoryForCurrentUser.path)
                    let name = URL(fileURLWithPath: path).lastPathComponent
                    projects.append(DetectedProject(name: name, path: path))
                }
            }
        }
        return projects
    }

    // MARK: - Terminal Detection

    private func detectTerminal() -> [DetectedProject] {
        let app = NSWorkspace.shared.frontmostApplication
        guard app?.bundleIdentifier == "com.apple.Terminal" ||
              app?.bundleIdentifier == "com.googlecode.iterm2" ||
              app?.bundleIdentifier == "net.kovidgoyal.kitty" ||
              app?.bundleIdentifier == "com.mitchellh.ghostty" else { return [] }

        guard let pid = app?.processIdentifier else { return [] }
        return detectFromWindowTitles(pid: pid)
    }

    // MARK: - Window Title Detection (shared)

    private func detectFromWindowTitles(bundleId: String? = nil, pid: pid_t? = nil) -> [DetectedProject] {
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        var projects: [DetectedProject] = []
        var seen = Set<String>()

        for window in windowList {
            let windowLayer = window[kCGWindowLayer as String] as? Int ?? -1
            guard windowLayer == 0 else { continue }

            if let pid {
                let windowPid = window[kCGWindowOwnerPID as String] as? pid_t ?? 0
                guard windowPid == pid else { continue }
            }

            if let bundleId {
                let ownerName = window[kCGWindowOwnerName as String] as? String ?? ""
                guard ownerName.contains("Xcode") || ownerName == bundleId else { continue }
            }

            guard let title = window[kCGWindowName as String] as? String, !title.isEmpty else { continue }

            let name: String
            if let dashRange = title.range(of: " — ") ?? title.range(of: " – ") {
                name = String(title[..<dashRange.lowerBound])
            } else if let dashRange = title.range(of: " - ") {
                name = String(title[..<dashRange.lowerBound])
            } else {
                name = title
            }

            let cleaned = name.trimmingCharacters(in: .whitespaces)
            guard !cleaned.isEmpty, !seen.contains(cleaned) else { continue }
            seen.insert(cleaned)
            projects.append(DetectedProject(name: cleaned, path: nil))
        }

        return projects
    }
}
