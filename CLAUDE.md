# Leo

macOS menu bar app -- Claude Code terminal in the MacBook notch.

## Tech Stack
- Swift / SwiftUI, macOS 14.0+ (Sonoma)
- SwiftTerm (SPM) for terminal emulation
- AppKit for window management (NSPanel, NSWindow, NSEvent)
- CoreVideo (CVDisplayLink) for smooth animations

## Architecture
- `LeoApp.swift` -- @main entry, NSApplicationDelegateAdaptor
- `AppDelegate.swift` -- menu bar, mouse tracking, keyboard shortcuts, lifecycle
- `NotchWindow.swift` -- invisible overlay, hover detection, pill animations (CVDisplayLink)
- `TerminalPanel.swift` -- floating NSPanel, expand/collapse
- `PanelContentView.swift` -- SwiftUI layout (tabs, terminal, checkpoint bar)
- `SessionStore.swift` -- @Observable state, persistence, status tracking
- `TerminalManager.swift` -- SwiftTerm integration, terminal buffer status detection
- `EditorDetector.swift` -- multi-editor project detection (Xcode, VS Code, Cursor, JetBrains, Terminal)
- `HotkeyManager.swift` -- configurable global hotkey via CGEventTap
- `CheckpointManager.swift` -- git-based snapshots under refs/leo-snapshots/

## Build
```
swift build
```

## Key Patterns
- Singletons with @Observable for state management
- NSViewRepresentable for SwiftUI-AppKit bridge
- Notification-based communication between components
- CVDisplayLink for frame-rate animations
- CGEventTap for global hotkey capture
- Actor isolation for CheckpointManager and EditorDetector
