import Foundation
import Testing
import MelodyCore
import MelodyImaging
@testable import MelodyApp

/// 显式环境变量才运行；仅使用仓库外公开样图，不扫描用户相册。
@Test(.enabled(if: ProcessInfo.processInfo.environment["MELODY_PUBLIC_FIXTURE"] != nil))
func realPublicImageSegmentation() throws {
    guard let path = ProcessInfo.processInfo.environment["MELODY_PUBLIC_FIXTURE"] else { return }
    let image = try PhotoProcessor.load(Data(contentsOf: URL(fileURLWithPath: path)))
    let outlines = try SubjectSegmenter.outlines(in: image)
    #expect(!outlines.isEmpty)
    #expect(outlines.allSatisfy { $0.bounds.isValid })
    let output = outlines.map { ["id": $0.id, "paths": $0.paths.map { $0.map { [$0.x,$0.y] } }] as [String:Any] }
    if let destination = ProcessInfo.processInfo.environment["MELODY_CHECK_OUTPUT"] {
        try JSONSerialization.data(withJSONObject: output).write(to: URL(fileURLWithPath: destination).appendingPathComponent("actual-outlines.json"))
    }
}
@Test(.enabled(if: ProcessInfo.processInfo.environment["MELODY_PUBLIC_FIXTURE"] != nil && ProcessInfo.processInfo.environment["MELODY_PRIVATE_CONFIG"] != nil))
func realDeepSeekPhotoContract() async throws {
    guard let path = ProcessInfo.processInfo.environment["MELODY_PUBLIC_FIXTURE"],
          let configuration = ProcessInfo.processInfo.environment["MELODY_PRIVATE_CONFIG"] else { return }
    struct Input: Decodable { let baseURL: String; let model: String; let apiKey: String }
    let input = try JSONDecoder().decode(Input.self, from: Data(contentsOf: URL(fileURLWithPath: configuration)))
    let photo = try PhotoProcessor.load(Data(contentsOf: URL(fileURLWithPath: path)), maxPixel: 1024)
    let analyst = OnlinePhotoAnalyst(config: .init(baseURL: input.baseURL, model: input.model, apiKey: input.apiKey), transport: { try await NetworkTransport.shared.send($0) })
    let report = try await analyst.analyze(frame: .init(jpeg: PhotoProcessor.jpeg(photo), zoom: 1), availableZooms: [1,2])
    #expect(!report.plans.isEmpty)
    #expect(report.subjectName != nil)
    #expect(report.plans.contains { $0.viewpoint != nil })
    if let destination = ProcessInfo.processInfo.environment["MELODY_CHECK_OUTPUT"] {
        try JSONEncoder().encode(report).write(to: URL(fileURLWithPath: destination).appendingPathComponent("actual-photo-report.json"))
    }
}
