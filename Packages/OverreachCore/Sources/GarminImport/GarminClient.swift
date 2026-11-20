import Domain
import Foundation

/// One HTTP request to the Garmin Personal API host.
public struct GarminHTTPRequest: Hashable, Sendable {
    public var method: String
    /// Path and query, e.g. `/hrv-service/hrv/daily/2026-11-01/2026-11-20`.
    public var path: String
    public var headers: [String: String]

    public init(method: String, path: String, headers: [String: String]) {
        self.method = method
        self.path = path
        self.headers = headers
    }
}

public struct GarminHTTPResponse: Sendable {
    public var status: Int
    public var body: Data
    /// Seconds from a `Retry-After` header, if Garmin sent one.
    public var retryAfter: TimeInterval?

    public init(status: Int, body: Data = Data(), retryAfter: TimeInterval? = nil) {
        self.status = status
        self.body = body
        self.retryAfter = retryAfter
    }
}

/// Sends requests to `https://personal.connectapi.garmin.com`. Throws only when no response arrives (offline,
/// timeout). URLSession on the iPhone; a fake in tests.
public protocol GarminTransport: Sendable {
    func send(_ request: GarminHTTPRequest) async throws -> GarminHTTPResponse
}

/// A 24 h access token minted from the key.
public struct GarminToken: Codable, Hashable, Sendable {
    public var value: String
    public var expiresAt: Date

    public init(value: String, expiresAt: Date) {
        self.value = value
        self.expiresAt = expiresAt
    }
}

/// Talks to Garmin politely and safely (Supplemental Terms §2; docs/design/garmin-integration.md):
/// - the key is sent only to the token endpoint; data calls carry the token;
/// - the token is reused until less than an hour is left, and minted again once if Garmin rejects it;
/// - requests are spaced, and 429/427/5xx are retried at most twice with growing, jittered waits that honour
///   `Retry-After`; then the sync stops instead of insisting.
public actor GarminClient {
    public static let tokenRenewalMargin: TimeInterval = 3_600
    public static let minimumSpacing: TimeInterval = 0.3
    public static let retryDelays: [TimeInterval] = [2, 8]

    private let transport: any GarminTransport
    private let clock: @Sendable () -> Date
    private let sleep: @Sendable (TimeInterval) async -> Void
    private let jitter: @Sendable () -> Double
    private var token: GarminToken?
    private var lastRequest: Date?

    public init(
        transport: any GarminTransport,
        token: GarminToken? = nil,
        clock: @escaping @Sendable () -> Date = { Date() },
        sleep: @escaping @Sendable (TimeInterval) async -> Void = { seconds in
            try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
        },
        jitter: @escaping @Sendable () -> Double = { Double.random(in: 0.8...1.2) }
    ) {
        self.transport = transport
        self.token = token
        self.clock = clock
        self.sleep = sleep
        self.jitter = jitter
    }

    /// The token in use, to keep it between launches (only on this device).
    public var currentToken: GarminToken? { token }

    /// Reuses a token saved on a previous launch.
    public func restore(_ saved: GarminToken) {
        token = saved
    }

    /// Exchanges `key` for a token. `keyRejected` means Garmin does not accept the key.
    @discardableResult
    public func mintToken(key: String) async throws(GarminAccountError) -> GarminToken {
        let request = GarminHTTPRequest(
            method: "POST", path: GarminEndpoint.tokenPath,
            headers: ["Authorization": "ApiKey \(key)", "Accept": "*/*"]
        )
        let response = try await send(request)
        switch response.status {
        case 200..<300:
            let value = String(decoding: response.body, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, !value.contains(" ") else { throw .garminUnavailable }
            let minted = GarminToken(
                value: value, expiresAt: Self.expiry(ofJWT: value) ?? clock().addingTimeInterval(86_400)
            )
            token = minted
            return minted
        case 400, 401, 403:
            throw .keyRejected
        default:
            throw Self.error(for: response.status)
        }
    }

    /// The body of `endpoint` (empty for 204: no data).
    public func data(for endpoint: GarminEndpoint, key: String) async throws(GarminAccountError) -> Data {
        var minted = false
        if token == nil || (token?.expiresAt ?? .distantPast) < clock().addingTimeInterval(Self.tokenRenewalMargin) {
            try await mintToken(key: key)
            minted = true
        }
        while true {
            let response = try await send(GarminHTTPRequest(
                method: "GET", path: endpoint.path,
                headers: ["Authorization": "Bearer \(token?.value ?? "")", "Accept": "application/json"]
            ))
            switch response.status {
            case 200..<300:
                return response.status == 204 ? Data() : response.body
            case 401 where !minted:
                // Revoked or expired early: one fresh token, then give up.
                try await mintToken(key: key)
                minted = true
            case 401, 403:
                throw .keyRejected
            default:
                throw Self.error(for: response.status)
            }
        }
    }

    // MARK: Sending

    /// Sends with spacing and bounded retries for rate limits and server errors.
    private func send(_ request: GarminHTTPRequest) async throws(GarminAccountError) -> GarminHTTPResponse {
        var attempt = 0
        while true {
            if let lastRequest {
                let wait = Self.minimumSpacing - clock().timeIntervalSince(lastRequest)
                if wait > 0 { await sleep(wait) }
            }
            lastRequest = clock()
            let response: GarminHTTPResponse
            do {
                response = try await transport.send(request)
            } catch {
                throw .offline
            }
            guard Self.isRetryable(response.status), attempt < Self.retryDelays.count else { return response }
            let delay = response.retryAfter.map { min($0, 60) } ?? Self.retryDelays[attempt] * jitter()
            attempt += 1
            await sleep(delay)
        }
    }

    private static func isRetryable(_ status: Int) -> Bool {
        status == 429 || status == 427 || (500..<600).contains(status)
    }

    private static func error(for status: Int) -> GarminAccountError {
        status == 429 || status == 427 ? .rateLimited : .garminUnavailable
    }

    /// The `exp` claim of a JWT, without checking its signature (Garmin checks it; the app only needs the date).
    static func expiry(ofJWT token: String) -> Date? {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var base64 = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let data = Data(base64Encoded: base64),
            let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let exp = GarminDecoding.number(claims["exp"])
        else { return nil }
        return Date(timeIntervalSince1970: exp)
    }
}
