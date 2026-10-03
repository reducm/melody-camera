import Foundation
import OSLog

enum DiagnosticLevel: String, Codable, CaseIterable, Sendable { case debug = "Debug", info = "Info", warning = "Warning", error = "Error" }
enum DiagnosticCategory: String, Codable, CaseIterable, Sendable {
    case app = "应用", camera = "相机", analysis = "照片分析", reference = "参考图", storage = "存储", model = "模型安装"
}
struct DiagnosticEntry: Codable, Identifiable, Sendable, Equatable {
    let id: UUID
    let date: Date
    let level: DiagnosticLevel
    let category: DiagnosticCategory
    let message: String
    let detail: String?
    let operationID: UUID?
}
struct DiagnosticSnapshot: Sendable, Equatable {
    let entries: [DiagnosticEntry]
    let bytes: Int
    let storageError: String?
}

/// 同一串行队列负责写入、读取、轮转和清空，避免旧的待写事件在清理后重新出现。
/// 模型文字仅进入本机文件；系统 Logger 只接收简短事件，不接收模型输入输出。
final class DiagnosticLog: @unchecked Sendable {
    static let detailsPreference = "diagnostics.modelDetails"
    static let shared = DiagnosticLog(
        directory: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Diagnostics", isDirectory: true),
        systemLogging: true,
        modelDetailsEnabled: { UserDefaults.standard.object(forKey: detailsPreference) as? Bool ?? true }
    )
    private let directory: URL
    private var file: URL { directory.appendingPathComponent("events.json") }
    private let queue = DispatchQueue(label: "com.melody.camera.diagnostics", qos: .utility)
    private let maxEntries: Int
    private let maxBytes: Int
    private let now: @Sendable () -> Date
    private let systemLogging: Bool
    private let modelDetailsEnabled: @Sendable () -> Bool
    private var loaded = false
    private var entries: [DiagnosticEntry] = []
    private var storageError: String?

    init(directory: URL, maxEntries: Int = 500, maxBytes: Int = 2 * 1024 * 1024,
         systemLogging: Bool = false, now: @escaping @Sendable () -> Date = { Date() },
         modelDetailsEnabled: @escaping @Sendable () -> Bool = { true }) {
        self.directory = directory; self.maxEntries = max(1, maxEntries); self.maxBytes = max(1024, maxBytes)
        self.systemLogging = systemLogging; self.now = now; self.modelDetailsEnabled = modelDetailsEnabled
    }

    func record(_ level: DiagnosticLevel, _ category: DiagnosticCategory, _ message: String,
                detail: String? = nil, operationID: UUID? = nil, secrets: [String] = [], modelContent: Bool = false) {
        // 在调用时读取开关，已关闭后提交的内容不会因为队列延迟而重新开启记录。
        let includeDetail = !modelContent || modelDetailsEnabled()
        queue.async {
            self.load()
            let entry = DiagnosticEntry(id: UUID(), date: self.now(), level: level, category: category,
                message: DiagnosticRedaction.text(message, secrets: secrets, limit: 512),
                detail: includeDetail ? detail.map { DiagnosticRedaction.text($0, secrets: secrets) } : nil,
                operationID: operationID)
            self.entries.append(entry)
            self.prune(); self.persist()
            if self.systemLogging {
                let logger = Logger(subsystem: "com.melody.camera", category: category.rawValue)
                // 文字按 private 处理，Console 默认脱敏；没有密钥、照片或模型正文。
                switch level {
                case .debug: logger.debug("\(entry.message, privacy: .private)")
                case .info: logger.info("\(entry.message, privacy: .private)")
                case .warning: logger.warning("\(entry.message, privacy: .private)")
                case .error: logger.error("\(entry.message, privacy: .private)")
                }
            }
        }
    }

    func failure(_ error: Error, _ category: DiagnosticCategory, _ message: String, operationID: UUID? = nil) {
        let ns = error as NSError
        let cancelled = error is CancellationError || (ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled)
        record(cancelled ? .warning : .error, category, cancelled ? "\(message)（已取消）" : message,
               detail: ModelDiagnostics.errorSummary(error), operationID: operationID)
    }

    func snapshot() async -> DiagnosticSnapshot {
        await withCheckedContinuation { continuation in
            queue.async {
                self.load()
                let count = self.entries.count
                self.prune()
                if count != self.entries.count { self.persist() }
                continuation.resume(returning: self.currentSnapshot())
            }
        }
    }

    func clear() async -> DiagnosticSnapshot {
        await withCheckedContinuation { continuation in
            queue.async {
                self.load()
                do {
                    // 即使文件不存在，也先检查目录状态，不能把无权限误报成清理成功。
                    try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
                    if FileManager.default.fileExists(atPath: self.file.path) { try FileManager.default.removeItem(at: self.file) }
                    self.entries.removeAll(); self.storageError = nil
                } catch { self.storageError = "日志未能清理，请检查本机可用空间或稍后重试。" }
                continuation.resume(returning: self.currentSnapshot())
            }
        }
    }

    private func load() {
        guard !loaded else { return }; loaded = true
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        do {
            let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= maxBytes else { throw CocoaError(.fileReadTooLarge) }
            entries = try JSONDecoder().decode([DiagnosticEntry].self, from: Data(contentsOf: file))
        } catch {
            entries = []; storageError = "旧日志无法读取；后续事件会建立新日志。可点击清理移除旧文件。"
        }
    }
    private func prune() {
        let cutoff = now().addingTimeInterval(-7 * 86400)
        entries.removeAll { $0.date < cutoff }
        if entries.count > maxEntries { entries.removeFirst(entries.count - maxEntries) }
        while !entries.isEmpty, (try? JSONEncoder().encode(entries).count) ?? Int.max > maxBytes { entries.removeFirst() }
    }
    private func persist() {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var folder = directory; var values = URLResourceValues(); values.isExcludedFromBackup = true
            try folder.setResourceValues(values)
            let data = try JSONEncoder().encode(entries)
            #if os(iOS)
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: directory.path)
            try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            #else
            try data.write(to: file, options: .atomic)
            #endif
            storageError = nil
        } catch { storageError = "日志暂未保存到本机，当前仅能查看内存记录；请检查可用空间。" }
    }
    private func currentSnapshot() -> DiagnosticSnapshot {
        DiagnosticSnapshot(entries: entries.reversed(), bytes: (try? JSONEncoder().encode(entries).count) ?? 0, storageError: storageError)
    }
}

enum DiagnosticRedaction {
    static func text(_ value: String, secrets: [String] = [], limit: Int = 32_768) -> String {
        var text = value
        for secret in secrets where !secret.isEmpty { text = text.replacingOccurrences(of: secret, with: "[密钥已隐藏]") }
        // 防御服务商回显凭据/图像；真正的边界是调用处仅抽取允许的文本字段。
        for pattern in [#"(?i)data:[^\s,]+;base64,[A-Za-z0-9+/=_-]+"#,
                        #"(?i)Bearer\s+[^\s\"',;]+"#, #"(?i)\bsk-[A-Za-z0-9_-]+"#,
                        #"(?i)https?://[^\s\"<>]+"#, #"[A-Za-z0-9+/=_-]{256,}"#] {
            text = text.replacingOccurrences(of: pattern, with: "[已隐藏]", options: .regularExpression)
        }
        guard text.utf8.count > limit else { return text }
        var data = Data(text.utf8.prefix(limit))
        while String(data: data, encoding: .utf8) == nil { data.removeLast() }
        return (String(data: data, encoding: .utf8) ?? "") + "\n…[内容过长，已截断]"
    }
}
