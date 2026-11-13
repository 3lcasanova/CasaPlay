// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
//
// Bencode (BitTorrent's encoding). Torrent files, tracker replies and peer
// extension messages all arrive from strangers, so the decoder is strict and bounded.

import Foundation

public indirect enum BValue: Equatable, Sendable {
    case int(Int64)
    case bytes(Data)
    case list([BValue])
    case dict([(key: Data, value: BValue)])

    public static func == (lhs: BValue, rhs: BValue) -> Bool {
        switch (lhs, rhs) {
        case let (.int(a), .int(b)): return a == b
        case let (.bytes(a), .bytes(b)): return a == b
        case let (.list(a), .list(b)): return a == b
        case let (.dict(a), .dict(b)):
            return a.count == b.count && zip(a, b).allSatisfy { $0.key == $1.key && $0.value == $1.value }
        default: return false
        }
    }

    public subscript(key: String) -> BValue? {
        guard case .dict(let pairs) = self else { return nil }
        let k = Data(key.utf8)
        return pairs.first { $0.key == k }?.value
    }

    public var int: Int64? { if case .int(let v) = self { return v } else { return nil } }
    public var data: Data? { if case .bytes(let v) = self { return v } else { return nil } }
    public var list: [BValue]? { if case .list(let v) = self { return v } else { return nil } }
    /// UTF-8 text, or nil when the bytes are not valid UTF-8.
    public var string: String? { data.flatMap { String(data: $0, encoding: .utf8) } }
}

public enum BencodeError: Error, Equatable {
    case truncated
    case invalid(String)
    case tooDeep
    case tooLarge
}

public struct BencodeDecoder {
    public var maxDepth = 64
    public var maxItems = 2_000_000

    public init() {}

    /// Decodes one value and requires that nothing follows it.
    public func decode(_ data: Data) throws -> BValue {
        var parser = Parser(bytes: [UInt8](data), maxDepth: maxDepth, maxItems: maxItems)
        let value = try parser.value(depth: 0)
        guard parser.index == parser.bytes.count else { throw BencodeError.invalid("trailing data") }
        return value
    }

    /// Decodes one value at the start and returns how many bytes it used.
    /// Used for ut_metadata messages, where raw piece data follows the dictionary.
    public func decodePrefix(_ data: Data) throws -> (BValue, Int) {
        var parser = Parser(bytes: [UInt8](data), maxDepth: maxDepth, maxItems: maxItems)
        let value = try parser.value(depth: 0)
        return (value, parser.index)
    }

    /// The exact bytes of the top-level dictionary's value for `key`.
    /// The info-hash must be computed over the original bytes, not a re-encoding.
    public func rawValue(forKey key: String, in data: Data) throws -> Data? {
        var parser = Parser(bytes: [UInt8](data), maxDepth: maxDepth, maxItems: maxItems)
        guard parser.peek() == UInt8(ascii: "d") else { throw BencodeError.invalid("not a dictionary") }
        parser.index += 1
        let wanted = Array(key.utf8)
        while parser.peek() != UInt8(ascii: "e") {
            guard case .bytes(let k) = try parser.value(depth: 1) else { throw BencodeError.invalid("key") }
            let start = parser.index
            _ = try parser.value(depth: 1)
            if Array(k) == wanted {
                return Data(parser.bytes[start..<parser.index])
            }
        }
        return nil
    }

    struct Parser {
        let bytes: [UInt8]
        let maxDepth: Int
        let maxItems: Int
        var index = 0
        var items = 0

        init(bytes: [UInt8], maxDepth: Int, maxItems: Int) {
            self.bytes = bytes
            self.maxDepth = maxDepth
            self.maxItems = maxItems
        }

        func peek() -> UInt8? { index < bytes.count ? bytes[index] : nil }

        mutating func value(depth: Int) throws -> BValue {
            guard depth <= maxDepth else { throw BencodeError.tooDeep }
            items += 1
            guard items <= maxItems else { throw BencodeError.tooLarge }
            guard let c = peek() else { throw BencodeError.truncated }
            switch c {
            case UInt8(ascii: "i"):
                index += 1
                return .int(try integer(until: UInt8(ascii: "e")))
            case UInt8(ascii: "l"):
                index += 1
                var out: [BValue] = []
                while true {
                    guard let n = peek() else { throw BencodeError.truncated }
                    if n == UInt8(ascii: "e") { index += 1; return .list(out) }
                    out.append(try value(depth: depth + 1))
                }
            case UInt8(ascii: "d"):
                index += 1
                var out: [(key: Data, value: BValue)] = []
                while true {
                    guard let n = peek() else { throw BencodeError.truncated }
                    if n == UInt8(ascii: "e") { index += 1; return .dict(out) }
                    guard case .bytes(let key) = try value(depth: depth + 1) else {
                        throw BencodeError.invalid("dictionary key is not a string")
                    }
                    out.append((key, try value(depth: depth + 1)))
                }
            case UInt8(ascii: "0")...UInt8(ascii: "9"):
                let length = try integer(until: UInt8(ascii: ":"))
                guard length >= 0, length <= Int64(bytes.count - index) else { throw BencodeError.truncated }
                let start = index
                index += Int(length)
                return .bytes(Data(bytes[start..<index]))
            default:
                throw BencodeError.invalid("unexpected byte \(c)")
            }
        }

        private mutating func integer(until terminator: UInt8) throws -> Int64 {
            let start = index
            while let c = peek(), c != terminator { index += 1 }
            guard peek() == terminator else { throw BencodeError.truncated }
            let text = String(decoding: bytes[start..<index], as: UTF8.self)
            index += 1
            guard !text.isEmpty, text.count <= 20,
                  text == "0" || !(text.hasPrefix("0") || text.hasPrefix("-0")),
                  let value = Int64(text) else {
                throw BencodeError.invalid("bad integer")
            }
            return value
        }
    }
}

public enum BencodeEncoder {
    public static func encode(_ value: BValue) -> Data {
        var out = Data()
        write(value, into: &out)
        return out
    }

    private static func write(_ value: BValue, into out: inout Data) {
        switch value {
        case .int(let v):
            out.append(contentsOf: Array("i\(v)e".utf8))
        case .bytes(let d):
            out.append(contentsOf: Array("\(d.count):".utf8))
            out.append(d)
        case .list(let items):
            out.append(UInt8(ascii: "l"))
            items.forEach { write($0, into: &out) }
            out.append(UInt8(ascii: "e"))
        case .dict(let pairs):
            out.append(UInt8(ascii: "d"))
            // Keys must be sorted as raw bytes.
            for pair in pairs.sorted(by: { $0.key.lexicographicallyPrecedes($1.key) }) {
                write(.bytes(pair.key), into: &out)
                write(pair.value, into: &out)
            }
            out.append(UInt8(ascii: "e"))
        }
    }
}

extension BValue {
    /// Builds a dictionary from string keys.
    public static func dict(_ pairs: [String: BValue]) -> BValue {
        .dict(pairs.map { (Data($0.key.utf8), $0.value) })
    }

    public static func string(_ s: String) -> BValue { .bytes(Data(s.utf8)) }
}
