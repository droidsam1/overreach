import Foundation

/// Finds the first syntax error in JSON text and says where it is, so an AI can fix it: line, column, what was
/// expected and the line itself. `JSONDecoder` only says that the data is invalid, and not the same way on every
/// platform.
enum JSONSyntax {
    struct Problem: Error, Equatable {
        let offset: Int
        let expected: String
    }

    /// "line 3, column 18: expected "," or "}" — `    "name": "Upper A" "focus": "strength",`", or `nil` if valid.
    static func describeProblem(in text: String) -> String? {
        let bytes = Array(text.utf8)
        var parser = Parser(bytes: bytes)
        do {
            try parser.document()
            return nil
        } catch {
            let problem = error as? Problem ?? Problem(offset: 0, expected: "valid JSON")
            return describe(problem, bytes: bytes)
        }
    }

    private static func describe(_ problem: Problem, bytes: [UInt8]) -> String {
        let offset = min(problem.offset, bytes.count)
        let before = bytes[..<offset]
        let line = before.filter { $0 == 0x0A }.count + 1
        let lineStart = (before.lastIndex(of: 0x0A) ?? -1) + 1
        let lineEnd = bytes[offset...].firstIndex(of: 0x0A) ?? bytes.count
        let column = String(decoding: bytes[lineStart..<offset], as: UTF8.self).count + 1
        var excerpt = String(decoding: bytes[lineStart..<lineEnd], as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if excerpt.count > 100 {
            excerpt = String(excerpt.prefix(100)) + "…"
        }
        let found = offset < bytes.count ? "" : " (the text ends there)"
        return "line \(line), column \(column): expected \(problem.expected)\(found) — `\(excerpt)`"
    }

    private struct Parser {
        let bytes: [UInt8]
        var index = 0

        mutating func document() throws {
            skipWhitespace()
            try value()
            skipWhitespace()
            guard index == bytes.count else { throw Problem(offset: index, expected: "the end of the JSON") }
        }

        private var current: UInt8? { index < bytes.count ? bytes[index] : nil }

        private mutating func skipWhitespace() {
            while let byte = current, [0x20, 0x09, 0x0A, 0x0D].contains(byte) {
                index += 1
            }
        }

        private mutating func value() throws {
            guard let byte = current else { throw Problem(offset: index, expected: "a value") }
            switch byte {
            case UInt8(ascii: "{"): try object()
            case UInt8(ascii: "["): try array()
            case UInt8(ascii: "\""): try string()
            case UInt8(ascii: "-"), UInt8(ascii: "0")...UInt8(ascii: "9"): try number()
            case UInt8(ascii: "t"): try literal("true")
            case UInt8(ascii: "f"): try literal("false")
            case UInt8(ascii: "n"): try literal("null")
            default: throw Problem(offset: index, expected: "a value (text in straight double quotes, a number, "
                + "true, false, null, an object or a list)")
            }
        }

        private mutating func object() throws {
            index += 1
            skipWhitespace()
            if current == UInt8(ascii: "}") {
                index += 1
                return
            }
            while true {
                skipWhitespace()
                guard current == UInt8(ascii: "\"") else {
                    let trailing = current == UInt8(ascii: "}")
                    throw Problem(offset: index, expected: trailing
                        ? "a key in double quotes (remove the comma before \"}\")" : "a key in double quotes")
                }
                try string()
                skipWhitespace()
                guard current == UInt8(ascii: ":") else { throw Problem(offset: index, expected: "\":\"") }
                index += 1
                skipWhitespace()
                try value()
                skipWhitespace()
                switch current ?? 0 {
                case UInt8(ascii: ","): index += 1
                case UInt8(ascii: "}"): index += 1; return
                default: throw Problem(offset: index, expected: "\",\" or \"}\"")
                }
            }
        }

        private mutating func array() throws {
            index += 1
            skipWhitespace()
            if current == UInt8(ascii: "]") {
                index += 1
                return
            }
            while true {
                skipWhitespace()
                if current == UInt8(ascii: "]") {
                    throw Problem(offset: index, expected: "a value (remove the comma before \"]\")")
                }
                try value()
                skipWhitespace()
                switch current ?? 0 {
                case UInt8(ascii: ","): index += 1
                case UInt8(ascii: "]"): index += 1; return
                default: throw Problem(offset: index, expected: "\",\" or \"]\"")
                }
            }
        }

        private mutating func string() throws {
            index += 1
            while let byte = current {
                switch byte {
                case UInt8(ascii: "\""):
                    index += 1
                    return
                case UInt8(ascii: "\\"):
                    index += 2
                case 0x00..<0x20:
                    throw Problem(offset: index, expected: "a closing double quote on the same line")
                default:
                    index += 1
                }
            }
            throw Problem(offset: index, expected: "a closing double quote")
        }

        private mutating func number() throws {
            if current == UInt8(ascii: "-") { index += 1 }
            try digits()
            if current == UInt8(ascii: ".") {
                index += 1
                try digits()
            }
            if current == UInt8(ascii: "e") || current == UInt8(ascii: "E") {
                index += 1
                if current == UInt8(ascii: "+") || current == UInt8(ascii: "-") { index += 1 }
                try digits()
            }
        }

        private mutating func digits() throws {
            let start = index
            while let byte = current, (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte) {
                index += 1
            }
            guard index > start else { throw Problem(offset: index, expected: "a digit") }
        }

        private mutating func literal(_ word: String) throws {
            let expected = Array(word.utf8)
            guard index + expected.count <= bytes.count,
                  Array(bytes[index..<index + expected.count]) == expected else {
                throw Problem(offset: index, expected: "a value (\(word)?)")
            }
            index += expected.count
        }
    }
}

/// Any JSON value, to see which fields a message has beyond the ones the format reads.
enum JSONValue: Decodable, Hashable, Sendable {
    case object([String: JSONValue])
    case array([JSONValue])
    case other

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let object = try? container.decode([String: JSONValue].self) {
            self = .object(object)
        } else if let array = try? container.decode([JSONValue].self) {
            self = .array(array)
        } else {
            self = .other
        }
    }
}
