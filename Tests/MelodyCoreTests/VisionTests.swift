import Testing
import Foundation
@testable import MelodyCore
private let config = ProviderConfiguration(baseURL: "https://example.com/v1/", model: "vision-model", apiKey: "secret")
private let frame = ObservationFrame(jpeg: Data([0xff,0xd8,0xff,0xd9]), zoom: 1)
@Test func requestContainsActualImagesAndLensLabels() throws {
    let request = try VisionRequest.make(config: config, frames: [frame], availableZooms: [1,2])
    #expect(request.url?.absoluteString == "https://example.com/v1/chat/completions")
    #expect(request.httpMethod == "POST")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer secret")
    let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
    let payload = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
    let messages = payload["messages"] as! [[String: Any]]
    let content = messages[0]["content"] as! [[String: Any]]
    let image = content.last?["image_url"] as? [String: String]
    #expect(image?["url"] == "data:image/jpeg;base64," + frame.jpeg.base64EncodedString())
    #expect(body.contains("vision-model"))
    #expect(body.contains("1.0"))
    #expect(request.timeoutInterval <= 45)
}
@Test func rejectsInsecureOrCredentialBearingEndpoints() {
    for url in ["http://example.com/v1", "https://user:pass@example.com/v1", "file:///tmp/a", "https://example.com/v1?key=secret", "https://example.com/v1#fragment"] {
        #expect(throws: CompositionError.invalidEndpoint) {
            try VisionRequest.make(config: .init(baseURL: url, model: "v", apiKey: "k"), frames: [frame], availableZooms: [1])
        }
    }
}
@Test func rejectsEmptyCredentialsBeforeNetwork() {
    #expect(throws: CompositionError.missingCredentials) {
        try VisionRequest.make(config: .init(baseURL: config.baseURL, model: " ", apiKey: ""), frames: [frame], availableZooms: [1])
    }
}
@Test func refusesEmptyObservation() {
    #expect(throws: CompositionError.noFrames) {
        try VisionRequest.make(config: config, frames: [], availableZooms: [1])
    }
}
@Test func refusesOversizedObservation() {
    #expect(throws: CompositionError.noFrames) {
        try VisionRequest.make(config: config, frames: Array(repeating: frame, count: 5), availableZooms: [1])
    }
}
@Test func decodesEndToEndProviderEnvelope() async throws {
    let envelope = try JSONSerialization.data(withJSONObject: ["choices": [["message": ["content": validPlan]]]])
    let director = OnlineDirector(config: config) { request in
        #expect(request.httpMethod == "POST")
        return (envelope, 200)
    }
    let plans = try await director.recommend(frames: [frame], availableZooms: [1,2])
    #expect(plans.count == 1)
}
@Test func reportsHTTPFailureWithoutLeakingBody() async {
    let director = OnlineDirector(config: config) { _ in (Data("secret diagnostic".utf8), 401) }
    await #expect(throws: CompositionError.http(401)) {
        try await director.recommend(frames: [frame], availableZooms: [1])
    }
}
@Test func rejectsNonChatResponse() async {
    let director = OnlineDirector(config: config) { _ in (Data(#"{"output":"oops"}"#.utf8), 200) }
    await #expect(throws: CompositionError.malformedResponse) {
        try await director.recommend(frames: [frame], availableZooms: [1])
    }
}
@Test func rejectsDuplicatePlanIdentifiers() throws {
    let object = try JSONSerialization.jsonObject(with: Data(validPlan.utf8)) as! [String: Any]
    let plans = object["plans"] as! [[String: Any]]
    let data = try JSONSerialization.data(withJSONObject: ["plans": plans + plans])
    #expect(throws: CompositionError.invalidPlan) {
        try PlanCodec.decode(String(decoding: data, as: UTF8.self), availableZooms: [2])
    }
}
@Test func cancellationDiscardsLateProviderResult() async throws {
    let envelope = try JSONSerialization.data(withJSONObject:["choices":[["message":["content":validPlan]]]])
    let director = OnlineDirector(config:config) { _ in
        try? await Task.sleep(for:.seconds(5))
        return (envelope,200)
    }
    let request = Task { try await director.recommend(frames:[frame],availableZooms:[1,2]) }
    request.cancel()
    await #expect(throws:CancellationError.self) { try await request.value }
}
