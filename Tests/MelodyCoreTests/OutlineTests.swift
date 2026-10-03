import Testing
@testable import MelodyCore

@Test func outlineRejectsInvalidCoordinatesAndEmptyGeometry() {
    #expect(throws: (any Error).self) { try SubjectOutline(id: 1, paths: [], sourceAspect: 0.75) }
    #expect(throws: (any Error).self) {
        try SubjectOutline(id: 1, paths: [[.init(x: -1, y: 0), .init(x: 1, y: 0), .init(x: 1, y: 1)]], sourceAspect: 1)
    }
}
@Test func targetOutlinePreservesShapeAndPhysicalAspectAcrossCanvases() throws {
    let outline = try SubjectOutline(id: 1, paths: [[.init(x: 0.4, y: 0.2), .init(x: 0.6, y: 0.2), .init(x: 0.6, y: 0.8), .init(x: 0.4, y: 0.8)]], sourceAspect: 2)
    let target = SubjectBox(x: 0.1, y: 0.1, width: 0.8, height: 0.8)
    let mapped = try outline.placed(in: target, canvasAspect: 0.75)
    #expect(mapped.bounds.isValid)
    #expect(abs(mapped.bounds.width * 0.75 / mapped.bounds.height - 2.0 / 3.0) < 0.001)
    #expect(mapped.bounds.x >= 0.1 && mapped.bounds.y >= 0.1)
    #expect(mapped.bounds.x + mapped.bounds.width <= 0.901)
    #expect(mapped.bounds.y + mapped.bounds.height <= 0.901)
}
