import Carbon
import Darwin
import Foundation
@testable import WhistleCore

var ran = 0
var failures = 0

func check(_ condition: @autoclosure () -> Bool, _ name: String) {
    ran += 1
    if !condition() {
        failures += 1
        fputs("FAIL: \(name)\n", stderr)
    }
}

func expectThrow<E: Error & Equatable>(_ expected: E, _ name: String, _ body: () throws -> Any) {
    ran += 1
    do {
        _ = try body()
        failures += 1
        fputs("FAIL: \(name): did not throw\n", stderr)
    } catch let error as E where error == expected {
    } catch {
        failures += 1
        fputs("FAIL: \(name): got \(error)\n", stderr)
    }
}

func key(_ bytes: UInt8...) -> ParsedKey {
    Recorder.parse(bytes)
}

check(key(0x1B, 0x5B, 0x41) == .key(126, 0), "plain up arrow")
check(key(0x1B, 0x5B, 0x42) == .key(125, 0), "plain down arrow")
check(key(0x1B, 0x5B, 0x43) == .key(124, 0), "plain right arrow")
check(key(0x1B, 0x5B, 0x44) == .key(123, 0), "plain left arrow")
check(key(0x1B, 0x4F, 0x41) == .key(126, 0), "SS3 up arrow")
check(key(0x1B, 0x4F, 0x44) == .key(123, 0), "SS3 left arrow")

check(key(0x1B, 0x5B, 0x31, 0x3B, 0x35, 0x41) == .key(126, UInt32(controlKey)), "ctrl+up")
check(key(0x1B, 0x5B, 0x31, 0x3B, 0x32, 0x43) == .key(124, UInt32(shiftKey)), "shift+right")
check(key(0x1B, 0x5B, 0x31, 0x3B, 0x33, 0x44) == .key(123, UInt32(optionKey)), "option+left")

check(key(0x1B, 0x1B, 0x5B, 0x41) == .key(126, UInt32(optionKey)), "option+up via double escape")
check(key(0x1B, 0x6F) == .key(31, UInt32(optionKey)), "option+o")

check(key(0x1B, 0x4F, 0x50) == .key(122, 0), "F1")
check(key(0x1B, 0x4F, 0x53) == .key(118, 0), "F4")
check(key(0x1B, 0x5B, 0x31, 0x35, 0x7E) == .key(96, 0), "F5")
check(key(0x1B, 0x5B, 0x32, 0x31, 0x7E) == .key(109, 0), "F10")
check(key(0x1B, 0x5B, 0x33, 0x3B, 0x35, 0x7E) == .key(117, UInt32(controlKey)), "ctrl+delete")

check(key(0x1B, 0x5B, 0x48) == .key(115, 0), "home")
check(key(0x1B, 0x5B, 0x46) == .key(119, 0), "end")
check(key(0x1B, 0x5B, 0x35, 0x7E) == .key(116, 0), "page up")
check(key(0x1B, 0x5B, 0x33, 0x7E) == .key(117, 0), "delete")
check(key(0x1B, 0x5B, 0x5A) == .key(48, UInt32(shiftKey)), "shift+tab")

check(key(0x5B) == .key(33, 0), "literal [ does not block")
check(key(0x4F) == .key(31, UInt32(shiftKey)), "literal O does not block")
check(key(0x61) == .key(0, 0), "literal a")

check(key(0x1B) == .incomplete, "lone escape waits")
check(key(0x1B, 0x5B) == .incomplete, "csi prefix waits")
check(key(0x1B, 0x4F) == .incomplete, "ss3 prefix waits")
check(key(0x1B, 0x1B) == .incomplete, "double escape waits")
check(key(0x1B, 0x5B, 0x31, 0x32, 0x7E) == .invalid, "unknown tilde code invalid")
check(key(0x1B, 0x4F, 0x5A) == .invalid, "unknown ss3 final invalid")

check(key(0x01) == .key(0, UInt32(controlKey)), "ctrl+a")
check(key(0x0D) == .key(36, 0), "return")
check(key(0x09) == .key(48, 0), "tab")
check(key(0x7F) == .key(51, 0), "backspace")

check(Recorder.keyFromChar("o")?.0 == 31, "key map o")
check(Recorder.keyFromChar("O")?.1 == true, "key map shift+o")
check(Recorder.keyFromChar(">")?.0 == 47, "key map >")
check(Recorder.keyFromChar(">")?.1 == true, "key map > is shifted")
check(Recorder.keyFromChar("?")?.0 == 44, "key map ?")
check(Recorder.keyFromChar("é") == nil, "key map rejects non-US")

func tempURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("whistle-tests-\(UUID().uuidString).json")
}

func write(_ json: String) -> URL {
    let url = tempURL()
    try! Data(json.utf8).write(to: url)
    return url
}

check((try? Config.load(at: tempURL())) == [], "missing config loads empty")

let roundTrip = [Binding(id: 1, command: "opencode\n--continue", keyCode: 31, modifiers: 4608, terminal: true)]
do {
    let url = tempURL()
    try Config.save(roundTrip, at: url)
    check((try? Config.load(at: url)) == roundTrip, "config round-trip")
    let permissions = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.posixPermissions] as? NSNumber
    check(permissions?.uint16Value == 0o600, "config saved with 0600")
}

do {
    let url = tempURL()
    try Data("not json".utf8).write(to: url)
    ran += 1
    do {
        _ = try Config.load(at: url)
        failures += 1
        fputs("FAIL: corrupt config throws\n", stderr)
    } catch {}
}

check((try? Config.load(at: write(#"[{"id":2,"command":"ls","keyCode":0,"modifiers":256}]"#)))?.first?.terminal == false, "legacy binding without terminal")

expectThrow(ConfigError.badID(-1), "negative id rejected") {
    try Config.load(at: write(#"[{"id":-1,"command":"ls","keyCode":0,"modifiers":4096,"terminal":false}]"#))
}
expectThrow(ConfigError.badID(5_000_000_000), "oversized id rejected") {
    try Config.load(at: write(#"[{"id":5000000000,"command":"ls","keyCode":0,"modifiers":4096,"terminal":false}]"#))
}
expectThrow(ConfigError.duplicateID(1), "duplicate id rejected") {
    try Config.load(at: write(#"[{"id":1,"command":"ls","keyCode":0,"modifiers":4096,"terminal":false},{"id":1,"command":"pwd","keyCode":11,"modifiers":4096,"terminal":false}]"#))
}
expectThrow(ConfigError.badCombo(1), "unknown key code rejected") {
    try Config.load(at: write(#"[{"id":1,"command":"ls","keyCode":200,"modifiers":0,"terminal":false}]"#))
}
expectThrow(ConfigError.badCombo(1), "unknown modifier bit rejected") {
    try Config.load(at: write(#"[{"id":1,"command":"ls","keyCode":0,"modifiers":1,"terminal":false}]"#))
}
expectThrow(ConfigError.bareKey(1), "bare printable key rejected") {
    try Config.load(at: write(#"[{"id":1,"command":"ls","keyCode":0,"modifiers":0,"terminal":false}]"#))
}
check((try? Config.load(at: write(#"[{"id":1,"command":"ls","keyCode":122,"modifiers":0,"terminal":false}]"#)))?.count == 1, "bare F-key allowed")
expectThrow(ConfigError.bareKey(1), "bare arrow rejected") {
    try Config.load(at: write(#"[{"id":1,"command":"ls","keyCode":123,"modifiers":0,"terminal":false}]"#))
}

let legacySettings = try? JSONDecoder().decode(Settings.self, from: Data(#"{"terminal":"auto"}"#.utf8))
check(legacySettings?.terminal == "auto", "settings legacy terminal")
check(legacySettings?.command == nil, "settings legacy command")

check(Terminals.backend(for: "ghostty")?.name == "ghostty", "terminal registry ghostty")
check(Terminals.backend(for: "iterm2")?.name == "iterm2", "terminal registry iterm2")
check(Terminals.backend(for: "terminal")?.name == "terminal", "terminal registry terminal")
check(Terminals.backend(for: "command-file")?.name == "command-file", "terminal registry command-file")
check(Terminals.backend(for: "custom")?.name == "custom", "terminal registry custom")
check(Terminals.backend(for: "bogus") == nil, "terminal registry rejects unknown")
check(Terminals.autoDetected().name.isEmpty == false, "auto-detect returns a backend")

if failures > 0 {
    exit(1)
}
print("\(ran) tests passed")
