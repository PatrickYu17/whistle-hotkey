import AppKit
import Darwin

final class Daemon: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let hotKeys = HotKeyManager()
    private var config: [Binding] = []
    private var conflicts: Set<Int> = []
    private var lastMtime: Date?
    private var timer: Timer?
    private var lockFD: Int32 = -1

    static func run() {
        let daemon = Daemon()
        daemon.start()
    }

    private func start() {
        signal(SIGHUP, SIG_IGN)
        guard acquireLock() else {
            fputs("whistle: already running\n", stderr)
            exit(1)
        }

        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.delegate = self

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.button?.image = NSImage(
            systemSymbolName: "bolt.fill",
            accessibilityDescription: "Whistle-Hotkey"
        )

        hotKeys.installHandler()
        hotKeys.onTrigger = { [weak self] id in
            guard let self, let binding = self.config.first(where: { $0.id == id }) else { return }
            Runner.run(binding)
        }

        reload()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.pollConfig()
        }
        app.run()
    }

    private func acquireLock() -> Bool {
        try? FileManager.default.createDirectory(at: Config.dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let path = Config.dir.appendingPathComponent(".lock").path
        lockFD = open(path, O_CREAT | O_RDWR, 0o600)
        guard lockFD >= 0 else { return false }
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
        return flock(lockFD, LOCK_EX | LOCK_NB) == 0
    }

    private func currentMtime() -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: Config.fileURL.path))?[.modificationDate] as? Date
    }

    private func pollConfig() {
        let mtime = currentMtime()
        if mtime != lastMtime {
            lastMtime = mtime
            reload()
        }
    }

    private func reload() {
        let mtime = currentMtime()
        do {
            config = try Config.load()
        } catch {
            Notifier.failure("Config error: \(error.localizedDescription); keeping previous bindings")
            rebuildMenu()
            return
        }
        lastMtime = mtime
        conflicts = []
        hotKeys.unregisterAll()
        for binding in config where hotKeys.register(binding) != noErr {
            conflicts.insert(binding.id)
        }
        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        if config.isEmpty {
            menu.addItem(withTitle: "No bindings, run: whistle-hotkey bind", action: nil, keyEquivalent: "")
        }
        for binding in config {
            let key = "\(Display.modifiers(binding.modifiers))\(Display.keyName(binding.keyCode))"
            let prefix = "\(binding.terminal ? "⧉ " : "")\(conflicts.contains(binding.id) ? "⚠  " : "")"
            let item = NSMenuItem(
                title: "\(prefix)\(key)  \(binding.command)",
                action: #selector(runFromMenu(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = binding.id
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let reloadItem = NSMenuItem(title: "Reload", action: #selector(reloadAction), keyEquivalent: "")
        reloadItem.target = self
        menu.addItem(reloadItem)
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitAction), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        statusItem?.menu = menu
    }

    @objc private func runFromMenu(_ item: NSMenuItem) {
        guard let id = item.representedObject as? Int,
              let binding = config.first(where: { $0.id == id }) else { return }
        Runner.run(binding)
    }

    @objc private func reloadAction() { reload() }

    @objc private func quitAction() { NSApp.terminate(nil) }
}

enum Detach {
    static func start() {
        try? FileManager.default.createDirectory(at: Config.dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let lockPath = Config.dir.appendingPathComponent(".lock").path
        let fd = open(lockPath, O_CREAT | O_RDWR, 0o600)
        if fd >= 0 {
            let free = flock(fd, LOCK_EX | LOCK_NB) == 0
            close(fd)
            guard free else {
                fputs("whistle: already running\n", stderr)
                exit(1)
            }
        }
        do {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: LaunchAgent.executablePath().path)
            process.arguments = ["--foreground"]
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
        } catch {
            fputs("whistle: failed to start daemon: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
        print("started. Look for the bolt in the menu bar")
    }
}
