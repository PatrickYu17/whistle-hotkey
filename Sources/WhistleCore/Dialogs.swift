import AppKit

enum Dialogs {
    /// Returns the edited command, or nil if the user cancelled.
    static func editCommand(_ binding: Binding) -> String? {
        let glyph = "\(Display.modifiers(binding.modifiers))\(Display.keyName(binding.keyCode))"
        let alert = NSAlert()
        alert.messageText = "Edit \(glyph)"
        alert.informativeText = "Update the command for this hotkey."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.last?.keyEquivalent = "\u{1b}"

        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 480, height: 160))
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 480, height: 160))
        textView.isEditable = true
        textView.isRichText = false
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.string = binding.command
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        scroll.documentView = textView
        alert.accessoryView = scroll

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return nil }
        let trimmed = textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            let errorAlert = NSAlert()
            errorAlert.messageText = "Command can't be empty."
            errorAlert.alertStyle = .warning
            errorAlert.addButton(withTitle: "OK")
            NSApp.activate(ignoringOtherApps: true)
            errorAlert.runModal()
            return nil
        }
        return trimmed
    }

    /// Returns true if the user confirmed removal.
    static func confirmRemove(_ binding: Binding) -> Bool {
        let glyph = "\(Display.modifiers(binding.modifiers))\(Display.keyName(binding.keyCode))"
        let alert = NSAlert()
        alert.messageText = "Remove this binding?"
        alert.informativeText = "\(glyph) → \(binding.command.split(separator: "\n").first ?? "")"
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.last?.keyEquivalent = "\u{1b}"
        alert.buttons.first?.hasDestructiveAction = true
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        return response == .alertFirstButtonReturn
    }
}