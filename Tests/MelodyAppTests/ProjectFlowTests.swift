#if os(macOS)
import Foundation
import Testing
import MelodyCore
import MelodyImaging
@testable import MelodyApp

@MainActor @Test func photoProjectSurvivesRestartAndRetake() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at:root) }
    let store = ProjectLibrary(root:root)
    let studio = StudioModel(loadCredentials:false,enableSegmentation:false,projectStore:store)
    let bytes = try PhotoProcessor.jpeg(studio.renderedDemo())
    await studio.importPhotoData(bytes)
    let id = try #require(studio.currentProject?.id)
    studio.style = .warm; studio.amount = 0.3; studio.updateEdit()
    await studio.waitForProjectSave()
    await studio.importPhotoData(bytes)
    #expect(studio.currentProject?.id == id)
    #expect(studio.currentProject?.photos.count == 2)
    let first = try #require(studio.currentProject?.photos.first?.id)
    await studio.selectProjectPhoto(first)
    #expect(studio.style == .warm && studio.amount == 0.3)
    await studio.waitForProjectSave()
    let restarted = StudioModel(loadCredentials:false,enableSegmentation:false,projectStore:store)
    await restarted.openProject(id)
    #expect(restarted.showEditor)
    #expect(restarted.currentProject?.photos.count == 2)
    #expect(restarted.style == .warm && restarted.amount == 0.3)
    #expect(try restarted.exportData(original:true) == bytes)
    restarted.newProject()
    #expect(restarted.currentProject == nil)
    #expect(restarted.original == nil)
    #expect(try await store.list().projects.count == 1)
}
@MainActor @Test func failedPhotoReplacementKeepsProjectAndPhoto() async throws {
    let studio = StudioModel(loadCredentials:false,enableSegmentation:false)
    await studio.importPhotoData(try PhotoProcessor.jpeg(studio.renderedDemo()))
    let snapshot = studio.currentProject
    await studio.importPhotoData(Data([1,2]))
    #expect(studio.currentProject == snapshot)
    #expect(studio.showEditor)
}

private actor SessionCamera: CameraOperating {
    let data: Data
    init(data:Data) { self.data = data }
    func start() async throws -> [Double] { [0.5,1,2] }
    func setZoom(_ zoom:Double) async throws {}
    func capture() async throws -> Data { data }
    nonisolated func stop() {}
}
@MainActor @Test func templateCaptureStaysInProjectWithReference() async throws {
    let seed = StudioModel(loadCredentials:false,enableSegmentation:false)
    let data = try PhotoProcessor.jpeg(seed.renderedDemo())
    let studio = StudioModel(loadCredentials:false,enableSegmentation:false,cameraDriver:SessionCamera(data:data))
    await studio.importPhotoData(data)
    let projectID = studio.currentProject?.id
    let photoID = studio.currentProject?.activePhotoID
    let report = try PhotoAnalysisCodec.decode(sessionReport,availableZooms:[1])
    studio.currentProject?.addRecommendation(report,source:"固定响应测试")
    studio.photoAnalysis = report
    let outline = try SubjectOutline(id:1,paths:[[.init(x:0.1,y:0.1),.init(x:0.7,y:0.1),.init(x:0.5,y:0.8)]],sourceAspect:0.75)
    studio.subjectOutlines = [outline]; studio.selectedOutlineID = 1
    studio.startCamera(plan:report.plans[0])
    for _ in 0..<100 where studio.busy { try await Task.sleep(for:.milliseconds(5)) }
    #expect(!studio.showEditor && studio.source == .camera)
    for zoom in [0.5, 2, 1] {
        studio.chooseZoom(zoom)
        for _ in 0..<100 where studio.busy { try await Task.sleep(for:.milliseconds(5)) }
        #expect(studio.zoom == zoom)
        #expect(studio.selected == report.plans[0])
        #expect(studio.guideOutline == outline)
    }
    studio.capture()
    for _ in 0..<100 where studio.busy { try await Task.sleep(for:.milliseconds(5)) }
    #expect(studio.currentProject?.id == projectID)
    #expect(studio.currentProject?.photos.count == 2)
    #expect(studio.currentProject?.activePhoto?.capturedFollowing?.photoID == photoID)
    #expect(studio.currentProject?.photos.first?.recommendations.count == 1)
    #expect(studio.followedOutline == outline)
    #expect(studio.followedPlan == report.plans[0])
    #expect(studio.photoAnalysis == nil && studio.showEditor)
}
private actor RepeatAnalysisTransport {
    var count = 0
    func send(_ request:URLRequest) throws -> (Data,Int) {
        count += 1
        if count == 3 { return (Data(),500) }
        return (try JSONSerialization.data(withJSONObject:["choices":[["message":["content":sessionReport]]]]),200)
    }
}
@MainActor @Test func repeatedAndFailedGenerationsPreservePreviousBatches() async throws {
    let transport = RepeatAnalysisTransport()
    let studio = StudioModel(loadCredentials:false,enableSegmentation:false,photoTransport:{ try await transport.send($0) })
    await studio.importPhotoData(try PhotoProcessor.jpeg(studio.renderedDemo()))
    studio.baseURL = "https://example.com/v1"; studio.modelName = "fixture"; studio.apiKey = "test"
    for _ in 0..<3 {
        studio.analyzePhoto()
        for _ in 0..<100 where studio.busy { try await Task.sleep(for:.milliseconds(5)) }
    }
    #expect(studio.recommendationBatches.count == 2)
    #expect(studio.photoAnalysis?.summary == "测试")
    #expect(studio.error != nil)
    let first = try #require(studio.recommendationBatches.first)
    studio.chooseRecommendationBatch(first.id)
    #expect(studio.currentProject?.activePhoto?.selectedBatchID == first.id)
}
@MainActor @Test func diskFailureKeepsOriginalAndReportsUnsavedProject() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try Data([1]).write(to:root)
    defer { try? FileManager.default.removeItem(at:root) }
    let studio = StudioModel(loadCredentials:false,enableSegmentation:false,projectStore:ProjectLibrary(root:root))
    let bytes = try PhotoProcessor.jpeg(studio.renderedDemo())
    await studio.importPhotoData(bytes)
    await studio.waitForProjectSave()
    #expect(studio.historySaveFailed)
    #expect(studio.currentProject != nil && studio.showEditor)
    #expect(studio.originalData == bytes)
}
private let sessionReport = """
{"summary":"测试","observations":{"light":"光","composition":"构图","background":"背景","pose":"姿态","quality":"细节"},"nextStep":"下一步","limitations":"固定响应测试","plans":[{"id":"p1","title":"测试","instruction":"动作","reason":"原因","zoom":1,"subject":{"x":0.1,"y":0.1,"width":0.5,"height":0.5}}]}
"""
#endif

#if os(macOS)
@MainActor @Test func galleryPreviewKeepsProjectSelectionAndPhotoRecipe() async throws {
    let studio = StudioModel(loadCredentials:false,enableSegmentation:false)
    let bytes = try PhotoProcessor.jpeg(studio.renderedDemo())
    await studio.importPhotoData(bytes)
    let first = try #require(studio.currentProject?.activePhotoID)
    studio.style = .warm; studio.amount = 0.2; studio.updateEdit()
    let expected = try studio.exportData(original:false)
    await studio.importPhotoData(bytes)
    let second = studio.currentProject?.activePhotoID
    let preview = try await studio.galleryPhoto(first,original:false)
    #expect(preview.id == first && preview.data == expected)
    #expect(studio.currentProject?.activePhotoID == second)
    #expect(try await studio.galleryPhoto(first,original:true).data == bytes)
    await #expect(throws:(any Error).self) { try await studio.galleryPhoto(UUID(),original:true) }
}
#endif
