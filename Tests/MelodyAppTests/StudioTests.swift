#if os(macOS)
import Testing
import SwiftUI
import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers
import MelodyCore
import MelodyImaging
@testable import MelodyApp

@MainActor @Test func offlineFlowProvidesUsableOverlayWithoutNetwork() {
    let studio = StudioModel(loadCredentials:false, enableSegmentation:false)
    studio.analyze()
    #expect(studio.plans.count == 3)
    #expect(studio.selected?.subject.isValid == true)
    #expect(studio.planSource.contains("未分析画面"))
    #expect(!studio.busy)
    studio.choose(studio.plans[1])
    #expect(studio.zoom == 2)
    studio.scene = .cafe; studio.changeScene()
    #expect(studio.plans.isEmpty && studio.selected == nil)
}
@MainActor @Test func onlineModeRequiresConfiguration() async throws {
    let studio = StudioModel(loadCredentials:false, enableSegmentation:false)
    studio.mode = .online
    studio.analyze()
    for _ in 0..<100 where studio.busy { try await Task.sleep(for:.milliseconds(5)) }
    #expect(studio.error?.contains("允许") != true)
    #expect(!studio.busy && studio.plans.isEmpty)
}
@MainActor @Test func importedOriginalSurvivesEditingAndExport() async throws {
    let studio = StudioModel(loadCredentials:false, enableSegmentation:false)
    let image = try studio.renderedDemo()
    let data = try PhotoProcessor.jpeg(image)
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
    try data.write(to:url); defer { try? FileManager.default.removeItem(at:url) }
    studio.loadPhoto(url)
    #expect(studio.source == .imported)
    #expect(studio.zooms == [1])
    studio.capture()
    for _ in 0..<100 where studio.busy { try await Task.sleep(for:.milliseconds(10)) }
    #expect(!studio.busy && studio.showEditor)
    #expect(try studio.exportData(original:true) == data)
    studio.style = .warm; studio.amount = 1
    #expect(try studio.exportData(original:false) != data)
    #expect(try studio.exportData(original:true) == data)
}

/// 离屏渲染用于布局检查；不是模拟器或 UI 自动化通过的证明。
@MainActor @Test func renderReviewArtifacts() throws {
    guard let directory = ProcessInfo.processInfo.environment["MELODY_RENDER_DIR"] else { return }
    let root = URL(fileURLWithPath:directory,isDirectory:true)
    try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
    let studio = StudioModel(loadCredentials:false, enableSegmentation:false); studio.analyze()
    func render<V: View>(_ view:V, name:String, width:CGFloat, height:CGFloat) throws {
        let host = NSHostingView(rootView:view.frame(width:width,height:height).environment(\.colorScheme,.dark))
        host.frame = CGRect(x:0,y:0,width:width,height:height)
        host.layoutSubtreeIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in:host.bounds) else { throw PhotoError.render }
        host.cacheDisplay(in:host.bounds,to:bitmap)
        guard let data = bitmap.representation(using:.png,properties:[:]) else { throw PhotoError.render }
        try data.write(to:root.appendingPathComponent(name + ".png"))

    }
    try render(StudioView(studio:studio),name:"mac-studio",width:1120,height:880)
    try render(StudioView(studio:studio),name:"phone-layout",width:430,height:932)
    studio.original = try studio.renderedDemo()
    studio.edited = try PhotoProcessor.render(studio.original!,style:.warm,amount:0.7)
    try render(PhotoEditor(studio:studio),name:"photo-editor",width:520,height:820)
    if let fixture = ProcessInfo.processInfo.environment["MELODY_PUBLIC_FIXTURE"] {
        let photo = try PhotoProcessor.load(Data(contentsOf: URL(fileURLWithPath:fixture)))
        let outlines = try SubjectSegmenter.outlines(in: photo)
        let outline = try #require(outlines.first)
        let preview = Image(decorative:photo,scale:1).resizable().overlay { SubjectOutlineView(outline:outline) }
        try render(preview,name:"actual-subject-outline",width:600,height:600*CGFloat(photo.height)/CGFloat(photo.width))
        let plan = ShotPlan(id:"layout-check",title:"布局检查",instruction:"布局检查",reason:"布局检查",zoom:1,subject:.init(x:0.15,y:0.3,width:0.7,height:0.45),viewpoint:.left45)
        try render(ShotTemplatePreview(plan:plan,outline:outline).padding().background(Color.melodyBackground),name:"actual-subject-template",width:430,height:260)
    }
}


private actor PausingCamera: CameraOperating {
    var waiting = false
    var continuation: CheckedContinuation<Void,Never>?
    func start() async throws -> [Double] { [1,2] }
    func setZoom(_ zoom: Double) async throws {
        waiting = true
        await withCheckedContinuation { continuation = $0 }
    }
    func capture() async throws -> Data { throw CameraFailure.capture }
    nonisolated func stop() {}
    func isWaiting() -> Bool { waiting }
    func release() { continuation?.resume(); continuation = nil }
}
@MainActor @Test(arguments:["start","zoom","plan"])
func cameraTransitionCannotCommitAfterBackground(action:String) async throws {
    let camera = PausingCamera()
    let studio = StudioModel(loadCredentials:false, enableSegmentation:false,cameraDriver:camera)
    if action == "start" { studio.startCamera() }
    else {
        studio.source = .camera
        if action == "zoom" { studio.chooseZoom(2) }
        else { studio.choose(OfflineDirector().plans(scene:.garden,availableZooms:[1,2])[1]) }
    }
    for _ in 0..<100 {
        if await camera.isWaiting() { break }
        try await Task.sleep(for:.milliseconds(5))
    }
    #expect(await camera.isWaiting())
    studio.suspend()
    await camera.release()
    for _ in 0..<100 where studio.busy { try await Task.sleep(for:.milliseconds(5)) }
    #expect(!studio.busy)
    #expect(studio.source == .demo)
    #expect(studio.zoom == 1 && studio.selected == nil)
    #expect(studio.error == nil)
}

private actor AnalysisProbe {
    var requests = 0
    var pending: CheckedContinuation<Void, Never>?
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests += 1
        await withCheckedContinuation { pending = $0 }
        return (Data(), 401)
    }
    func count() -> Int { requests }
    func release() { pending?.resume(); pending = nil }
}
@MainActor @Test func photoAnalysisNeedsPhotoAndConfigurationBeforeTransport() async throws {
    let probe = AnalysisProbe()
    let studio = StudioModel(loadCredentials: false, enableSegmentation: false, photoTransport: { try await probe.send($0) })
    studio.analyzePhoto()
    #expect(studio.error != nil)
    studio.original = try studio.renderedDemo()
    studio.originalData = try PhotoProcessor.jpeg(studio.original!)
    studio.error = nil
    studio.analyzePhoto()
    #expect(studio.error?.contains("允许") != true)
    #expect(await probe.count() == 0)
    #expect(!studio.busy && studio.photoAnalysis == nil)
}
@MainActor @Test func cancelledPhotoAnalysisDoesNotPublishLateFailure() async throws {
    let probe = AnalysisProbe()
    let studio = StudioModel(loadCredentials: false, enableSegmentation: false, photoTransport: { try await probe.send($0) })
    studio.original = try studio.renderedDemo()
    let originalData = try PhotoProcessor.jpeg(studio.original!)
    studio.originalData = originalData
    studio.baseURL = "https://example.com/v1"; studio.modelName = "vision"; studio.apiKey = "test"
    studio.analyzePhoto()
    for _ in 0..<100 {
        if await probe.count() > 0 { break }
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(await probe.count() == 1)
    studio.cancelPhotoAnalysis()
    await probe.release()
    for _ in 0..<100 where studio.busy { try await Task.sleep(for: .milliseconds(10)) }
    #expect(!studio.busy && studio.photoAnalysis == nil && studio.error == nil)
    #expect(studio.originalData == originalData)
}

private actor ReadyCamera: CameraOperating {
    private var currentZoom: Double = 1
    func start() async throws -> [Double] { [1, 2] }
    func setZoom(_ zoom: Double) async throws { currentZoom = zoom }
    func capture() async throws -> Data { throw CameraFailure.capture }
    nonisolated func stop() {}
    func chosenZoom() -> Double { currentZoom }
}
@MainActor @Test func templateReturnsToCameraAfterApplyingSupportedZoom() async throws {
    let camera = ReadyCamera()
    let studio = StudioModel(loadCredentials: false, enableSegmentation: false, cameraDriver: camera)
    let plan = OfflineDirector().plans(scene: .garden, availableZooms: [1, 2])[1]
    studio.showEditor = true
    studio.startCamera(plan: plan)
    for _ in 0..<100 where studio.busy { try await Task.sleep(for: .milliseconds(5)) }
    #expect(studio.source == .camera && studio.selected == plan)
    #expect(studio.zoom == 2 && !studio.showEditor)
    #expect(await camera.chosenZoom() == 2)
}
@MainActor @Test func unsupportedTemplateDoesNotDismissPhoto() async throws {
    let studio = StudioModel(loadCredentials: false, enableSegmentation: false, cameraDriver: ReadyCamera())
    let plan = OfflineDirector().plans(scene: .garden, availableZooms: [8])[0]
    studio.showEditor = true
    studio.startCamera(plan: plan)
    for _ in 0..<100 where studio.busy { try await Task.sleep(for: .milliseconds(5)) }
    #expect(studio.error != nil && studio.showEditor)
    #expect(studio.source == .demo && studio.selected == nil)
}
@MainActor @Test func reportStaysBoundToOriginalAndNewCaptureClearsIt() async throws {
    let plans = OfflineDirector().plans(scene: .garden, availableZooms: [1])
    let payload: [String: Any] = ["summary": "测试画面", "nextStep": "向左移动", "limitations": "固定响应测试", "observations": ["light": "测试光线", "composition": "测试构图", "background": "测试背景", "pose": "测试姿态", "quality": "测试画质"], "plans": try JSONSerialization.jsonObject(with: JSONEncoder().encode(plans))]
    let content = String(decoding: try JSONSerialization.data(withJSONObject: payload), as: UTF8.self)
    let response = try JSONSerialization.data(withJSONObject: ["choices": [["message": ["content": content]]]])
    let studio = StudioModel(loadCredentials: false, enableSegmentation: false, photoTransport: { request in
        #expect(request.url?.absoluteString == "https://example.com/v1/chat/completions")
        return (response, 200)
    })
    studio.capture()
    for _ in 0..<100 where studio.busy { try await Task.sleep(for: .milliseconds(5)) }
    let original = studio.originalData
    studio.baseURL = "https://example.com/v1"; studio.modelName = "fixture"; studio.apiKey = "test"
    studio.analyzePhoto()
    for _ in 0..<100 where studio.busy { try await Task.sleep(for: .milliseconds(10)) }
    // 旧供应商响应没有 scene，不把三个泛化建议冒充知识推荐。
    #expect(studio.photoAnalysis?.plans.count == 1)
    #expect(studio.photoAnalysis?.plans.first?.design?.kind == .framingOnly)
    #expect(studio.photoAnalysisSource.contains("非实拍"))
    #expect(studio.originalData == original)
    studio.capture()
    for _ in 0..<100 where studio.busy { try await Task.sleep(for: .milliseconds(5)) }
    #expect(studio.photoAnalysis == nil && studio.photoAnalysisSource.isEmpty)
}
@MainActor @Test func localPhotoAnalysisDoesNotRequireUploadOrKey() async throws {
    let studio = StudioModel(loadCredentials:false, enableSegmentation:false)
    studio.original = try studio.renderedDemo()
    studio.photoBackend = .gemma
    studio.analyzePhoto()
    for _ in 0..<100 where studio.busy { try await Task.sleep(for:.milliseconds(10)) }
    #expect(studio.error?.contains("Gemma") == true)
    #expect(studio.error?.contains("允许") != true)
    #expect(studio.apiKey.isEmpty)
}
@MainActor @Test func photosPickerImportPreservesOriginalAndOpensEditor() async throws {
    let studio = StudioModel(loadCredentials:false, enableSegmentation:false)
    let bytes = try PhotoProcessor.jpeg(studio.renderedDemo())
    await studio.importPhotoData(bytes)
    #expect(studio.showEditor && studio.photoSource == .imported)
    #expect(try studio.exportData(original:true) == bytes)
    await studio.importPhotoData(Data([0,1,2]))
    #expect(studio.error != nil)
    #expect(try studio.exportData(original:true) == bytes)
}
#endif
