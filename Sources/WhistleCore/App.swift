import Carbon
import Darwin
import Foundation

public enum WhistleEntry {
    static let version = "0.1.0"

    static let usage = """
    whistle-hotkey: global hotkey launcher

      whistle-hotkey              start the daemon (detached)
      whistle-hotkey --foreground run the daemon in this terminal
      whistle-hotkey bind         bind a command to a key combination
      whistle-hotkey list         list bindings
      whistle-hotkey rm <id>      remove a binding
      whistle-hotkey terminal     show or set the terminal app
      whistle-hotkey install      start at login (LaunchAgent)
      whistle-hotkey uninstall    stop starting at login
    """

    public static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        switch args.first {
        case "bind":
            Bind.run()
        case "list":
            List.run()
        case "rm":
            Remove.run(args.dropFirst().first)
        case "terminal":
            TerminalCommand.run(args.dropFirst().first, args.dropFirst().dropFirst().first)
        case "install":
            LaunchAgent.install()
        case "uninstall":
            LaunchAgent.uninstall()
        case "version", "-v", "--version":
            print("whistle-hotkey \(version)")
        case "--foreground":
            Daemon.run()
        case "help", "-h", "--help":
            print(usage)
        case nil:
            Detach.start()
        default:
            fputs("unknown command: \(args.first ?? "")\n\n\(usage)", stderr)
            exit(2)
        }
    }
}

enum TerminalCommand {
    static func run(_ arg: String?, _ templateArg: String?) {
        guard let arg else {
            let settings = SettingsStore.load()
            print(settings.terminal + (settings.command.map { " \($0)" } ?? ""))
            return
        }
        if arg == "custom" {
            guard let template = templateArg, !template.isEmpty else {
                print(#"usage: whistle-hotkey terminal custom '<launch template>'"#)
                print(#"template runs via zsh; "$1" is your command, e.g.: kitty --hold zsh -ilc "$1""#)
                exit(1)
            }
            do {
                try SettingsStore.save(Settings(terminal: "custom", command: template))
                print("terminal set to custom: \(template)")
            } catch {
                fputs("whistle: failed to save settings: \(error)\n", stderr)
                exit(1)
            }
            return
        }
        guard Terminals.backend(for: arg) != nil else {
            print("unknown terminal: \(arg)")
            print(#"options: auto, ghostty, iterm2, terminal, command-file, custom '<template with "$1">'"#)
            exit(1)
        }
        do {
            try SettingsStore.save(Settings(terminal: arg))
            print("terminal set to: \(arg)")
        } catch {
            fputs("whistle: failed to save settings: \(error)\n", stderr)
            exit(1)
        }
    }
}

enum Bind {
    static func run() {
        print("Command to run (multiple lines allowed):")
        print("End with a blank line (or Ctrl-D):")
        var lines: [String] = []
        while let line = readLine() {
            if line.isEmpty { break }
            lines.append(line)
        }
        guard !lines.isEmpty else {
            print("cancelled, no command")
            return
        }
        let command = lines.joined(separator: "\n")

        print("Press your key combination now (Esc cancels):")
        guard let (keyCode, modifiers) = Recorder.record() else {
            print("cancelled (Esc, or a combo this terminal can't express, e.g. Cmd)")
            return
        }

        print("Run in a visible terminal window? [y/N]")
        let terminal = readLine()?.lowercased().hasPrefix("y") ?? false

        do {
            try Config.locked {
                var config = try Config.load()
                if let duplicate = config.first(where: {
                    $0.keyCode == keyCode && $0.modifiers == modifiers
                }) {
                    let key = "\(Display.modifiers(modifiers))\(Display.keyName(keyCode))"
                    print("already bound: \(key) → \(duplicate.command)")
                    return
                }
                let id = (config.map(\.id).max() ?? 0) + 1
                let binding = Binding(id: id, command: command, keyCode: keyCode, modifiers: modifiers, terminal: terminal)

                let probe = HotKeyManager()
                let status = probe.register(binding)
                probe.unregisterAll()
                if status == eventHotKeyExistsErr {
                    fputs("⚠  warning: that combo is registered by another app; the binding may not fire.\n", stderr)
                } else if status != noErr {
                    fputs("⚠  warning: registering that combo failed (status \(status)); the binding may not fire.\n", stderr)
                }

                config.append(binding)
                try Config.save(config)
                let key = "\(Display.modifiers(modifiers))\(Display.keyName(keyCode))"
                print("bound: \(key) → \(command)\(terminal ? "  [terminal]" : "")")
            }
        } catch {
            fputs("whistle: failed to update config: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}

enum List {
    static func run() {
        let config: [Binding]
        do {
            config = try Config.load()
        } catch {
            fputs("whistle: failed to read config: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
        if config.isEmpty {
            print("no bindings, run: whistle-hotkey bind")
            return
        }
        for binding in config {
            let key = "\(Display.modifiers(binding.modifiers))\(Display.keyName(binding.keyCode))"
            print("\(binding.id)\t\(key)\t\(binding.command)\(binding.terminal ? "\t[terminal]" : "")")
        }
    }
}

enum Remove {
    static func run(_ idArg: String?) {
        guard let idArg, let id = Int(idArg) else {
            print("usage: whistle-hotkey rm <id>")
            exit(1)
        }
        do {
            try Config.locked {
                var config = try Config.load()
                let before = config.count
                config.removeAll { $0.id == id }
                guard config.count != before else {
                    print("no binding with id \(id)")
                    return
                }
                try Config.save(config)
                print("removed binding \(id)")
            }
        } catch {
            fputs("whistle: failed to update config: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}
