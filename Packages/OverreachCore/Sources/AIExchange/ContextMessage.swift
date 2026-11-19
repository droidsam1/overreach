import Foundation

/// How the context travels to the chat app: compact JSON (keys sorted, ISO 8601 dates) and the text to paste.
public enum ContextMessage {
    public static func json(_ pack: ContextPack) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(pack)
    }

    public static func decode(_ data: Data) throws -> ContextPack {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ContextPack.self, from: data)
    }

    /// A one-line header, the JSON in a code block and, if any, the user's request after it.
    public static func text(json: String, request: String?) -> String {
        var text = "Overreach training context (\(ContextPack.formatName) v\(ContextPack.currentVersion))\n\n"
            + "```json\n\(json)\n```"
        if let request, !request.isEmpty {
            text += "\n\n" + request
        }
        return text
    }
}
