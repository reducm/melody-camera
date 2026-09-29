import Testing
import Foundation
@testable import MelodyCore

let validPlan = #"{"plans":[{"id":"garden-left","title":"三分留白","instruction":"人物站到左侧","reason":"给视线留出空间","zoom":2,"subject":{"x":0.15,"y":0.2,"width":0.3,"height":0.65}}]}"#
@Test func rejectsOffscreenBody() {
    #expect(!SubjectBox(x: 0.9, y: 0.1, width: 0.3, height: 0.7).isValid)
    #expect(!SubjectBox(x: .nan, y: 0, width: 0.3, height: 0.7).isValid)
    #expect(!SubjectBox(x: 0, y: 0, width: 0, height: 0.7).isValid)
}
@Test func acceptsNormalizedBody() {
    #expect(SubjectBox(x: 0.15, y: 0.2, width: 0.3, height: 0.65).isValid)
}
@Test func readsProviderPlan() throws {
    let plans = try PlanCodec.decode(validPlan, availableZooms: [1, 2])
    #expect(plans.count == 1)
    #expect(plans.first?.title == "三分留白")
}
@Test func stripsJSONFence() throws {
    #expect(try PlanCodec.decode("```json\n" + validPlan + "\n```", availableZooms: [1,2]).count == 1)
}
@Test func rejectsUnavailableZoom() {
    #expect(throws: CompositionError.invalidPlan) { try PlanCodec.decode(validPlan, availableZooms: [1]) }
}
@Test func rejectsInvalidCoordinates() {
    #expect(throws: CompositionError.invalidPlan) {
        try PlanCodec.decode(validPlan.replacingOccurrences(of: "0.15", with: "1.5"), availableZooms: [2])
    }
}
@Test func rejectsEmptyAndMalformedResults() {
    #expect(throws: (any Error).self) { try PlanCodec.decode("not json", availableZooms: [1]) }
    #expect(throws: CompositionError.invalidPlan) { try PlanCodec.decode(#"{"plans":[]}"#, availableZooms: [1]) }
}
@Test func offlinePlansRespectCapabilities() {
    for scene in SceneKind.allCases {
        let plans = OfflineDirector().plans(scene: scene, availableZooms: [1])
        #expect(plans.count == 3)
        #expect(plans.allSatisfy { $0.zoom == 1 && $0.subject.isValid })
        #expect(Set(plans.map(\.id)).count == plans.count)
    }
}
@Test func noLensMeansNoPlan() {
    #expect(OfflineDirector().plans(scene: .city, availableZooms: []).isEmpty)
}
