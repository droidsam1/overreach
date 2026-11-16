import Foundation

/// Minimal RFC 4180 CSV reader: quoted fields, escaped quotes (`""`), delimiters and line breaks inside
/// quotes, CRLF/LF/CR line endings and a UTF-8 BOM. The delimiter (`,` or `;`) is detected from the header.
enum CSVReader {
    static func rows(from text: String) -> [[String]] {
        let content = text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
        let delimiter = detectDelimiter(in: content)
        return rows(from: content, delimiter: delimiter)
    }

    static func detectDelimiter(in text: String) -> Character {
        let headerLine = text.prefix { $0 != "\n" && $0 != "\r\n" && $0 != "\r" }
        let commas = headerLine.filter { $0 == "," }.count
        let semicolons = headerLine.filter { $0 == ";" }.count
        return semicolons > commas ? ";" : ","
    }

    static func rows(from text: String, delimiter: Character) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        let characters = Array(text)
        var index = 0

        while index < characters.count {
            let character = characters[index]
            if inQuotes {
                if character == "\"" {
                    if index + 1 < characters.count, characters[index + 1] == "\"" {
                        field.append("\"")
                        index += 1
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(character)
                }
            } else if character == "\"" {
                inQuotes = true
            } else if character == delimiter {
                row.append(field)
                field = ""
            } else if character == "\n" || character == "\r\n" || character == "\r" {
                row.append(field)
                rows.append(row)
                row = []
                field = ""
            } else {
                field.append(character)
            }
            index += 1
        }

        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        // Drop blank lines.
        return rows.filter { !($0.count == 1 && $0[0].trimmingCharacters(in: .whitespaces).isEmpty) }
    }
}
