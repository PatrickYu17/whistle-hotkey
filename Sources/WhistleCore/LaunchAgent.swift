import Darwin
import Foundation

enum LaunchAgent {
    static let label = "com.patrickyu17.whistle-hotkey"

    static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static func install() {
        do {
            let executable = executablePath()
            try FileManager.default.createDirectory(
                at: plistURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let plist = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
                <key>Label</key><string>\(label)</string>
                <key>ProgramArguments</key>
                <array><string>\(xmlEscape(executable.path))</string><string>--foreground</string></array>
                <key>RunAtLoad</key><true/>
                <key>ProcessType</key><string>Interactive</string>
            </dict>
            </plist>
            """
            try plist.write(to: plistURL, atomically: true, encoding: .utf8)
            runLaunchctl(["bootout", "gui/\(getuid())/\(label)"])
            let status = runLaunchctl(["bootstrap", "gui/\(getuid())", plistURL.path])
            guard status == 0 else {
                try? FileManager.default.removeItem(at: plistURL)
                fputs("whistle: launchctl bootstrap failed (status \(status))\n", stderr)
                exit(1)
            }
            print("installed. Whistle-Hotkey starts at login. Remove with: whistle-hotkey uninstall")
        } catch {
            fputs("whistle: install failed: \(error)\n", stderr)
            exit(1)
        }
    }

    static func uninstall() {
        let status = runLaunchctl(["bootout", "gui/\(getuid())/\(label)"])
        if status != 0 {
            fputs("whistle: agent was not loaded (already uninstalled?)\n", stderr)
        }
        do {
            try FileManager.default.removeItem(at: plistURL)
        } catch let error as NSError where error.code == NSFileNoSuchFileError {
        } catch {
            fputs("whistle: failed to remove \(plistURL.path): \(error)\n", stderr)
            exit(1)
        }
        print("uninstalled")
    }

    static func xmlEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    @discardableResult
    private static func runLaunchctl(_ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return -1
        }
        process.waitUntilExit()
        return process.terminationStatus
    }

    static func executablePath() -> URL {
        let argv0 = CommandLine.arguments[0]
        if argv0.hasPrefix("/") {
            return URL(fileURLWithPath: argv0).resolvingSymlinksInPath()
        }
        for dir in (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(dir)).appendingPathComponent(argv0)
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate.resolvingSymlinksInPath()
            }
        }
        return URL(fileURLWithPath: argv0)
    }
}
