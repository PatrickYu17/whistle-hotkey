import Carbon
import Darwin
import Foundation

struct Binding: Codable, Equatable {
    let id: Int
    var command: String
    var keyCode: UInt32
    var modifiers: UInt32
    var terminal: Bool
    var enabled: Bool

    init(id: Int, command: String, keyCode: UInt32, modifiers: UInt32, terminal: Bool = false, enabled: Bool = true) {
        self.id = id
        self.command = command
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.terminal = terminal
        self.enabled = enabled
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        command = try c.decode(String.self, forKey: .command)
        keyCode = try c.decode(UInt32.self, forKey: .keyCode)
        modifiers = try c.decode(UInt32.self, forKey: .modifiers)
        terminal = try c.decodeIfPresent(Bool.self, forKey: .terminal) ?? false
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
    }
}

enum ConfigError: Error, Equatable {
    case badID(Int)
    case duplicateID(Int)
    case badCombo(Int)
    case bareKey(Int)
    case duplicateCombo(Int)
    case missingBinding(Int)
    case lockFailed
}

extension ConfigError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .badID(let id): return "binding id \(id) is out of range"
        case .duplicateID(let id): return "duplicate binding id \(id)"
        case .badCombo(let id): return "binding \(id) has an unknown key code or modifiers"
        case .bareKey(let id): return "binding \(id) uses a bare printable key; add a modifier (only F-keys can be modifier-less)"
        case .duplicateCombo(let id): return "that combination is already assigned to binding \(id)"
        case .missingBinding(let id): return "binding \(id) no longer exists"
        case .lockFailed: return "could not acquire config lock"
        }
    }
}

enum Config {
    static var dir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/whistle-hotkey", isDirectory: true)
    }

    static var fileURL: URL { dir.appendingPathComponent("config.json") }

    static func load(at url: URL = Config.fileURL) throws -> [Binding] {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch let error as NSError
        where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
            return []
        }
        let bindings = try JSONDecoder().decode([Binding].self, from: data)
        try validate(bindings)
        return bindings
    }

    // F-keys are the only keyCodes allowed as global hotkeys without a modifier
    static let bareKeys: Set<UInt32> = [96, 97, 98, 99, 100, 101, 103, 105, 107, 109, 111, 113, 118, 120, 122]

    static func changeHotkey(_ id: Int, keyCode: UInt32, modifiers: UInt32, in bindings: inout [Binding]) throws {
        guard let index = bindings.firstIndex(where: { $0.id == id }) else {
            throw ConfigError.missingBinding(id)
        }
        if let duplicate = bindings.first(where: { $0.id != id && $0.keyCode == keyCode && $0.modifiers == modifiers }) {
            throw ConfigError.duplicateCombo(duplicate.id)
        }
        var updated = bindings[index]
        updated.keyCode = keyCode
        updated.modifiers = modifiers
        try validate([updated])
        bindings[index] = updated
    }

    static func validate(_ bindings: [Binding]) throws {
        let validModifiers = UInt32(cmdKey | shiftKey | optionKey | controlKey)
        var seen = Set<Int>()
        for binding in bindings {
            guard binding.id >= 0, binding.id <= Int(UInt32.max) else { throw ConfigError.badID(binding.id) }
            guard seen.insert(binding.id).inserted else { throw ConfigError.duplicateID(binding.id) }
            guard binding.keyCode < 128, binding.modifiers & ~validModifiers == 0 else {
                throw ConfigError.badCombo(binding.id)
            }
            guard binding.modifiers != 0 || bareKeys.contains(binding.keyCode) else {
                throw ConfigError.bareKey(binding.id)
            }
        }
    }

    static func save(_ bindings: [Binding], at url: URL = Config.fileURL) throws {
        try validate(bindings)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try JSONEncoder().encode(bindings).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    static func locked<T>(_ body: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let fd = open(lockPath.path, O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else { throw ConfigError.lockFailed }
        defer { close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { throw ConfigError.lockFailed }
        return try body()
    }

    private static var lockPath: URL { dir.appendingPathComponent(".cfg.lock") }
}

struct Settings: Codable, Equatable {
    var terminal: String
    var command: String?

    init(terminal: String, command: String? = nil) {
        self.terminal = terminal
        self.command = command
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        terminal = try c.decodeIfPresent(String.self, forKey: .terminal) ?? "auto"
        command = try c.decodeIfPresent(String.self, forKey: .command)
    }
}

enum SettingsStore {
    static var fileURL: URL { Config.dir.appendingPathComponent("settings.json") }

    static func load() -> Settings {
        guard let data = try? Data(contentsOf: fileURL),
              let settings = try? JSONDecoder().decode(Settings.self, from: data) else {
            return Settings(terminal: "auto")
        }
        return settings
    }

    static func save(_ settings: Settings) throws {
        try FileManager.default.createDirectory(at: Config.dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(settings).write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }
}
