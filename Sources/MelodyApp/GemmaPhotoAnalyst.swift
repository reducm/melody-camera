import Foundation
import CryptoKit
import MelodyCore
#if canImport(LiteRTLM)
import LiteRTLM
#endif

enum PhotoBackend: String, CaseIterable { case online = "在线视觉", gemma = "本机 Gemma" }
enum LocalModelFailure: LocalizedError {
    case missing, invalid, unavailable, invalidResponse
    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Gemma 返回的模板结构不完整，请重新分析或切换在线模型。"
        case .missing: return "请先在模型设置中导入 Gemma 4 E2B 模型文件。"
        case .invalid: return "Gemma 文件不完整或版本不匹配，请重新下载指定模型。"
        case .unavailable: return "当前构建未包含 Gemma 推理运行时，请使用 iOS 真机版本。"
        }
    }
}
enum GemmaModelStore {
    static let filename = "gemma-4-E2B-it.litertlm"
    static let expectedSize = 2_588_147_712
    static let sha256 = "181938105e0eefd105961417e8da75903eacda102c4fce9ce90f50b97139a63c"
    static var directory: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Gemma", isDirectory: true) }
    static var modelURL: URL { directory.appendingPathComponent(filename) }
    static var isInstalled: Bool { FileManager.default.fileExists(atPath: directory.appendingPathComponent("verified.sha256").path) && (try? modelURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) == expectedSize }
    static func install(from source: URL) throws {
        let access = source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }
        guard (try source.resourceValues(forKeys: [.fileSizeKey])).fileSize == expectedSize else { throw LocalModelFailure.invalid }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let staged = directory.appendingPathComponent(UUID().uuidString + ".partial")
        defer { try? FileManager.default.removeItem(at: staged) }
        try FileManager.default.copyItem(at: source, to: staged)
        let file = try FileHandle(forReadingFrom: staged)
        defer { try? file.close() }
        var hash = SHA256()
        while let chunk = try file.read(upToCount: 4 * 1024 * 1024), !chunk.isEmpty {
            try Task.checkCancellation(); hash.update(data: chunk)
        }
        guard hash.finalize().map({ String(format: "%02x", $0) }).joined() == sha256 else { throw LocalModelFailure.invalid }
        try Task.checkCancellation()
        if FileManager.default.fileExists(atPath: modelURL.path) { _ = try FileManager.default.replaceItemAt(modelURL, withItemAt: staged) }
        else { try FileManager.default.moveItem(at: staged, to: modelURL) }
        var location = directory
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try location.setResourceValues(values)
        try Data(sha256.utf8).write(to: directory.appendingPathComponent("verified.sha256"), options: .atomic)
    }
}
struct GemmaPhotoAnalyst: PhotoAnalyzing {
    func analyze(frame: ObservationFrame, availableZooms: [Double]) async throws -> PhotoAnalysis {
        let id = ModelDiagnostics.operationID ?? UUID(), start = ContinuousClock.now
        DiagnosticLog.shared.record(.debug, .analysis, "Gemma 本地模型输入", detail: "Gemma 4 E2B · maxOutputTokens=2500 · visualTokenBudget=280\n" + ModelDiagnostics.imageSummary(frame.jpeg) + "\n\n" + PhotoAnalysisPrompt.make(availableZooms: availableZooms), operationID: id, modelContent: true)
        do {
            let result = try await performAnalysis(frame: frame, availableZooms: availableZooms, operationID: id)
            DiagnosticLog.shared.record(.info, .analysis, "Gemma 分析完成", detail: "耗时 \(ModelDiagnostics.elapsed(since: start)) · 结果通过结构校验", operationID: id)
            return result
        } catch {
            DiagnosticLog.shared.failure(error, .analysis, "Gemma 本地分析未完成", operationID: id)
            throw error
        }
    }
    private func performAnalysis(frame: ObservationFrame, availableZooms: [Double], operationID: UUID) async throws -> PhotoAnalysis {
        guard GemmaModelStore.isInstalled else { throw LocalModelFailure.missing }
        #if canImport(LiteRTLM)
        try await PhoneModelGate.shared.acquire()
        do {
            let result=try await analyzeLocally(frame:frame,availableZooms:availableZooms,operationID:operationID)
            await PhoneModelGate.shared.release()
            return result
        } catch {
            await PhoneModelGate.shared.release()
            throw error
        }
        #else
        throw LocalModelFailure.unavailable
        #endif
    }
    #if canImport(LiteRTLM)
    private func analyzeLocally(frame:ObservationFrame,availableZooms:[Double],operationID:UUID) async throws -> PhotoAnalysis {
        try Task.checkCancellation()
        let engine = Engine(engineConfig: try EngineConfig(modelPath: GemmaModelStore.modelURL.path,
            backend: .gpu, visionBackend: .cpu(), maxNumTokens: 4096))
        try await engine.initialize()
        try Task.checkCancellation()
        let conversation = try await engine.createConversation(with: ConversationConfig(
            thinkingConfig: ThinkingConfig(enableThinking: false), automaticToolCalling: false, enableResponseFormat: true, visualTokenBudget: 280))
        let result = try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await conversation.sendMessage(Message(contents: [
                .imageData(frame.jpeg), .text(PhotoAnalysisPrompt.make(availableZooms: availableZooms))
            ]), maxOutputTokens: 2500, thinkingConfig: ThinkingConfig(enableThinking: false),
               responseFormat: try ResponseFormat.json(schema: PhotoAnalysisSchema.make(availableZooms: availableZooms)))
        } onCancel: { try? conversation.cancel() }
        try Task.checkCancellation()
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--melody-check-gemma") {
            let output = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("gemma-check-raw.txt")
            try? Data(result.contents.toString.utf8).write(to: output, options: .atomic)
        }
        #endif
        DiagnosticLog.shared.record(.info, .analysis, "Gemma 本地模型输出", detail: result.contents.toString, operationID: operationID, modelContent: true)
        do { return try PhotoAnalysisCodec.decode(result.contents.toString, availableZooms: availableZooms) }
        catch { throw LocalModelFailure.invalidResponse }
    }
    #endif
}
