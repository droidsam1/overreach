import Foundation
import GarminImport
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// HTTPS to `personal.connectapi.garmin.com`, straight from the iPhone. An ephemeral session: no cookies, no cache, so
/// nothing of the key or the token is written to disk by URLSession.
public struct URLSessionGarminTransport: GarminTransport {
    private let session: URLSession

    public init(timeout: TimeInterval = 30) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout * 4
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        session = URLSession(configuration: configuration)
    }

    public func send(_ request: GarminHTTPRequest) async throws -> GarminHTTPResponse {
        guard let url = URL(string: "https://\(GarminEndpoint.host)\(request.path)") else {
            throw URLError(.badURL)
        }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method
        for (field, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: field)
        }
        let (data, response) = try await session.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
        return GarminHTTPResponse(status: http.statusCode, body: data, retryAfter: retryAfter)
    }
}
