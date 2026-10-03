import Foundation
import MelodyCore
#if os(iOS)
import UIKit
#endif

/// 仅开发构建：通过本机 Xcode 设备容器传入一次性配置，消费后立即删除。
enum DebugProvisioning {
    @MainActor static func consumeReference(into controller:ReferenceGenerationController) throws {
        #if DEBUG
        let file=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("melody-reference-once.json")
        guard FileManager.default.fileExists(atPath:file.path) else { return }
        // 旧版 Mac 配置仅清理，不再导入；手机生成不需要连接密钥。
        try? FileManager.default.removeItem(at:file)
        #endif
    }
    static func consumeProvider() throws -> ProviderConfiguration? {
        #if DEBUG
        let file = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("melody-provider-once.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        defer { try? FileManager.default.removeItem(at: file) }
        guard (try file.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0 <= 8192 else { return nil }
        struct Input: Decodable { let baseURL: String; let model: String; let apiKey: String }
        let input = try JSONDecoder().decode(Input.self, from: Data(contentsOf: file))
        let config = ProviderConfiguration(baseURL: input.baseURL, model: input.model, apiKey: input.apiKey)
        _ = try VisionRequest.make(config: config, frames: [.init(jpeg: Data([1]), zoom: 1)], availableZooms: [1])
        try KeyStore.save(config.apiKey)
        return config
        #else
        return nil
        #endif
    }
}

#if DEBUG
/// 只有显式启动参数才执行的真机集成检查，不上传文件，也不访问相册。
@MainActor extension StudioModel {
    func runDeviceGemmaCheck() async {
        if ProcessInfo.processInfo.arguments.contains("--melody-check-logs") {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let isolated = DiagnosticLog(directory: root)
            isolated.record(.debug, .app, "独立日志回归检查", detail: "test-secret", secrets: ["test-secret"])
            let written = await isolated.snapshot()
            let restored = await DiagnosticLog(directory: root).snapshot()
            let cleared = await isolated.clear()
            let live = await DiagnosticLog.shared.snapshot()
            let file = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("logging-check-result.json")
            let result: [String: Any] = [
                "isolatedPersisted": written.entries.count == 1 && written.storageError == nil,
                "isolatedRestored": restored.entries.count == 1,
                "isolatedRedacted": restored.entries.first?.detail?.contains("test-secret") == false,
                "isolatedCleared": cleared.entries.isEmpty && cleared.storageError == nil,
                "liveCount": live.entries.count, "liveStorageOK": live.storageError == nil,
                "liveCategories": Array(Set(live.entries.map { $0.category.rawValue })).sorted(),
                "liveLevels": Array(Set(live.entries.map { $0.level.rawValue })).sorted(),
                "qwenInputPresent": live.entries.contains { $0.message == "Qwen 参考图输入 · 已排队" && $0.detail != nil },
                "qwenOutputPresent": live.entries.contains { $0.message == "Qwen 生成图输出" },
                "qwenLinkedCall": live.entries.contains { output in output.message == "Qwen 生成图输出" && live.entries.contains { $0.message == "Qwen 参考图输入 · 已排队" && $0.operationID == output.operationID } }
            ]
            try? JSONSerialization.data(withJSONObject: result, options: .sortedKeys).write(to: file, options: .atomic)
            return
        }
        #if os(iOS)
        let holdsScreen=ProcessInfo.processInfo.arguments.contains("--melody-check-project-reference-existing")
        if holdsScreen {
            for _ in 0..<100 where UIApplication.shared.applicationState != .active { try? await Task.sleep(for:.milliseconds(100)) }
            UIApplication.shared.isIdleTimerDisabled=true
        }
        defer { if holdsScreen { UIApplication.shared.isIdleTimerDisabled=false } }
        #endif
        if ProcessInfo.processInfo.arguments.contains("--melody-observe-startup") {
            for _ in 0..<80 where source != .camera && error == nil { try? await Task.sleep(for:.milliseconds(250)) }
            let file = FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("camera-startup-check.json")
            try? JSONSerialization.data(withJSONObject:["cameraReady":source == .camera, "projectEmpty":currentProject == nil, "editorClosed":!showEditor, "availableZooms":zooms]).write(to:file,options:.atomic)
            return
        }
        if ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("--melody-check-project") }) {
            await runProjectCheck(); return
        }
        let templateCheck = ProcessInfo.processInfo.arguments.contains("--melody-check-template")
        guard templateCheck || ProcessInfo.processInfo.arguments.contains("--melody-check-gemma") else { return }
        let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        if templateCheck {
            do {
                await importPhotoData(try Data(contentsOf: root.appendingPathComponent("public-test-truck.jpg")))
                photoAnalysis = try PhotoAnalysisCodec.decode(String(contentsOf: root.appendingPathComponent("public-test-report.json"), encoding: .utf8), availableZooms: [1,2])
                photoAnalysisSource = "公开样图回归 · 已验证的 DeepSeek 响应"
            } catch { self.error = "公开样图回归文件不可用。" }
            return
        }
        let output = root.appendingPathComponent("gemma-check-result.json")
        func record(_ value: [String: Any]) { try? JSONSerialization.data(withJSONObject: value).write(to: output, options: .atomic) }
        record(["stage": "started"])
        if !GemmaModelStore.isInstalled {
            installLocalModel(root.appendingPathComponent(GemmaModelStore.filename))
            while installingModel { try? await Task.sleep(for: .milliseconds(250)) }
            guard GemmaModelStore.isInstalled else { record(["stage":"install-failed", "error": error ?? "未知错误"]); return }
            try? FileManager.default.removeItem(at: root.appendingPathComponent(GemmaModelStore.filename))
        }
        record(["stage":"model-installed"])
        do {
            let photo = try Data(contentsOf: root.appendingPathComponent("public-test-truck.jpg"))
            await importPhotoData(photo)
            photoBackend = .gemma
            let started = Date()
            analyzePhoto()
            while analyzingPhoto { try await Task.sleep(for: .milliseconds(250)) }
            if let report = photoAnalysis {
                try JSONEncoder().encode(report).write(to: root.appendingPathComponent("gemma-check-report.json"), options: .atomic)
                record(["stage":"passed", "seconds":Date().timeIntervalSince(started), "plans":report.plans.count, "outlines":subjectOutlines.count])
            } else { record(["stage":"inference-failed", "error":error ?? notice]) }
        } catch { record(["stage":"failed", "error":error.localizedDescription]) }
    }
    private func runProjectCheck() async {
        let root = FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0]
        let recordURL = root.appendingPathComponent("project-check-result.json")
        do {
            if ProcessInfo.processInfo.arguments.contains("--melody-check-project-seed") {
                let bytes = try Data(contentsOf:root.appendingPathComponent("public-test-truck.jpg"))
                await importPhotoData(bytes)
                let report = try PhotoAnalysisCodec.decode(String(contentsOf:root.appendingPathComponent("public-test-report.json"),encoding:.utf8),availableZooms:[1])
                currentProject?.addRecommendation(report,source:"公开样图回归 · 已验证的 Gemma 响应")
                currentProject?.addRecommendation(report,source:"公开样图回归 · 重复保存检查")
                photoAnalysis = report; photoAnalysisSource = "公开样图回归"
                style = .warm; amount = 0.35; updateEdit()
                let first = currentProject!.activePhotoID!
                while outlining { try await Task.sleep(for:.milliseconds(100)) }
                let reference = CaptureReference(photoID:first,batchID:currentProject!.activePhoto!.selectedBatch!.id,planID:report.plans[0].id,outline:selectedOutline)
                await importPhotoData(bytes)
                // 公开样图构造跟拍来源，仅检查历史/叠加，不冒充相机实拍。
                currentProject?.photos[1].capturedFollowing = reference
                persistCurrentProject()
                await selectProjectPhoto(first)
                await waitForProjectSave()
            } else {
                await refreshProjectHistory()
                guard let id = projectHistory.first?.id else { throw ProjectFailure.damaged }
                await openProject(id)
                if ProcessInfo.processInfo.arguments.contains(where:{$0.hasPrefix("--melody-check-project-reference")}),currentProject?.photos.contains(where:{ !$0.recommendations.isEmpty }) != true {
                    for candidate in projectHistory.dropFirst() {
                        await openProject(candidate.id)
                        if currentProject?.photos.contains(where:{ !$0.recommendations.isEmpty }) == true { break }
                    }
                }
            }
            if ProcessInfo.processInfo.arguments.contains(where:{$0.hasPrefix("--melody-check-project-reference")}) {
                guard let photo=currentProject?.photos.first(where: { !$0.recommendations.isEmpty }) else { throw ProjectFailure.damaged }
                await selectProjectPhoto(photo.id)
                guard let plan=photoAnalysis?.plans.first else { throw ProjectFailure.damaged }
                if ProcessInfo.processInfo.arguments.contains("--melody-check-project-reference-view"),let project=currentProject,let photo=project.activePhoto,let batch=photo.selectedBatch {
                    let job=references.job(projectID:project.id,photoID:photo.id,batchID:batch.id,planID:plan.id)
                    let result:[String:Any]=["ready":job?.state == .ready,"imagePresent":job.map { references.imageData($0.id)?.isEmpty == false } ?? false,"editorOpen":showEditor,"templateStillAvailable":photoAnalysis?.plans.isEmpty == false]
                    try JSONSerialization.data(withJSONObject:result).write(to:root.appendingPathComponent("reference-view-check.json"),options:.atomic)
                    return
                }
                let referenceStarted=Date()
                generateReference(plan,retry:true)
                for _ in 0..<100 where references.jobs.last?.isActive != true { try await Task.sleep(for:.milliseconds(100)) }
                while references.jobs.last?.isActive == true { try await Task.sleep(for:.seconds(1)) }
                guard let job=references.jobs.last else { throw ProjectFailure.damaged }
                let result:[String:Any]=["state":job.state.rawValue,"message":job.message,"jobID":job.id.uuidString,"provider":job.provider,"elapsedSeconds":Date().timeIntervalSince(referenceStarted),"width":job.request.resolution?.width ?? 512,"height":job.request.resolution?.height ?? 512,"templateStillAvailable":photoAnalysis?.plans.isEmpty == false]
                try JSONSerialization.data(withJSONObject:result).write(to:root.appendingPathComponent("reference-check-result.json"),options:.atomic)
                return
            }
            if ProcessInfo.processInfo.arguments.contains("--melody-check-project-zoom") {
                if let first = currentProject?.photos.first { await selectProjectPhoto(first.id) }
                guard let plan = photoAnalysis?.plans.first else { throw ProjectFailure.damaged }
                while outlining { try await Task.sleep(for:.milliseconds(100)) }
                startCamera(plan:plan)
                while busy { try await Task.sleep(for:.milliseconds(100)) }
                let expectedOutline = guideOutline
                var checks: [[String:Any]] = []
                for value in zooms {
                    chooseZoom(value)
                    while busy { try await Task.sleep(for:.milliseconds(100)) }
                    checks.append(["zoom":value,"matched":abs(zoom-value)<0.001,"templateKept":selected == plan,"outlineKept":guideOutline == expectedOutline,"cameraReady":source == .camera])
                }
                try JSONSerialization.data(withJSONObject:["checks":checks,"hasOutline":expectedOutline != nil,"error":error ?? ""]).write(to:root.appendingPathComponent("zoom-check-result.json"),options:.atomic)
                return
            }
            let valid = currentProject?.photos.count == 2 && recommendationBatches.count == 2 && style == .warm && abs(amount-0.35) < 0.001 && originalData != nil
            let record: [String:Any] = ["passed":valid, "photos":currentProject?.photos.count ?? 0, "batches":recommendationBatches.count, "style":style.rawValue, "amount":amount, "savingFailed":historySaveFailed]
            try JSONSerialization.data(withJSONObject:record).write(to:recordURL,options:.atomic)
        } catch {
            try? JSONSerialization.data(withJSONObject:["passed":false,"error":error.localizedDescription]).write(to:recordURL,options:.atomic)
        }
    }
}
#endif
