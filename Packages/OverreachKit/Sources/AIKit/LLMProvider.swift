import Foundation

// Provider-agnostic AI layer (ADR-0006). The prototype only shares a Markdown report (see `Reports`);
// these types are the contract for the in-app chat in phase 4.

public enum LLMProviderKind: String, Codable, Sendable, CaseIterable {
    /// Default provider.
    case openAI
    case anthropic
    /// Any endpoint that speaks the OpenAI chat API (self-hosted or third-party).
    case openAICompatible
}

public enum LLMRole: String, Codable, Sendable {
    case system, user, assistant
}

public struct LLMMessage: Hashable, Codable, Sendable {
    public var role: LLMRole
    public var content: String

    public init(role: LLMRole, content: String) {
        self.role = role
        self.content = content
    }
}

public struct LLMRequest: Sendable {
    public var model: String
    public var messages: [LLMMessage]
    public var maxOutputTokens: Int?

    public init(model: String, messages: [LLMMessage], maxOutputTokens: Int? = nil) {
        self.model = model
        self.messages = messages
        self.maxOutputTokens = maxOutputTokens
    }
}

public struct LLMResponse: Sendable {
    public var text: String
    /// Token counts when the provider reports them, used for the monthly spend estimate.
    public var inputTokens: Int?
    public var outputTokens: Int?

    public init(text: String, inputTokens: Int? = nil, outputTokens: Int? = nil) {
        self.text = text
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
    }
}

/// One adapter per provider implements this. API keys come from the Keychain, never from code.
public protocol LLMProvider: Sendable {
    var kind: LLMProviderKind { get }
    func complete(_ request: LLMRequest) async throws -> LLMResponse
}
