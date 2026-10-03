import Foundation
import ImageIO
import MelodyCore

enum ModelDiagnostics {
    @TaskLocal static var operationID: UUID?
    /// 装饰 transport，不改 Core、请求、重试或模型选择；只抽取允许的文本，绝不序列化整个请求。
    static func transport(_ send: @escaping OnlineDirector.Transport, log: DiagnosticLog = .shared) -> OnlineDirector.Transport {
        { request in
            let id = operationID ?? UUID(), start = ContinuousClock.now
            let authorization = request.value(forHTTPHeaderField: "Authorization") ?? ""
            let secret = authorization.hasPrefix("Bearer ") ? String(authorization.dropFirst(7)) : ""
            log.record(.debug, .analysis, "在线模型输入", detail: requestSummary(request), operationID: id, secrets: [secret], modelContent: true)
            do {
                let (data, status) = try await send(request)
                let timing = "HTTP \(status) · 耗时 \(elapsed(since: start)) · 响应 \(data.count) 字节"
                log.record((200...299).contains(status) ? .info : .error, .analysis, "在线模型输出 · HTTP \(status)",
                           detail: timing + "\n\n" + responseSummary(data), operationID: id, secrets: [secret], modelContent: true)
                return (data, status)
            } catch {
                log.failure(error, .analysis, "在线模型调用未完成", operationID: id)
                throw error
            }
        }
    }
    static func elapsed(since start: ContinuousClock.Instant) -> String {
        let value = start.duration(to: .now).components
        return String(format: "%.2f 秒", Double(value.seconds) + Double(value.attoseconds) / 1e18)
    }
    static func imageSummary(_ data: Data) -> String {
        var summary = "图片 \(data.count) 字节（不记录图像正文或 EXIF）"
        if let source = CGImageSourceCreateWithData(data as CFData, nil),
           let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let width = properties[kCGImagePropertyPixelWidth] as? Int,
           let height = properties[kCGImagePropertyPixelHeight] as? Int {
            summary = "图片 \(width) × \(height) · \(data.count) 字节（不记录图像正文或 EXIF）"
        }
        return summary
    }
    static func errorSummary(_ error: Error) -> String {
        // 自己定义的错误只有受控文案；底层 NSError 的 userInfo 可能包含 URL、路径和凭据。
        if error is CompositionError || error is LocalModelFailure || error is PhoneReferenceFailure || error is ReferenceFailure || error is CameraFailure {
            return error.localizedDescription
        }
        if error is CancellationError { return "任务已取消" }
        let ns = error as NSError
        switch ns.domain {
        case NSURLErrorDomain: return "网络错误，代码 \(ns.code)" + (ns.code == NSURLErrorTimedOut ? "（连接或响应超时）" : "")
        case NSCocoaErrorDomain: return "系统文件或数据错误，代码 \(ns.code)"
        case "AVFoundationErrorDomain": return "相机系统错误，代码 \(ns.code)"
        default: return "底层调用失败，代码 \(ns.code)；未记录可能包含私人信息的原始错误正文。"
        }
    }
    private static func requestSummary(_ request: URLRequest) -> String {
        guard let data = request.httpBody, data.count <= 10_000_000,
              let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return "请求正文不可解析；未记录原始数据。" }
        var lines = ["模型：\(body["model"] as? String ?? "未提供")"]
        if let tokens = body["max_tokens"] as? Int { lines.append("输出上限：\(tokens) tokens") }
        for message in (body["messages"] as? [[String: Any]] ?? []).prefix(8) {
            if let text = message["content"] as? String { lines.append(text) }
            for part in (message["content"] as? [[String: Any]] ?? []).prefix(12) {
                if part["type"] as? String == "text", let text = part["text"] as? String { lines.append(text) }
                else if part["type"] as? String == "image_url" {
                    if let image = part["image_url"] as? [String: Any], let url = image["url"] as? String,
                       url.hasPrefix("data:image/jpeg;base64,"), url.count <= 3_000_000,
                       let bytes = Data(base64Encoded: String(url.dropFirst("data:image/jpeg;base64,".count))) {
                        lines.append(imageSummary(bytes))
                    } else { lines.append("附带 1 张图片（正文与地址不记录）") }
                }
            }
        }
        return lines.joined(separator: "\n\n")
    }
    private static func responseSummary(_ data: Data) -> String {
        guard data.count <= 256_000, let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "响应超过大小限制或不是 JSON；未记录原始数据。"
        }
        if let error = body["error"] as? [String: Any] {
            return ["message", "type", "code"].compactMap { key in
                guard let text = error[key] as? String else { return nil }; return "\(key)：\(text)"
            }.joined(separator: "\n")
        }
        let choices = body["choices"] as? [[String: Any]] ?? []
        let texts = choices.prefix(3).compactMap { ($0["message"] as? [String: Any])?["content"] as? String }
        return texts.isEmpty ? "响应没有可用的 message.content 文本；未记录其他字段。" : texts.joined(separator: "\n\n")
    }
}
