import Carbon
import Darwin
import Foundation

enum ParsedKey: Equatable {
    case key(UInt32, UInt32)
    case incomplete
    case invalid
}

enum Recorder {
    private static var savedTermios = termios()
    private static var savedFD: Int32 = 0

    private static func restoreTerminal(_ sig: Int32) {
        tcsetattr(savedFD, TCSANOW, &savedTermios)
        tcflush(savedFD, TCIFLUSH)
        signal(sig, SIG_DFL)
        raise(sig)
    }

    static func record() -> (keyCode: UInt32, modifiers: UInt32)? {
        guard isatty(STDIN_FILENO) == 1 else {
            fputs("whistle: bind needs an interactive terminal\n", stderr)
            return nil
        }
        guard tcgetattr(STDIN_FILENO, &savedTermios) == 0 else {
            fputs("whistle: cannot read terminal state\n", stderr)
            return nil
        }
        savedFD = STDIN_FILENO
        for sig in [SIGINT, SIGTERM, SIGHUP] {
            signal(sig) { sig in Recorder.restoreTerminal(sig) }
        }
        var raw = savedTermios
        cfmakeraw(&raw)
        raw.c_lflag |= UInt(ISIG)
        guard tcsetattr(STDIN_FILENO, TCSANOW, &raw) == 0 else {
            fputs("whistle: cannot enable raw mode\n", stderr)
            return nil
        }
        defer {
            for sig in [SIGINT, SIGTERM, SIGHUP] { signal(sig, SIG_DFL) }
            tcsetattr(STDIN_FILENO, TCSANOW, &savedTermios)
            tcflush(STDIN_FILENO, TCIFLUSH)
        }
        return readKeystroke()
    }

    static func parse(_ buf: [UInt8]) -> ParsedKey {
        guard let first = buf.first else { return .incomplete }
        guard first == 0x1B else {
            guard buf.count == 1 else { return .invalid }
            return singleByte(first)
        }
        guard buf.count >= 2 else { return .incomplete }
        switch buf[1] {
        case 0x1B:
            switch parse(Array(buf.dropFirst())) {
            case .key(let kc, let m): return .key(kc, m | UInt32(optionKey))
            case let other: return other
            }
        case 0x5B: return csi(Array(buf.dropFirst(2)))
        case 0x4F: return ss3(Array(buf.dropFirst(2)))
        default:
            guard buf.count == 2, case .key(let kc, let m) = singleByte(buf[1]) else { return .invalid }
            return .key(kc, m | UInt32(optionKey))
        }
    }

    private static func readKeystroke() -> (UInt32, UInt32)? {
        guard let first = readByte() else { return nil }
        var buf = [first]
        while true {
            switch parse(buf) {
            case .key(let keyCode, let modifiers):
                return (keyCode, modifiers)
            case .invalid:
                return nil
            case .incomplete:
                if buf.count == 1 {
                    // 250 ms window after a lone Esc: long enough for chunked
                    // escape sequences, short enough that Esc-cancel feels instant
                    guard inputPending(250) else { return nil }
                }
                guard let next = readByte() else { return nil }
                buf.append(next)
            }
        }
    }

    private static func singleByte(_ b: UInt8) -> ParsedKey {
        switch b {
        case 0x0D, 0x0A: return .key(36, 0)
        case 0x09: return .key(48, 0)
        case 0x7F: return .key(51, 0)
        case 0x00: return .key(49, UInt32(controlKey))
        case 0x01...0x1A:
            guard let kc = letters[Character(UnicodeScalar(0x60 + b))] else { return .invalid }
            return .key(kc, UInt32(controlKey))
        case 0x20: return .key(49, 0)
        default:
            guard b > 0x20, let (kc, shift) = keyFromChar(Character(UnicodeScalar(b))) else { return .invalid }
            return .key(kc, shift ? UInt32(shiftKey) : 0)
        }
    }

    private static func csi(_ bytes: [UInt8]) -> ParsedKey {
        var param = ""
        for b in bytes {
            if (0x30...0x39).contains(b) || b == 0x3B {
                param.append(Character(UnicodeScalar(b)))
                continue
            }
            guard (0x40...0x7E).contains(b) else { return .invalid }
            return finishCSI(final: b, param: param)
        }
        return .incomplete
    }

    private static func finishCSI(final: UInt8, param: String) -> ParsedKey {
        let values = param.split(separator: ";").map { Int($0) ?? 0 }
        var mods: UInt32 = 0
        if values.count > 1, values[1] > 1 {
            let m = values[1] - 1
            if m & 1 != 0 { mods |= UInt32(shiftKey) }
            if m & 2 != 0 { mods |= UInt32(optionKey) }
            if m & 4 != 0 { mods |= UInt32(controlKey) }
        }
        switch final {
        case 0x41: return .key(126, mods)
        case 0x42: return .key(125, mods)
        case 0x43: return .key(124, mods)
        case 0x44: return .key(123, mods)
        case 0x48: return .key(115, mods)
        case 0x46: return .key(119, mods)
        case 0x5A: return .key(48, UInt32(shiftKey))
        case 0x7E:
            let codes: [Int: UInt32] = [
                2: 114, 3: 117, 5: 116, 6: 121,
                15: 96, 17: 97, 18: 98, 19: 100, 20: 101, 21: 109, 23: 103, 24: 111,
            ]
            guard let code = values.first, let kc = codes[code] else { return .invalid }
            return .key(kc, mods)
        default: return .invalid
        }
    }

    private static func ss3(_ bytes: [UInt8]) -> ParsedKey {
        guard let b = bytes.first else { return .incomplete }
        switch b {
        case 0x50: return .key(122, 0)
        case 0x51: return .key(120, 0)
        case 0x52: return .key(99, 0)
        case 0x53: return .key(118, 0)
        case 0x41: return .key(126, 0)
        case 0x42: return .key(125, 0)
        case 0x43: return .key(124, 0)
        case 0x44: return .key(123, 0)
        case 0x48: return .key(115, 0)
        case 0x46: return .key(119, 0)
        default: return .invalid
        }
    }

    private static func readByte() -> UInt8? {
        var b: UInt8 = 0
        return read(STDIN_FILENO, &b, 1) == 1 ? b : nil
    }

    private static func inputPending(_ ms: Int32 = 50) -> Bool {
        var pfd = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0)
        return poll(&pfd, 1, ms) > 0
    }

    static func keyFromChar(_ ch: Character) -> (UInt32, Bool)? {
        if let k = letters[ch] { return (k, false) }
        if let k = basePunctuation[ch] { return (k, false) }
        if let k = digits[ch] { return (k, false) }
        if let k = shiftedPunctuation[ch] { return (k, true) }
        if ch.isUppercase, let k = letters[Character(ch.lowercased())] { return (k, true) }
        return nil
    }

    private static let letters: [Character: UInt32] = [
        "a": 0, "b": 11, "c": 8, "d": 2, "e": 14, "f": 3, "g": 5, "h": 4,
        "i": 34, "j": 38, "k": 40, "l": 37, "m": 46, "n": 45, "o": 31, "p": 35,
        "q": 12, "r": 15, "s": 1, "t": 17, "u": 32, "v": 9, "w": 13, "x": 7,
        "y": 16, "z": 6,
    ]

    private static let digits: [Character: UInt32] = [
        "1": 18, "2": 19, "3": 20, "4": 21, "5": 23, "6": 22, "7": 26, "8": 28, "9": 25, "0": 29,
    ]

    private static let basePunctuation: [Character: UInt32] = [
        "-": 27, "=": 24, "[": 33, "]": 30, "\\": 42, ";": 41, "'": 39, ",": 43, ".": 47, "/": 44, "`": 50,
    ]

    private static let shiftedPunctuation: [Character: UInt32] = [
        "_": 27, "+": 24, "{": 33, "}": 30, "|": 42, ":": 41, "\"": 39, "<": 43, ">": 47, "?": 44, "~": 50,
        "!": 18, "@": 19, "#": 20, "$": 21, "%": 23, "^": 22, "&": 26, "*": 28, "(": 25, ")": 29,
    ]
}
