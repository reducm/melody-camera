import Foundation
import Testing
@testable import MelodyCore

private func reportJSON(summary: String = "人物位于画面中央，背景有树木。", duplicate: Bool = false, zoom: Double = 1) throws -> String {
    let plans = OfflineDirector().plans(scene: .garden, availableZooms: [zoom])
    let report: [String: Any] = [
        "summary": summary,
        "observations": ["light": "面部光线较柔和。", "composition": "人物居中。", "background": "头部后方有树干。", "pose": "手臂自然垂下。", "quality": "缩略图不能判断精确对焦。"],
        "nextStep": "先向右移动半步，避开头后树干。",
        "limitations": "单张缩略图无法确认高光原始细节。",
        "plans": try JSONSerialization.jsonObject(with: JSONEncoder().encode(duplicate ? [plans[0], plans[0]] : plans))
    ]
    return String(decoding: try JSONSerialization.data(withJSONObject: report), as: UTF8.self)
}
@Test func detailedPhotoReportValidatesAllSectionsAndTemplates() throws {
    let report = try PhotoAnalysisCodec.decode(reportJSON(), availableZooms: [1])
    #expect(report.plans.count == 3)
    #expect(report.observations.light.contains("光线"))
    #expect(!report.limitations.isEmpty)
}
@Test func detailedPhotoReportRejectsUntrustedContent() throws {
    for json in [try reportJSON(summary: " "), try reportJSON(summary: String(repeating: "字", count: 401)), try reportJSON(duplicate: true), try reportJSON(zoom: 8)] {
        #expect(throws: (any Error).self) { try PhotoAnalysisCodec.decode(json, availableZooms: [1]) }
    }
    #expect(throws: (any Error).self) { try PhotoAnalysisCodec.decode("{}", availableZooms: [1]) }
}
@Test func photoAnalysisSendsOnePhotoAndReturnsValidatedReport() async throws {
    let json = try reportJSON()
    let response = try JSONSerialization.data(withJSONObject: ["choices": [["message": ["content": json]]]])
    let analyst = OnlinePhotoAnalyst(config: .init(baseURL: "https://example.com/v1", model: "vision", apiKey: "test")) { request in
        let payload = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        let messages = payload["messages"] as! [[String: Any]]
        let content = messages[0]["content"] as! [[String: Any]]
        #expect(content.filter { $0["type"] as? String == "image_url" }.count == 1)
        #expect((content[0]["text"] as? String)?.contains("limitations") == true)
        return (response, 200)
    }
    let report = try await analyst.analyze(frame: .init(jpeg: Data([1,2,3]), zoom: 1), availableZooms: [1])
    #expect(report.nextStep.contains("半步"))
}
@Test func photoAnalysisRejectsHTTPFailureWithoutDisplayingBody() async {
    let analyst = OnlinePhotoAnalyst(config: .init(baseURL: "https://example.com/v1", model: "vision", apiKey: "test")) { _ in (Data("private details".utf8), 401) }
    await #expect(throws: CompositionError.http(401)) {
        try await analyst.analyze(frame: .init(jpeg: Data([1]), zoom: 1), availableZooms: [1])
    }
}

@Test func photoSchemaRequiresTemplateGeometryAndSupportedZoom() throws {
    let schema = PhotoAnalysisSchema.make(availableZooms: [1,2])
    let properties = try #require(schema["properties"] as? [String: Any])
    let plans = try #require(properties["plans"] as? [String: Any])
    let item = try #require(plans["items"] as? [String: Any])
    #expect((item["required"] as? [String])?.contains("subject") == true)
    let planProperties = try #require(item["properties"] as? [String: Any])
    #expect((planProperties["zoom"] as? [String:Any])?["enum"] as? [Double] == [1,2])
}
