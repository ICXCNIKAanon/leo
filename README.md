# Leo

**Get back to shipping.** Claude Code in your MacBook notch.

Leo is a macOS menu bar app that puts a Claude Code terminal right in your notch. Hover to reveal, click to pin, ship faster.

## Features

- **Notch integration** -- lives in your MacBook notch. Hover to reveal the terminal panel.
- **Multi-editor detection** -- Automatically detects projects from Xcode, VS Code, Cursor, JetBrains, and Terminal.
- **Multi-session tabs** -- Run multiple Claude Code sessions in separate tabs.
- **Status visualization** -- Crystal ball glows amber (working), red (needs input), gold (complete).
- **Git checkpoints** -- Cmd+S snapshots your project before Claude makes changes. One-click restore.
- **Configurable hotkey** -- Set your own global shortcut to toggle the panel.
- **Notification sounds** -- Subtle audio cue when Claude completes a task.

## Requirements

- macOS 14.0+ (Sonoma)
- Claude Code CLI installed

## Building

```
swift build
```

Or open in Xcode: add SwiftTerm package via File > Add Package Dependencies > `https://github.com/migueldeicaza/SwiftTerm.git`

## Usage

1. Launch Leo
2. Hover over the notch (or use your hotkey) to reveal the terminal
3. Leo auto-detects your open projects and creates tabs
4. Click + to create a new session manually
5. Pin the panel to keep it visible
6. Cmd+S to create a git checkpoint before risky changes

## License

MIT
