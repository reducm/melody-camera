import Foundation
import SwiftUI
import ImageIO
import MelodyCore
import MelodyImaging

@MainActor final class ReferenceGenerationController: ObservableObject {
    @Published private(set) var jobs: [ReferenceJob] = []
    @Published var enabled: Bool
    @Published var resolution: ReferenceResolution
    let providerName = "Draw Things · 此 iPhone 本地 Qwen"
    var modelStatus: String { PhoneReferenceProvider.modelStatus }
    @Published var configurationError: String?
    private let root: URL?
    private var tasks: [UUID:Task<Void,Never>] = [:]
    private var images: [UUID:Data] = [:]
    private let injected: (any ReferenceImageGenerating)?
    private let outlineExtractor: @Sendable (Data) throws -> [SubjectOutline]
    init(root:URL? = nil,loadSettings:Bool = true,provider:(any ReferenceImageGenerating)? = nil,
         outlineExtractor: @escaping @Sendable (Data) throws -> [SubjectOutline] = { try SubjectSegmenter.outlines(in:PhotoProcessor.load($0)) }) {
        self.root=root; injected=provider
        self.outlineExtractor = outlineExtractor
        enabled=loadSettings ? (UserDefaults.standard.object(forKey:"reference.phone.enabled") as? Bool ?? true) : false
        resolution=loadSettings ? ReferenceResolution(rawValue:UserDefaults.standard.string(forKey:"reference.resolution") ?? "") ?? .square512 : .square512
        if let root {
            let files=(try? FileManager.default.contentsOfDirectory(at:root,includingPropertiesForKeys:nil)) ?? []
            for folder in files where UUID(uuidString:folder.lastPathComponent) != nil {
                let url=folder.appendingPathComponent("job.json")
                guard let size=try? url.resourceValues(forKeys:[.fileSizeKey]).fileSize,size <= 64_000,
                      let data=try? Data(contentsOf:url),var job=try? JSONDecoder().decode(ReferenceJob.self,from:data),job.id.uuidString == folder.lastPathComponent,
                      (try? job.request.validated()) != nil,job.message.count <= 160,job.provider.count <= 100,
                      job.progress.map({ $0.isFinite && (0...1).contains($0) }) ?? true else { continue }
                if let design = job.design, (try? design.validate(for:job.id)) == nil { continue }
                if job.isActive { job.state = .cancelled; job.progress=nil; job.message="上次生成已中断，可重试" }
                jobs.append(job)
            }
            jobs.sort { $0.createdAt < $1.createdAt }
        }
    }
    func saveSettings() {
        UserDefaults.standard.set(enabled,forKey:"reference.phone.enabled")
        UserDefaults.standard.set(resolution.rawValue,forKey:"reference.resolution")
        configurationError=nil
    }
    func job(projectID:UUID,photoID:UUID,batchID:UUID,planID:String) -> ReferenceJob? {
        jobs.last { $0.provider == providerName && $0.request.projectID == projectID && $0.request.photoID == photoID && $0.request.batchID == batchID && $0.request.plan.id == planID }
    }
    func enqueue(_ request:ReferenceImageRequest,jpeg:Data,retry:Bool = false) {
        guard enabled else { return }
        guard (try? request.validated()) != nil,!jpeg.isEmpty,jpeg.count <= 2_000_000 else {
            configurationError="参考图输入或推荐参数无效，请重新生成推荐。"; return
        }
        if let existing=job(projectID:request.projectID,photoID:request.photoID,batchID:request.batchID,planID:request.plan.id), existing.isActive || (!retry && existing.state == .ready) { return }
        var request=request; request.resolution=resolution
        let job=ReferenceJob(request:request,provider:providerName)
        DiagnosticLog.shared.record(.debug, .reference, "Qwen 参考图输入 · 已排队", detail: "Qwen Image Edit 2511 · Lightning 4 步 · \(resolution.width) × \(resolution.height)\n" + ModelDiagnostics.imageSummary(jpeg) + "\n\n" + request.prompt, operationID: job.id, modelContent: true)
        jobs.append(job); persist(job)
        let provider=injected ?? PhoneReferenceProvider()
        tasks[job.id]=Task { [weak self] in
            guard let self else { return }
            defer { tasks.removeValue(forKey:job.id) }
            do {
                let data=try await provider.generate(request,jpeg:jpeg) { [weak self] status in
                    await self?.update(job.id,status:status)
                }
                try Task.checkCancellation()
                guard data.count <= 8_000_000,
                      let source=CGImageSourceCreateWithData(data as CFData,nil),
                      let props=CGImageSourceCopyPropertiesAtIndex(source,0,nil) as? [CFString:Any],
                      let width=props[kCGImagePropertyPixelWidth] as? Int,let height=props[kCGImagePropertyPixelHeight] as? Int,
                      width > 0,height > 0,width <= 4096,height <= 4096 else { throw ReferenceFailure.invalidResponse }
                // 重新编码，避免把外部元数据和定位写进本机结果。
                let clean=try await Task.detached { try PhotoProcessor.jpeg(PhotoProcessor.load(data,maxPixel:1536)) }.value
                try Task.checkCancellation()
                var designed: ReferenceDesign?
                // 分割只是提取合成图形状，不等于识别对了主体；留给用户核对。
                if request.plan.design != nil {
                    update(job.id,status:.init(id:job.id,state:.running,stage:"正在提取参考图设计轮廓"))
                    do {
                        let extractor = outlineExtractor
                        let worker = Task.detached(priority:.utility) { try extractor(clean) }
                        let outlines = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
                        designed = try ReferenceDesign(jobID:job.id,candidates:outlines)
                    } catch is CancellationError { throw CancellationError() }
                    catch { DiagnosticLog.shared.record(.warning,.reference,"参考图轮廓提取未完成，保留构图方案",operationID:job.id) }
                    try Task.checkCancellation()
                }
                if let root {
                    let directory=root.appendingPathComponent(job.id.uuidString)
                    try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
                    try clean.write(to:directory.appendingPathComponent("reference.jpg"),options:.atomic)
                } else { images[job.id]=clean }
                if let index = jobs.firstIndex(where: { $0.id == job.id }), jobs[index].isActive { jobs[index].design = designed }
                DiagnosticLog.shared.record(.info, .reference, "Qwen 生成图输出", detail: ModelDiagnostics.imageSummary(clean), operationID: job.id)
                finish(job.id,state:.ready,message:(designed?.candidates.isEmpty == false) ? "AI 生成参考 · 新轮廓待你核对" : "AI 生成参考 · 非实拍；当前构图模板仍可使用")
            } catch is CancellationError { finish(job.id,state:.cancelled,message:"参考图已取消，模板仍可跟拍") }
            catch {
                if Task.isCancelled { finish(job.id,state:.cancelled,message:"参考图已取消，模板仍可跟拍") }
                else {
                    DiagnosticLog.shared.failure(error, .reference, "Qwen 引擎调用失败", operationID: job.id)
                    let message = (error is PhoneReferenceFailure || error is ReferenceFailure) ? error.localizedDescription : "手机参考图生成失败，可重试；模板仍可跟拍。"
                    finish(job.id,state:.failed,message:message)
                }
            }
        }
    }
    private func update(_ id:UUID,status:ReferenceRemoteStatus) {
        guard let valid=try? status.validated(for:id),let index=jobs.firstIndex(where:{$0.id==id}),jobs[index].isActive else { return }
        if jobs[index].state != valid.state || jobs[index].progress != valid.progress {
            let progress = valid.progress.map { " · 采样 \(Int($0 * 100))%" } ?? ""
            DiagnosticLog.shared.record(.debug, .reference, "参考图生成状态", detail: "\(valid.state.rawValue)\(progress)", operationID: id)
        }
        jobs[index].state = valid.state == .ready ? .running : valid.state
        jobs[index].progress = valid.state == .ready ? nil : valid.progress
        jobs[index].message = valid.state == .ready ? "正在读取生成图" : (valid.stage ?? "参考图生成中")
        persist(jobs[index])
    }
    private func finish(_ id:UUID,state:ReferenceState,message:String) {
        guard let index=jobs.firstIndex(where:{$0.id==id}),jobs[index].state != .cancelled || state == .cancelled else { return }
        if jobs[index].state != state {
            DiagnosticLog.shared.record(state == .failed ? .error : (state == .cancelled ? .warning : .info), .reference,
                state == .ready ? "参考图已保存" : (state == .cancelled ? "参考图已取消" : "参考图生成失败"),
                detail: String(format: "总耗时（含排队） %.2f 秒", Date().timeIntervalSince(jobs[index].createdAt)), operationID: id)
        }
        jobs[index].state=state; jobs[index].message=message; jobs[index].progress=state == .ready ? 1 : nil; persist(jobs[index])
    }
    func cancel(_ id:UUID) {
        tasks[id]?.cancel(); finish(id,state:.cancelled,message:"参考图已取消，模板仍可跟拍")
    }
    func approveDesign(jobID:UUID,candidateID:Int,checks:ReferenceReviewChecks) throws {
        guard let index = jobs.firstIndex(where: { $0.id == jobID }), jobs[index].state == .ready,
              job(projectID:jobs[index].request.projectID,photoID:jobs[index].request.photoID,batchID:jobs[index].request.batchID,planID:jobs[index].request.plan.id)?.id == jobID,
              var design = jobs[index].design else { throw CompositionError.invalidPlan }
        try design.approve(candidateID:candidateID,checks:checks,expectedJobID:jobID)
        jobs[index].design = design; persist(jobs[index])
    }
    func revokeDesign(_ jobID:UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == jobID }), jobs[index].state == .ready else { return }
        jobs[index].design?.revoke(); persist(jobs[index])
    }
    func suspend() { for job in jobs where job.isActive { cancel(job.id) } }
    func imageData(_ id:UUID) -> Data? {
        if let image=images[id] { return image }
        guard let url=root?.appendingPathComponent(id.uuidString).appendingPathComponent("reference.jpg"),
              let size=try? url.resourceValues(forKeys:[.fileSizeKey]).fileSize,size <= 8_000_000 else { return nil }
        return try? Data(contentsOf:url)
    }
    private func persist(_ job:ReferenceJob) {
        guard let root else { return }
        do {
            let directory=root.appendingPathComponent(job.id.uuidString)
            try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
            try JSONEncoder().encode(job).write(to:directory.appendingPathComponent("job.json"),options:.atomic)
            var folder=root; var attributes=URLResourceValues(); attributes.isExcludedFromBackup=true; try folder.setResourceValues(attributes)
        } catch { DiagnosticLog.shared.failure(error, .storage, "参考图记录保存失败", operationID: job.id); configurationError="参考图记录暂未保存到本机，请检查可用空间。" }
    }
}
