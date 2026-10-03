import XCTest
import Foundation
@testable import MelodyApp
import MelodyCore

final class DiagnosticLogTests: XCTestCase {
    private func directory() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }

    func testPersistenceLevelsAndClearAcrossRestart() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let log = DiagnosticLog(directory: root)
        for level in DiagnosticLevel.allCases { log.record(level, .app, "分级测试") }
        let saved = await log.snapshot()
        XCTAssertEqual(saved.entries.count, 4)
        let reopened = DiagnosticLog(directory: root)
        let restored = await reopened.snapshot()
        XCTAssertEqual(Set(restored.entries.map(\.level)), Set(DiagnosticLevel.allCases))
        let cleared = await reopened.clear()
        XCTAssertTrue(cleared.entries.isEmpty)
        XCTAssertNil(cleared.storageError)
        let after = await DiagnosticLog(directory: root).snapshot()
        XCTAssertTrue(after.entries.isEmpty)
    }

    func testPendingWritesCannotReappearAfterClear() async {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let log = DiagnosticLog(directory: root)
        DispatchQueue.concurrentPerform(iterations: 60) { _ in log.record(.info, .camera, "拍摄完成") }
        let cleared = await log.clear()
        XCTAssertTrue(cleared.entries.isEmpty)
        log.record(.info, .app, "清理之后的新事件")
        let after = await log.snapshot()
        XCTAssertEqual(after.entries.map(\.message), ["清理之后的新事件"])
    }

    func testRetentionBoundsAndExpiryOnRead() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let date = Date(timeIntervalSince1970: 100_000)
        let log = DiagnosticLog(directory: root, maxEntries: 3, maxBytes: 1600, now: { date })
        for _ in 0..<10 { log.record(.debug, .analysis, "有界日志", detail: String(repeating: "测", count: 300)) }
        let snapshot = await log.snapshot()
        XCTAssertLessThanOrEqual(snapshot.entries.count, 3)
        XCTAssertGreaterThan(snapshot.entries.count, 0)
        XCTAssertLessThanOrEqual(snapshot.bytes, 1600)
        let expired = await DiagnosticLog(directory: root, now: { date.addingTimeInterval(8 * 86400) }).snapshot()
        XCTAssertTrue(expired.entries.isEmpty)
    }

    func testRedactionBeforePersistenceAndTextLimit() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let log = DiagnosticLog(directory: root)
        let secret = "custom-secret-without-prefix"
        log.record(.debug, .analysis, "模型输出", detail: "\(secret) Bearer abcdefgh sk-test123456 data:image/jpeg;base64,AAAAAAA https://host.test/path?key=123\n" + String(repeating: "照片", count: 40_000), secrets: [secret])
        let snapshot = await log.snapshot()
        let text = snapshot.entries.first!.detail!
        XCTAssertFalse(text.contains(secret)); XCTAssertFalse(text.contains("abcdefgh"))
        XCTAssertFalse(text.contains("sk-test123456")); XCTAssertFalse(text.contains("AAAAAAA"))
        XCTAssertFalse(text.contains("host.test")); XCTAssertTrue(text.contains("已截断"))
        XCTAssertLessThanOrEqual(text.utf8.count, 33_000)
        let bytes = try Data(contentsOf: root.appendingPathComponent("events.json"))
        XCTAssertFalse(String(decoding: bytes, as: UTF8.self).contains(secret))
    }

    func testCorruptionAndStorageFailureAreVisible() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("broken".utf8).write(to: root.appendingPathComponent("events.json"))
        let corrupt = await DiagnosticLog(directory: root).snapshot()
        XCTAssertNotNil(corrupt.storageError)
        let blocked = root.appendingPathComponent("not-directory")
        try Data().write(to: blocked)
        let log = DiagnosticLog(directory: blocked)
        log.record(.error, .storage, "保存失败")
        let failed = await log.snapshot()
        XCTAssertNotNil(failed.storageError)
        XCTAssertEqual(failed.entries.count, 1)
        let cleared = await log.clear()
        XCTAssertNotNil(cleared.storageError)
    }

    func testOnlineCallShowsTextAndStatusWithoutHeadersOrImageBody() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let log = DiagnosticLog(directory: root)
        let secret = "custom-provider-secret"
        var request = URLRequest(url: URL(string: "https://example.test/v1/chat/completions")!)
        request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["model": "test-model", "messages": [["role": "user", "content": [["type": "text", "text": "观察主体"], ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,PRIVATEIMAGE"]]]]]])
        let transport = ModelDiagnostics.transport({ _ in
            (try JSONSerialization.data(withJSONObject: ["error": ["message": "额度不足 \(secret)"]]), 429)
        }, log: log)
        let callID = UUID()
        let (_, code) = try await ModelDiagnostics.$operationID.withValue(callID) { try await transport(request) }
        XCTAssertEqual(code, 429)
        let events = await log.snapshot()
        XCTAssertEqual(events.entries.count, 2)
        XCTAssertEqual(Set(events.entries.compactMap(\.operationID)), [callID])
        let details = events.entries.compactMap(\.detail).joined()
        XCTAssertTrue(details.contains("观察主体")); XCTAssertTrue(details.contains("额度不足"))
        XCTAssertTrue(details.contains("429")); XCTAssertFalse(details.contains(secret))
        XCTAssertFalse(details.contains("PRIVATEIMAGE")); XCTAssertFalse(details.contains("Authorization"))
        XCTAssertEqual(events.entries.first?.level, .error)
    }

    func testDisablingModelDetailsKeepsOnlyOperationalSummary() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let log = DiagnosticLog(directory: root, modelDetailsEnabled: { false })
        log.record(.debug, .analysis, "模型输入", detail: "私人照片描述", modelContent: true)
        log.record(.info, .analysis, "模型调用完成", detail: "HTTP 200")
        let snapshot = await log.snapshot()
        XCTAssertEqual(snapshot.entries.count, 2)
        XCTAssertNil(snapshot.entries.first(where: { $0.message == "模型输入" })?.detail)
        XCTAssertEqual(snapshot.entries.first(where: { $0.message == "模型调用完成" })?.detail, "HTTP 200")
    }

    func testNetworkErrorCannotLeakURLOrDescription() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let log = DiagnosticLog(directory: root)
        let transport = ModelDiagnostics.transport({ _ in
            throw NSError(domain: NSURLErrorDomain, code: -1001, userInfo: [NSLocalizedDescriptionKey: "private-secret", NSURLErrorFailingURLStringErrorKey: "https://secret.test"])
        }, log: log)
        do { _ = try await transport(URLRequest(url: URL(string: "https://example.test")!)); XCTFail() } catch {}
        let snapshot = await log.snapshot()
        let text = snapshot.entries.compactMap(\.detail).joined()
        XCTAssertTrue(text.contains("-1001")); XCTAssertFalse(text.contains("private-secret"))
        XCTAssertEqual(snapshot.entries.first?.level, .error)
    }
}
