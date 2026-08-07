import Foundation
import XCTest

/// Mock URLProtocol that intercepts requests, records them, and returns predefined responses.
final class MockURLProtocol: URLProtocol {

    typealias Handler = (URLRequest) throws -> (HTTPURLResponse, Data)

    private static let lock = NSLock()

    nonisolated(unsafe) private static var handler: Handler?
    nonisolated(unsafe) private(set) static var requests: [URLRequest] = []

    static func setHandler(_ handler: @escaping Handler) {
        lock.lock()
        defer { lock.unlock() }
        Self.handler = handler
    }

    static func reset() {
        lock.lock()
        defer { lock.unlock() }
        handler = nil
        requests.removeAll()
    }

    static func snapshotRequests() -> [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return requests
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        MockURLProtocol.lock.lock()
        MockURLProtocol.requests.append(request)
        let currentHandler = MockURLProtocol.handler
        MockURLProtocol.lock.unlock()

        guard let handler = currentHandler else {
            XCTFail("MockURLProtocol received a request without a configured handler")
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {
        // No-op for mock
    }
}
