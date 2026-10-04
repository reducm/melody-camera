import Foundation
import Testing
@testable import MelodyApp

@MainActor @Test func publicPhotoRegressionRejectsMissingManifest() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let report = await PublicPhotoRegression.run(fixtures: root.appendingPathComponent("missing"), output: root)
    #expect(!report.passed && !report.completed && report.error != nil)
}

/// 只读取显式指定的公开样图库；没有参数时不运行，也不读取私人照片或凭据。
@MainActor @Test(.enabled(if: ProcessInfo.processInfo.environment["MELODY_PUBLIC_PHOTOS"] != nil))
func publicPhotoWorkflowRegression() async throws {
    let path = try #require(ProcessInfo.processInfo.environment["MELODY_PUBLIC_PHOTOS"])
    let output = try #require(ProcessInfo.processInfo.environment["MELODY_PUBLIC_RESULTS"])
    let report = await PublicPhotoRegression.run(fixtures: URL(fileURLWithPath: path), output: URL(fileURLWithPath: output))
    #expect(report.completed)
    for sample in report.samples { #expect(sample.passed, "\(sample.file): \(sample.error ?? sample.checks.filter { !$0.value }.description)") }
    #expect(report.passed)
}
