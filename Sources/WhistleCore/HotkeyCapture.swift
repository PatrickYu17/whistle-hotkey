import AppKit
import Carbon

/// Maps Cocoa modifier flags to the Carbon modifier mask used by the config.
enum CarbonMask {
    static func from(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var mask: UInt32 = 0
        if flags.contains(.control) { mask |= UInt32(controlKey) }
        if flags.contains(.option) { mask |= UInt32(optionKey) }
        if flags.contains(.shift) { mask |= UInt32(shiftKey) }
        if flags.contains(.command) { mask |= UInt32(cmdKey) }
        return mask
    }
}

enum HotkeyCapture {
    /// Shows a modal capture panel. Returns the recorded (keyCode, modifiers),
    /// or nil if the user pressed Esc to cancel.
    static func record(for binding: Binding, existing: [Binding]) -> (keyCode: UInt32, modifiers: UInt32)? {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 120),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        panel.title = "Change Hotkey"
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false

        let label = NSTextField(labelWithString: "Press the key combination…  (Esc to cancel)")
        label.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 120))
        content.addSubview(label)
        panel.contentView = content
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: content.leadingAnchor, constant: 20),
            label.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -20),
        ])

        var result: (keyCode: UInt32, modifiers: UInt32)? = nil

        NSApp.activate(ignoringOtherApps: true)
        panel.center()
        panel.makeKeyAndOrderFront(nil)

        let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let modifiers = CarbonMask.from(event.modifierFlags)

            // Esc cancels
            if event.keyCode == 53 {
                NSApp.stopModal()
                return nil
            }

            // Modifier keys themselves (⌘ 55, ⇧ 56, ⌥ 58, ⌃ 59) are not hotkey keys
            if [55, 56, 58, 59].contains(event.keyCode) {
                return nil
            }

            // Bare Return, Tab, and arrows are not valid global hotkeys
            if modifiers == 0 && [36, 48, 123, 124, 125, 126].contains(event.keyCode) {
                return nil
            }

            // A modifier is required unless the key is an F-key
            if modifiers == 0 && !Self.bareKeys.contains(UInt32(event.keyCode)) {
                label.stringValue = "Add a modifier (⌃⌥⇧⌘), or use an F-key"
                return nil
            }

            if existing.contains(where: { $0.keyCode == UInt32(event.keyCode) && $0.modifiers == modifiers }) {
                label.stringValue = "Already bound to another hotkey"
                return nil
            }

            // Probe whether another app already owns the combo (mirrors the CLI's bind flow)
            let probe = HotKeyManager()
            let probeBinding = Binding(
                id: Int(UInt32.max) - 1,
                command: "",
                keyCode: UInt32(event.keyCode),
                modifiers: modifiers
            )
            let status = probe.register(probeBinding)
            probe.unregisterAll()
            if status == eventHotKeyExistsErr {
                let alert = NSAlert()
                alert.messageText = "Combo may be taken"
                alert.informativeText = "That combination is registered by another app; the binding may not fire. Use it anyway?"
                alert.addButton(withTitle: "Use it anyway")
                alert.addButton(withTitle: "Cancel")
                alert.buttons.last?.keyEquivalent = "\u{1b}"
                NSApp.activate(ignoringOtherApps: true)
                let response = alert.runModal()
                guard response == .alertFirstButtonReturn else {
                    label.stringValue = "Press the key combination…  (Esc to cancel)"
                    return nil
                }
            }

            result = (UInt32(event.keyCode), modifiers)
            NSApp.stopModal()
            return nil
        }

        defer {
            if let monitor { NSEvent.removeMonitor(monitor) }
            NSApp.stopModal()
            panel.orderOut(nil)
        }

        NSApp.runModal(for: panel)
        return result
    }

    // F-keys are the only keyCodes allowed as global hotkeys without a modifier
    // (mirrors Config.bareKeys)
    private static let bareKeys: Set<UInt32> = [96, 97, 98, 99, 100, 101, 103, 105, 107, 109, 111, 113, 118, 120, 122]
}