import Foundation
import MelodyCore

/// 照片请求不跟随重定向，防止图像被送往用户未配置的地址。
actor NetworkTransport {
    static let shared = NetworkTransport()
    private let session: URLSession
    private init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 40
        config.timeoutIntervalForResource = 45
        config.urlCache = nil
        session = URLSession(configuration: config, delegate: RedirectBlocker(), delegateQueue: nil)
    }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse else { throw CompositionError.malformedResponse }
        guard (200...299).contains(response.statusCode) else { return (Data(), response.statusCode) }
        var data = Data()
        for try await byte in bytes {
            guard data.count < 256_000 else { throw CompositionError.malformedResponse }
            data.append(byte)
        }
        return (data, response.statusCode)
    }
}

private final class RedirectBlocker: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
