import AppKit
import CoreGraphics

class HotkeyManager {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let onToggle: () -> Void

    init(onToggle: @escaping () -> Void) {
        self.onToggle = onToggle
        setupEventTap()
    }

    private func setupEventTap() {
        let eventMask = (1 << CGEventType.keyDown.rawValue)

        let callback: CGEventTapCallBack = { proxy, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userInfo).takeUnretainedValue()
            return manager.handleEvent(proxy: proxy, type: type, event: event)
        }

        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: callback,
            userInfo: userInfo
        )

        guard let eventTap else {
            print("Leo: Failed to create event tap. Grant Accessibility permissions in System Settings.")
            return
        }

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard type == .keyDown else { return Unmanaged.passUnretained(event) }

        let settings = SettingsManager.shared
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags

        let targetKeyCode = settings.hotkeyKeyCode
        let targetModifiers = NSEvent.ModifierFlags(rawValue: UInt(settings.hotkeyModifiers))

        guard keyCode == targetKeyCode else { return Unmanaged.passUnretained(event) }

        let relevantFlags = flags.intersection([.maskShift, .maskControl, .maskAlternate, .maskCommand])
        let targetFlags = CGEventFlags(rawValue: UInt64(targetModifiers.rawValue))
            .intersection([.maskShift, .maskControl, .maskAlternate, .maskCommand])

        guard relevantFlags == targetFlags else { return Unmanaged.passUnretained(event) }

        DispatchQueue.main.async { [weak self] in
            self?.onToggle()
        }

        return nil
    }

    deinit {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }
    }
}
