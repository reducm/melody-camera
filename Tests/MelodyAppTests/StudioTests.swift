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
    let studio = StudioModel(loadCredentials:false)
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
@MainActor @Test func onlineModeRequiresExplicitUploadConsent() {
    let studio = StudioModel(loadCredentials:false)
    studio.mode = .online
    studio.analyze()
    #expect(studio.error?.contains("允许") == true)
    #expect(!studio.busy && studio.plans.isEmpty)
}
@MainActor @Test func importedOriginalSurvivesEditingAndExport() async throws {
    let studio = StudioModel(loadCredentials:false)
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
    let studio = StudioModel(loadCredentials:false); studio.analyze()
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
    let studio = StudioModel(loadCredentials:false,cameraDriver:camera)
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
#endif
