import Foundation

enum Runner {
    private static var lastFired: [Int: Date] = [:]

    static func run(_ binding: Binding) {
        // 500 ms per-binding debounce guards against key-repeat bursts; raise it if deliberate double-fire matters
        let now = Date()
        if let last = lastFired[binding.id], now.timeIntervalSince(last) < 0.5 { return }
        lastFired[binding.id] = now

        if binding.terminal {
            do {
                let settings = SettingsStore.load()
                let backend = Terminals.backend(for: settings.terminal) ?? Terminals.autoDetected()
                try backend.launch(binding.command, settings: settings)
            } catch {
                Notifier.failure("Couldn't open terminal for: \(binding.command): \(error.localizedDescription)")
            }
        } else {
            runHeadless(binding.command)
        }
    }

    private static func runHeadless(_ command: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-ilc", command]
        do {
            try process.run()
        } catch {
            Notifier.failure("Couldn't run command: \(command): \(error.localizedDescription)")
        }
    }
}

enum Notifier {
    static func failure(_ message: String) {
        let escaped = message
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = "display notification \"\(escaped)\" with title \"Whistle-Hotkey\""
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        try? process.run()
    }
}
