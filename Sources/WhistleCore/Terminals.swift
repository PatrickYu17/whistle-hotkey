import Foundation

enum Terminals {
    enum Backend: String {
        case ghostty
        case iterm2
        case terminal
        case commandFile = "command-file"
        case custom

        var name: String { rawValue }

        func launch(_ command: String, settings: Settings) throws {
            switch self {
            case .ghostty:
                runAppleScript("""
                tell application "Ghostty"
                  try
                    make new window with configuration {command:(item 1 of argv), wait after command:true}
                  on error errStr number errNum
                    if errNum is not -2710 then error errStr number errNum
                  end try
                end tell
                """, command: command)
            case .iterm2:
                runAppleScript("""
                tell application "iTerm"
                  create window with default profile command (item 1 of argv)
                end tell
                """, command: command)
            case .terminal:
                runAppleScript("""
                tell application "Terminal"
                  do script (item 1 of argv)
                end tell
                """, command: command)
            case .commandFile:
                try launchCommandFile(command)
            case .custom:
                guard let template = settings.command, !template.isEmpty else {
                    throw NSError(domain: "whistle", code: 1, userInfo: [NSLocalizedDescriptionKey: "no custom terminal template set"])
                }
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/zsh")
                process.arguments = ["-ilc", template, "whistle", command]
                try process.run()
            }
        }
    }

    static func backend(for name: String) -> Backend? {
        name == "auto" ? autoDetected() : Backend(rawValue: name)
    }

    static func autoDetected() -> Backend {
        if FileManager.default.fileExists(atPath: "/Applications/Ghostty.app") {
            return .ghostty
        }
        if FileManager.default.fileExists(atPath: "/Applications/iTerm.app") {
            return .iterm2
        }
        return .commandFile
    }

    private static func runAppleScript(_ body: String, command: String) {
        let script = "on run argv\n  \(body)\nend run"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script, command]
        process.terminationHandler = { p in
            guard p.terminationStatus != 0 else { return }
            Notifier.failure("Terminal launch failed: automation denied or the terminal errored")
        }
        do {
            try process.run()
        } catch {
            Notifier.failure("Couldn't run osascript: \(error.localizedDescription)")
            return
        }
    }

    private static func launchCommandFile(_ command: String) throws {
        try FileManager.default.createDirectory(
            at: Config.dir,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let script = Config.dir.appendingPathComponent("run-\(UUID().uuidString).command")
        try "#!/bin/zsh\n\(command)\n".write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        let opener = Process()
        opener.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        opener.arguments = [script.path]
        opener.terminationHandler = { p in
            if p.terminationStatus != 0 {
                Notifier.failure("Couldn't open command file (status \(p.terminationStatus))")
            }
        }
        try opener.run()
        // the file can linger up to 30s; delete right after `open` reads it if that ever matters
        DispatchQueue.global().asyncAfter(deadline: .now() + 30) {
            try? FileManager.default.removeItem(at: script)
        }
    }
}
