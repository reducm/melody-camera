import Foundation
import MelodyCore

/// 与生图运行时无关的异步作业协议，Draw Things 由 Mac 适配服务执行。
struct ReferenceImageClient: ReferenceImageGenerating {
    let endpoint: String
    let token: String
    func generate(_ request:ReferenceImageRequest,jpeg:Data,progress:@escaping @Sendable (ReferenceRemoteStatus) async -> Void) async throws -> Data {
        guard let base = URL(string:endpoint), let host=base.host, !host.isEmpty,
              ["http","https"].contains(base.scheme), base.user == nil, base.password == nil,
              base.query == nil, base.fragment == nil, !token.isEmpty, jpeg.count <= 2_000_000 else { throw ReferenceFailure.configuration }
        // 不把带凭据请求重定向到其他目标，不把照片正文写到缓存。
        let delegate = ReferenceSessionDelegate()
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30; config.timeoutIntervalForResource = 60
        let session = URLSession(configuration:config,delegate:delegate,delegateQueue:nil)
        defer { session.invalidateAndCancel() }
        let path = "v1/reference-jobs/" + request.id.uuidString
        func call(_ path:String,method:String="GET",body:Data?=nil,limit:Int=8_000_000) async throws -> Data {
            var req=URLRequest(url:base.appendingPathComponent(path))
            req.httpMethod=method; req.httpBody=body
            req.setValue("Bearer " + token,forHTTPHeaderField:"Authorization")
            if body != nil { req.setValue("application/json",forHTTPHeaderField:"Content-Type") }
            let (bytes,response)=try await session.bytes(for:req)
            guard let response=response as? HTTPURLResponse,(200...299).contains(response.statusCode),response.expectedContentLength <= limit else { throw ReferenceFailure.failed }
            var data=Data()
            for try await byte in bytes { guard data.count < limit else { throw ReferenceFailure.invalidResponse }; data.append(byte) }
            return data
        }
        let body = try JSONSerialization.data(withJSONObject:["id":request.id.uuidString,"prompt":request.prompt,"image":jpeg.base64EncodedString()])
        do {
            _ = try await call("v1/reference-jobs",method:"POST",body:body,limit:65536)
            for _ in 0..<1800 {
                try Task.checkCancellation()
                let status=try JSONDecoder().decode(ReferenceRemoteStatus.self,from:try await call(path,limit:65536)).validated(for:request.id)
                await progress(status)
                switch status.state {
                case .ready: return try await call(path + "/image")
                case .failed: throw ReferenceFailure.failed
                case .cancelled: throw CancellationError()
                case .queued,.running: try await Task.sleep(for:.seconds(2))
                }
            }
            throw ReferenceFailure.expired
        } catch {
            // 即使客户端已取消，也单独通知拥有该 UUID 的服务端任务停止。
            do {
                var cancel=URLRequest(url:base.appendingPathComponent(path)); cancel.httpMethod="DELETE"
                cancel.setValue("Bearer " + token,forHTTPHeaderField:"Authorization")
                let cleanupConfig=URLSessionConfiguration.ephemeral
                cleanupConfig.timeoutIntervalForRequest=5; cleanupConfig.timeoutIntervalForResource=5
                let cleanup=URLSession(configuration:cleanupConfig,delegate:delegate,delegateQueue:nil)
                let task=Task.detached { _ = try? await cleanup.data(for:cancel); cleanup.invalidateAndCancel() }
                _ = await task.value
            }
            throw error
        }
    }
}
private final class ReferenceSessionDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session:URLSession,task:URLSessionTask,willPerformHTTPRedirection response:HTTPURLResponse,newRequest request:URLRequest,completionHandler:@escaping (URLRequest?)->Void) { completionHandler(nil) }
}
