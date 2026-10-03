import Foundation
import Testing
@testable import MelodyApp
import MelodyCore

private actor DelayedReferenceProvider: ReferenceImageGenerating {
    var calls=0
    func generate(_ request:ReferenceImageRequest,jpeg:Data,progress:@escaping @Sendable (ReferenceRemoteStatus) async -> Void) async throws -> Data {
        calls += 1
        await progress(.init(id:request.id,state:.running,progress:0.25,stage:"正在采样"))
        try? await Task.sleep(for:.milliseconds(200))
        // 即使服务忽略取消，迟到的坏结果也不能覆盖取消状态。
        return Data([0])
    }
}
@MainActor @Test func referenceQueueDeduplicatesAndCancellationSurvivesLateResult() async throws {
    let provider=DelayedReferenceProvider()
    let controller=ReferenceGenerationController(loadSettings:false,provider:provider)
    controller.enabled=true
    let request=ReferenceImageRequest(projectID:UUID(),photoID:UUID(),batchID:UUID(),plan:OfflineDirector().plans(scene:.garden,availableZooms:[1])[0])
    controller.enqueue(request,jpeg:Data([1])); controller.enqueue(request,jpeg:Data([1]))
    for _ in 0..<50 where controller.jobs.first?.progress == nil { try await Task.sleep(for:.milliseconds(10)) }
    #expect(controller.jobs.count == 1)
    #expect(controller.jobs.first?.progress == 0.25)
    #expect(await provider.calls == 1)
    controller.cancel(request.id)
    try await Task.sleep(for:.milliseconds(250))
    #expect(controller.jobs.first?.state == .cancelled)
    #expect(controller.imageData(request.id) == nil)
}
@MainActor @Test func referenceRestartRestoresAssociationAndInterruptsPendingJob() async throws {
    let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at:root) }
    let provider=DelayedReferenceProvider()
    let first=ReferenceGenerationController(root:root,loadSettings:false,provider:provider); first.enabled=true
    let request=ReferenceImageRequest(projectID:UUID(),photoID:UUID(),batchID:UUID(),plan:OfflineDirector().plans(scene:.garden,availableZooms:[1])[0])
    first.enqueue(request,jpeg:Data([1]))
    let restored=ReferenceGenerationController(root:root,loadSettings:false)
    #expect(restored.job(projectID:request.projectID,photoID:request.photoID,batchID:request.batchID,planID:request.plan.id)?.state == .cancelled)
    #expect(restored.job(projectID:UUID(),photoID:request.photoID,batchID:request.batchID,planID:request.plan.id) == nil)
    first.suspend()
}

private struct ImmediateReferenceProvider:ReferenceImageGenerating {
    let result:Data
    func generate(_ request:ReferenceImageRequest,jpeg:Data,progress:@escaping @Sendable (ReferenceRemoteStatus) async -> Void) async throws -> Data { result }
}
@MainActor @Test func referenceRejectsNonImageWithoutPublishingReady() async throws {
    let controller=ReferenceGenerationController(loadSettings:false,provider:ImmediateReferenceProvider(result:Data([1,2,3])))
    controller.enabled=true
    let request=ReferenceImageRequest(projectID:UUID(),photoID:UUID(),batchID:UUID(),plan:OfflineDirector().plans(scene:.garden,availableZooms:[1])[0])
    controller.enqueue(request,jpeg:Data([1]))
    for _ in 0..<50 where controller.jobs.first?.isActive == true { try await Task.sleep(for:.milliseconds(10)) }
    #expect(controller.jobs.first?.state == .failed)
    #expect(controller.imageData(request.id) == nil)
}

@MainActor @Test func referenceDefaultsToPhoneAndDoesNotExposeLegacyMacJobs() throws {
    let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at:root) }
    let request=ReferenceImageRequest(projectID:UUID(),photoID:UUID(),batchID:UUID(),plan:OfflineDirector().plans(scene:.garden,availableZooms:[1])[0])
    let old=ReferenceJob(request:request,provider:"Draw Things · Mac 本地 Qwen")
    let folder=root.appendingPathComponent(old.id.uuidString)
    try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
    try JSONEncoder().encode(old).write(to:folder.appendingPathComponent("job.json"))
    let controller=ReferenceGenerationController(root:root,loadSettings:false)
    #expect(controller.providerName.contains("此 iPhone"))
    #expect(controller.job(projectID:request.projectID,photoID:request.photoID,batchID:request.batchID,planID:request.plan.id) == nil)
    #expect(FileManager.default.fileExists(atPath:folder.appendingPathComponent("job.json").path))
}

@MainActor @Test func referenceResolutionIsGlobalDefaultAndCapturedWhenQueued() async throws {
    let controller=ReferenceGenerationController(loadSettings:false,provider:DelayedReferenceProvider())
    #expect(controller.resolution == .square512)
    controller.enabled=true; controller.resolution = .portrait512
    let request=ReferenceImageRequest(projectID:UUID(),photoID:UUID(),batchID:UUID(),plan:OfflineDirector().plans(scene:.garden,availableZooms:[1])[0])
    controller.enqueue(request,jpeg:Data([1]))
    controller.resolution = .square768
    #expect(controller.jobs.first?.request.resolution == .portrait512)
    #expect(controller.jobs.first?.request.resolution?.width == 512)
    #expect(controller.jobs.first?.request.resolution?.height == 768)
    controller.suspend()
}

@Test func phoneGenerationGateCancellationDoesNotReleaseAnotherJob() async throws {
    let gate=PhoneModelGate()
    try await gate.acquire()
    let waiting=Task { try await gate.acquire() }
    try await Task.sleep(for:.milliseconds(20))
    waiting.cancel()
    do { try await waiting.value; Issue.record("排队取消不能取得生成槽") } catch is CancellationError {} catch { throw error }
    #expect(await gate.isOccupied)
    await gate.release()
    try await gate.acquire()
    #expect(await gate.isOccupied)
    await gate.release()
}

@Test func phoneModelInventoryAcceptsSDKOptimizedVAEBeforeSecondGeneration() {
    var files=Dictionary(uniqueKeysWithValues:PhoneReferenceProvider.requiredFiles)
    #expect(PhoneReferenceProvider.installationFraction(fileSizes:files) == 1)
    for (name,size) in PhoneReferenceProvider.optimizedVAEFiles { files[name]=size }
    #expect(PhoneReferenceProvider.installationFraction(fileSizes:files) == 1)
    let tensor=PhoneReferenceProvider.optimizedVAEFiles[1].0
    files[tensor]=1
    #expect(PhoneReferenceProvider.installationFraction(fileSizes:files) < 1)
    files[tensor]=nil
    #expect(PhoneReferenceProvider.installationFraction(fileSizes:files) < 1)
}
