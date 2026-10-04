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

private func detachedSceneResponse(base: String? = nil, scene: SceneEvidence = .init()) throws -> String {
    let report = try base ?? reportJSON(summary: "测试文本含有 }、{ 和转义引号 \"scene\"，不是结构边界。")
    let encodedScene = String(decoding: try JSONEncoder().encode(scene), as: UTF8.self)
    // 复现真机返回的结构错误；只用合成文字，不收录用户照片描述。
    return report + ",\"scene\":" + encodedScene + "}"
}

private func analyzeResponse(_ content: String, zooms: [Double] = [1]) async throws -> PhotoAnalysis {
    let data = try JSONSerialization.data(withJSONObject: ["choices": [["message": ["content": content]]]])
    return try await OnlinePhotoAnalyst(config: .init(baseURL: "https://example.test/v1", model: "vision", apiKey: "test")) { _ in
        (data, 200)
    }.analyze(frame: .init(jpeg: Data([1]), zoom: 1), availableZooms: zooms)
}

@Test func photoPromptExampleIsOneCompleteReportWithScene() throws {
    let prompt = PhotoAnalysisPrompt.make(availableZooms: [2])
    let example = try #require(prompt.split(separator: "\n").last)
    let report = try PhotoAnalysisCodec.decode(String(example), availableZooms: [2])
    #expect(report.scene != nil)
}

@Test func onlineAnalysisRecoversOnlyDetachedSceneEnvelope() async throws {
    var scene = SceneEvidence(); scene.subjectKind = .product; scene.shape = .box
    for text in [try detachedSceneResponse(scene: scene), "```json\n" + (try detachedSceneResponse(scene: scene)) + "\n```"] {
        let report = try await analyzeResponse(text)
        #expect(report.scene == scene)
        #expect(report.summary.contains("转义引号"))
        #expect(report.plans.count == 3)
    }
}

@Test func onlineAnalysisRejectsAmbiguousOrInvalidSceneRepairs() async throws {
    let good = try reportJSON()
    var withScene = try JSONSerialization.jsonObject(with: Data(good.utf8)) as! [String: Any]
    withScene["scene"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(SceneEvidence()))
    let existingScene = String(decoding: try JSONSerialization.data(withJSONObject: withScene), as: UTF8.self)
    var badScene = SceneEvidence(); badScene.horizonY = 2
    let detached = try detachedSceneResponse()
    let cases = [detached + "说明", String(detached.dropLast()), good + good,
                 good + ",\"other\":{}}", try detachedSceneResponse(base: existingScene),
                 String(detached.dropLast()) + ",\"other\":true}",
                 try detachedSceneResponse(scene: badScene),
                 try detachedSceneResponse(base: reportJSON(duplicate: true)),
                 try detachedSceneResponse(base: reportJSON(zoom: 8))]
    for value in cases {
        await #expect(throws: (any Error).self) { try await analyzeResponse(value) }
    }
}

@Test func invalidAnalysisBodyDoesNotBlameImageEndpoint() async {
    do {
        _ = try await analyzeResponse("{\"summary\":")
        Issue.record("损坏的 JSON 不应通过")
    } catch {
        #expect(error.localizedDescription.contains("JSON"))
        #expect(!error.localizedDescription.contains("支持图像"))
    }
}

@Test func sceneRepairIsReportedOnlyAfterValidationAndHistoryStaysStrict() throws {
    var repairs = 0
    let detached = try detachedSceneResponse()
    _ = try PhotoAnalysisCodec.decodeModelResponse(detached, availableZooms: [1]) { repairs += 1 }
    #expect(repairs == 1)
    _ = try PhotoAnalysisCodec.decodeModelResponse(reportJSON(), availableZooms: [1]) { repairs += 1 }
    #expect(repairs == 1)
    #expect(throws: (any Error).self) {
        try PhotoAnalysisCodec.decodeModelResponse(detachedSceneResponse(base: reportJSON(zoom: 8)), availableZooms: [1]) { repairs += 1 }
    }
    #expect(repairs == 1)
    #expect(throws: (any Error).self) { try PhotoAnalysisCodec.decode(detached, availableZooms: [1]) }
}
