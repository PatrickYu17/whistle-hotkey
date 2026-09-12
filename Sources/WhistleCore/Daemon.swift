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
    private var isCapturingHotkey = false

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
            guard let self, !self.isCapturingHotkey,
                  let binding = self.config.first(where: { $0.id == id && $0.enabled }) else { return }
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
            refreshHotkeys()
            rebuildMenu()
            return
        }
        lastMtime = mtime
        refreshHotkeys()
        rebuildMenu()
    }

    private func refreshHotkeys() {
        conflicts = []
        hotKeys.unregisterAll()
        guard !isCapturingHotkey else { return }
        for binding in config where binding.enabled && hotKeys.register(binding) != noErr {
            conflicts.insert(binding.id)
        }
    }

    private func updateConfig(_ body: (inout [Binding]) throws -> Void) {
        do {
            try Config.locked {
                var config = try Config.load()
                try body(&config)
                try Config.save(config)
            }
            reload()
        } catch {
            Notifier.failure("Config update failed: \(error.localizedDescription)")
        }
    }

    private func mutate(_ id: Int, _ change: (inout Binding) -> Void) {
        updateConfig { config in
            guard let index = config.firstIndex(where: { $0.id == id }) else { return }
            change(&config[index])
        }
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        if config.isEmpty {
            menu.addItem(withTitle: "No bindings, run: whistle-hotkey bind", action: nil, keyEquivalent: "")
        }
        for binding in config {
            let key = "\(Display.modifiers(binding.modifiers))\(Display.keyName(binding.keyCode))"
            let prefix = "\(binding.terminal ? "⧉ " : "")\(conflicts.contains(binding.id) ? "⚠  " : "")"
            var title = "\(prefix)\(key)  \(binding.command)"
            if !binding.enabled {
                title += "  (disabled)"
            }
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            if !binding.enabled {
                item.attributedTitle = NSAttributedString(
                    string: title,
                    attributes: [.foregroundColor: NSColor.secondaryLabelColor]
                )
            }
            let submenu = NSMenu()
            if binding.enabled {
                let runItem = NSMenuItem(title: "Run", action: #selector(runFromMenu(_:)), keyEquivalent: "")
                runItem.target = self
                runItem.representedObject = binding.id
                submenu.addItem(runItem)
            }
            let editItem = NSMenuItem(title: "Edit Command…", action: #selector(editCommand(_:)), keyEquivalent: "")
            editItem.target = self
            editItem.representedObject = binding.id
            submenu.addItem(editItem)
            let hotkeyItem = NSMenuItem(title: "Change Hotkey…", action: #selector(changeHotkey(_:)), keyEquivalent: "")
            hotkeyItem.target = self
            hotkeyItem.representedObject = binding.id
            submenu.addItem(hotkeyItem)
            let toggleItem = NSMenuItem(
                title: binding.enabled ? "Disable" : "Enable",
                action: #selector(toggleEnabled(_:)),
                keyEquivalent: ""
            )
            toggleItem.target = self
            toggleItem.representedObject = binding.id
            submenu.addItem(toggleItem)
            submenu.addItem(.separator())
            let removeItem = NSMenuItem(title: "Remove…", action: #selector(removeBinding(_:)), keyEquivalent: "")
            removeItem.target = self
            removeItem.representedObject = binding.id
            submenu.addItem(removeItem)
            item.submenu = submenu
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
        guard !isCapturingHotkey, let id = item.representedObject as? Int,
              let binding = config.first(where: { $0.id == id && $0.enabled }) else { return }
        Runner.run(binding)
    }

    @objc private func editCommand(_ item: NSMenuItem) {
        guard let id = item.representedObject as? Int,
              let binding = config.first(where: { $0.id == id }) else { return }
        if let command = Dialogs.editCommand(binding) {
            mutate(id) { $0.command = command }
        }
    }

    @objc private func changeHotkey(_ item: NSMenuItem) {
        guard let id = item.representedObject as? Int,
              config.contains(where: { $0.id == id }) else { return }
        let existing = config.filter { $0.id != id }
        isCapturingHotkey = true
        hotKeys.unregisterAll()
        defer {
            isCapturingHotkey = false
            reload()
        }
        if let recorded = HotkeyCapture.record(existing: existing) {
            updateConfig { config in
                try Config.changeHotkey(id, keyCode: recorded.keyCode, modifiers: recorded.modifiers, in: &config)
            }
        }
    }

    @objc private func toggleEnabled(_ item: NSMenuItem) {
        guard let id = item.representedObject as? Int else { return }
        mutate(id) { $0.enabled.toggle() }
    }

    @objc private func removeBinding(_ item: NSMenuItem) {
        guard let id = item.representedObject as? Int,
              let binding = config.first(where: { $0.id == id }) else { return }
        guard Dialogs.confirmRemove(binding) else { return }
        updateConfig { config in
            config.removeAll { $0.id == id }
        }
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
