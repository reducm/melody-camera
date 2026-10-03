import SwiftUI
import UniformTypeIdentifiers
import MelodyCore
import MelodyImaging
#if os(iOS)
import Photos
#endif

enum InputSource: String { case demo = "演示场景", imported = "导入照片", camera = "实景相机" }
enum DirectorMode: String, CaseIterable { case offline = "离线构图", online = "在线视觉" }

@MainActor final class StudioModel: ObservableObject {
    let references: ReferenceGenerationController
    @Published var currentProject: ShootingProject?
    @Published var projectHistory: [ShootingProject] = []
    @Published var historyMessage = ""
    @Published var pendingProjectSaves = 0
    @Published var historySaveFailed = false
    private let projectStore: ProjectLibrary?
    private var projectSaveTask: Task<Void, Never>?
    private var unsavedProjectIDs: Set<UUID> = []
    private var pendingOriginals: [UUID: Data] = [:]
    private var captureReference: CaptureReference?
    @Published var scene: SceneKind = .garden
    @Published var source: InputSource = .demo
    @Published var mode: DirectorMode = .offline
    @Published var zoom: Double = 1
    @Published var zooms: [Double] = [1, 2]
    @Published var grid = true
    @Published var guideOpacity = 0.75
    @Published var plans: [ShotPlan] = []
    @Published var selected: ShotPlan?
    @Published var planSource = ""
    @Published var busy = false
    @Published var progress = ""
    @Published var error: String?
    @Published var notice = ""
    @Published var imported: CGImage?
    private var importedData: Data?
    @Published var original: CGImage?
    @Published var edited: CGImage?
    @Published var originalData: Data?
    @Published var style: ColorStyle = .natural
    @Published var amount = 0.6
    @Published var compare = false
    @Published var showEditor = false
    @Published var baseURL: String = UserDefaults.standard.string(forKey: "provider.baseURL") ?? "https://api.deepseek.com"
    @Published var modelName: String = UserDefaults.standard.string(forKey: "provider.model") ?? "deepseek-flash"
    @Published var apiKey = ""
    @Published var savingPhoto = false
    @Published var photoBackend: PhotoBackend = .online
    @Published var localModelStatus = GemmaModelStore.isInstalled ? "Gemma 模型已校验并安装" : "尚未导入 Gemma 模型"
    @Published var installingModel = false
    @Published var subjectOutlines: [SubjectOutline] = []
    @Published var photographyStyle: PhotographyStyle = .natural
    @Published var selectedOutlineID: Int?
    @Published var outlining = false
    @Published var outlineNotice = ""
    @Published var guideOutline: SubjectOutline?
    private var outlineTask: Task<Void, Never>?
    private var outlineGeneration = 0
    private let enableSegmentation: Bool
    var selectedOutline: SubjectOutline? { subjectOutlines.first { $0.id == selectedOutlineID } }
    @Published var photoAnalysis: PhotoAnalysis?
    @Published var photoAnalysisSource = ""
    @Published var analyzingPhoto = false
    @Published var photoSource: InputSource = .demo
    private var photoZoom: Double = 1
    private var photoZooms: [Double] = [1]
    private var photoTask: Task<Void, Never>?
    private let photoTransport: OnlineDirector.Transport
    private var task: Task<Void, Never>?
    private var editTask: Task<Void, Never>?
    private var editGeneration = 0
    #if os(iOS)
    let camera: CameraController
    #endif

    private let cameraDriver: any CameraOperating
    init(loadCredentials: Bool = true, enableSegmentation: Bool = true, projectStore: ProjectLibrary? = nil, cameraDriver: (any CameraOperating)? = nil, photoTransport: @escaping OnlineDirector.Transport = { try await NetworkTransport.shared.send($0) }) {
        let isDiagnostic = ProcessInfo.processInfo.arguments.contains { $0.hasPrefix("--melody-check-") }
        let projectCheck = ProcessInfo.processInfo.arguments.contains { $0.hasPrefix("--melody-check-project") }
        let projectsDirectory = FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent((projectCheck && !ProcessInfo.processInfo.arguments.contains(where:{$0.hasPrefix("--melody-check-project-reference")})) ? "ProjectChecks" : "Projects",isDirectory:true)
        self.projectStore = projectStore ?? ((loadCredentials && (!isDiagnostic || projectCheck)) ? ProjectLibrary(root:projectsDirectory) : nil)
        references = ReferenceGenerationController(root:loadCredentials ? FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("ReferenceDrafts") : nil,loadSettings:loadCredentials)
        self.photoTransport = ModelDiagnostics.transport(photoTransport)
        self.enableSegmentation = enableSegmentation
        #if os(iOS)
        let hardware = CameraController()
        camera = hardware
        self.cameraDriver = cameraDriver ?? hardware
        #else
        self.cameraDriver = cameraDriver ?? UnavailableCamera()
        #endif
        if loadCredentials {
            photographyStyle = PhotographyStyle(rawValue:UserDefaults.standard.string(forKey:"recommendation.style") ?? "") ?? .natural
            do {
                try DebugProvisioning.consumeReference(into:references)
                if let config = try DebugProvisioning.consumeProvider() {
                    baseURL = config.baseURL; modelName = config.model
                    UserDefaults.standard.set(baseURL, forKey: "provider.baseURL")
                    UserDefaults.standard.set(modelName, forKey: "provider.model")
                }
            } catch { self.error = "个人模型配置导入失败，请在设置中重新填写。" }
            apiKey = KeyStore.read()
            #if DEBUG
            Task { await runDeviceGemmaCheck() }
            #endif
        }
    }
    var previewImage: CGImage? {
        guard let imported else { return nil }
        return try? PhotoProcessor.crop(imported, zoom: zoom)
    }
    func saveSettings() {
        do {
            try KeyStore.save(apiKey)
            UserDefaults.standard.set(baseURL, forKey: "provider.baseURL")
            UserDefaults.standard.set(modelName, forKey: "provider.model")
            notice = "配置已保存，密钥保存在本机钥匙串。"
        } catch { DiagnosticLog.shared.failure(error, .storage, "配置保存失败"); self.error = error.localizedDescription }
    }
    func resetPlans() { plans = []; selected = nil; planSource = ""; guideOutline = nil }
    func changeScene() { resetPlans(); if source != .camera { zoom = 1 } }
    func demo() {
        cancel()
        cameraDriver.stop()
        source = .demo; imported = nil; importedData = nil; zooms = [1,2]; zoom = 1; resetPlans()
    }
    func loadPhoto(_ url: URL) {
        guard !busy else { return }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 40_000_000 else { error = "请选择小于 40 MB 的图片。"; return }
            let data = try Data(contentsOf: url)
            let image = try PhotoProcessor.load(data)
            cameraDriver.stop()
            imported = image; importedData = data; source = .imported; zooms = [1]; zoom = 1; resetPlans()
            notice = "已导入照片，保留原始文件；在线分析前需要单独开启上传。"
        } catch { DiagnosticLog.shared.failure(error, .storage, "照片读取失败"); self.error = error.localizedDescription }
    }
    func startCamera(plan: ShotPlan? = nil) {
        guard !busy else { return }
        DiagnosticLog.shared.record(.info, .camera, "正在启动相机")
        busy = true; progress = "正在启动相机"
        task = Task {
            defer { busy = false; progress = "" }
            do {
                let available = try await cameraDriver.start()
                try Task.checkCancellation()
                guard !available.isEmpty else { throw CameraFailure.unavailable }
                if let plan, !available.contains(where: { abs($0 - plan.zoom) < 0.001 }) {
                    throw CompositionError.invalidPlan
                }
                let initialZoom = plan?.zoom ?? (available.contains(1) ? 1 : available[0])
                try await cameraDriver.setZoom(initialZoom)
                // 设置倍率的硬件回调不能保证响应取消，因此在提交 UI 状态前再次检查。
                try Task.checkCancellation()
                zooms = available; zoom = initialZoom; source = .camera; resetPlans(); showEditor = false
                if let plan {
                    plans = [plan]; selected = plan; planSource = photoAnalysisSource
                    guideOutline = plan.design?.outline ?? (plan.design == nil ? selectedOutline : nil)
                    showEditor = false
                    if let photo = currentProject?.activePhoto, let batch = photo.selectedBatch {
                        captureReference = CaptureReference(photoID:photo.id,batchID:batch.id,planID:plan.id,outline:guideOutline,planSnapshot:plan.design == nil ? nil : plan)
                    }
                } else { captureReference = nil }
                DiagnosticLog.shared.record(.info, .camera, "相机已就绪", detail: "可用倍率：\(available)")
                notice = "实景相机已开启，点击快门拍照；拍后可分析照片并推荐模板。"
            } catch is CancellationError { cameraDriver.stop() }
            catch { cameraDriver.stop(); DiagnosticLog.shared.failure(error, .camera, "相机启动失败"); self.error = error.localizedDescription }
        }
    }
    func chooseZoom(_ value: Double) {
        guard !busy else { return }
        if source == .camera {
            busy = true
            task = Task {
                defer { busy = false }
                do { try await cameraDriver.setZoom(value); try Task.checkCancellation(); zoom = value }
                catch is CancellationError {}
                catch { DiagnosticLog.shared.failure(error, .camera, "相机倍率切换失败"); self.error = error.localizedDescription }
            }
            return
        }
        zoom = value
    }
    func choose(_ plan: ShotPlan) {
        guard !busy else { return }
        if source == .camera {
            busy = true
            task = Task {
                defer { busy = false }
                do { try await cameraDriver.setZoom(plan.zoom); try Task.checkCancellation(); zoom = plan.zoom; selected = plan }
                catch is CancellationError {}
                catch { DiagnosticLog.shared.failure(error, .camera, "跟拍倍率设置失败"); self.error = error.localizedDescription }
            }
            return
        }
        zoom = plan.zoom; selected = plan
    }
    func renderedDemo() throws -> CGImage {
        let renderer = ImageRenderer(content: DemoScene(scene: scene).frame(width: 750, height: 1000))
        renderer.scale = 1
        guard let image = renderer.cgImage else { throw PhotoError.render }
        return try PhotoProcessor.crop(image, zoom: zoom)
    }
    func observation() async throws -> [ObservationFrame] {
        if source == .camera {
            let previous = zoom
            var frames: [ObservationFrame] = []
            do {
                for value in zooms.prefix(3) {
                    try Task.checkCancellation()
                    progress = "正在观察 \(value.formatted())× · 请保持人物不动"
                    try await cameraDriver.setZoom(value)
                    try await Task.sleep(for: .milliseconds(450))
                    let data = try await cameraDriver.capture()
                    let image = try PhotoProcessor.load(data, maxPixel: 1024)
                    frames.append(.init(jpeg: try PhotoProcessor.jpeg(image, quality: 0.75), zoom: value))
                }
                try await cameraDriver.setZoom(previous)
                return frames
            } catch {
                try? await cameraDriver.setZoom(previous)
                throw error
            }
        }
        let image: CGImage
        if source == .imported, let previewImage { image = previewImage }
        else { image = try renderedDemo() }
        let data = try PhotoProcessor.jpeg(image, quality: 0.75)
        let reduced = try PhotoProcessor.load(data, maxPixel: 1024)
        return [.init(jpeg: try PhotoProcessor.jpeg(reduced, quality: 0.75), zoom: zoom)]
    }
    func analyze() {
        guard !busy else { return }
        if mode == .offline {
            DiagnosticLog.shared.record(.info, .analysis, "生成离线构图规则（未调用模型）")
            plans = OfflineDirector().plans(scene: scene, availableZooms: zooms)
            planSource = "离线规则 · 按所选场景推荐，未分析画面"
            if let first = plans.first { choose(first) }
            return
        }
        busy = true; progress = "正在准备取景图"
        task = Task {
            defer { busy = false; progress = "" }
            do {
                let configuration = ProviderConfiguration(baseURL: baseURL, model: modelName, apiKey: apiKey)
                // 在拍摄之前检查配置，避免白白采样。
                _ = try VisionRequest.make(config: configuration, frames: [.init(jpeg: Data([1]), zoom: 1)], availableZooms: zooms)
                let frames = try await observation()
                try Task.checkCancellation()
                progress = "正在分析构图 · 可随时取消"
                let director = OnlineDirector(config: configuration, transport: photoTransport)
                let results = try await director.recommend(frames: frames, availableZooms: zooms)
                try Task.checkCancellation()
                plans = results; selected = nil
                planSource = "在线视觉 · \(modelName) · \(frames.count) 张取景图"
                notice = "分析完成，选择一个方案开始构图。"
            } catch is CancellationError { notice = "已取消分析。" }
            catch let error as URLError where error.code == .cancelled { notice = "已取消分析。" }
            catch { DiagnosticLog.shared.failure(error, .analysis, "构图分析失败"); self.error = error.localizedDescription }
        }
    }
    func cancel() { task?.cancel(); photoTask?.cancel(); outlineTask?.cancel() }
    func cancelPhotoAnalysis() { photoTask?.cancel() }
    func extractSubjectOutlines(_ image: CGImage) {
        guard enableSegmentation else { return }
        outlineTask?.cancel(); outlineGeneration += 1
        let generation = outlineGeneration
        subjectOutlines = []; selectedOutlineID = nil; outlining = true; outlineNotice = "正在本机提取主体轮廓，不上传照片"
        outlineTask = Task {
            defer { if generation == outlineGeneration { outlining = false } }
            do {
                let worker = Task.detached(priority: .userInitiated) { try SubjectSegmenter.outlines(in: image) }
                let outlines = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
                try Task.checkCancellation()
                guard generation == outlineGeneration else { return }
                DiagnosticLog.shared.record(.info, .analysis, "Apple Vision 主体轮廓提取完成", detail: "轮廓数量：\(outlines.count)")
                subjectOutlines = outlines
                selectedOutlineID = outlines.first(where: { $0.id == currentProject?.activePhoto?.selectedOutlineID })?.id ?? outlines.first?.id
                outlineNotice = "Apple Vision 本机分割 · 请核对并选择主体；边缘可能不完整"
            } catch is CancellationError {}
            catch {
                guard generation == outlineGeneration else { return }
                DiagnosticLog.shared.failure(error, .analysis, "Apple Vision 主体轮廓提取失败")
                outlineNotice = "本机未提取到可靠轮廓，可重新提取或换一张背景简单的照片。模板将只显示目标范围。"
            }
        }
    }
    func importPhotoData(_ data: Data) async {
        guard !busy else { return }
        guard !data.isEmpty, data.count <= 40_000_000 else { error = "请选择小于 40 MB 的图片。"; return }
        busy = true; progress = "正在打开照片"
        defer { busy = false; progress = "" }
        do {
            let image = try await Task.detached(priority: .userInitiated) { try PhotoProcessor.load(data) }.value
            try Task.checkCancellation()
            cameraDriver.stop()
            imported = image; importedData = data; source = .imported; zooms = [1]; zoom = 1; resetPlans()
            original = image; originalData = data; edited = image; compare = false; style = .natural; amount = 0.6
            photoSource = .imported; photoZoom = 1; photoZooms = [1]; captureReference = nil
            photoAnalysis = nil; photoAnalysisSource = ""; showEditor = true
            notice = "照片已加入当前项目，可以生成推荐或继续编辑。"
            rememberCurrentPhoto(data); updateEdit(); extractSubjectOutlines(image)
        } catch is CancellationError {}
        catch { DiagnosticLog.shared.failure(error, .storage, "照片导入失败"); self.error = error.localizedDescription }
    }
    func analyzePhoto() {
        guard !busy else { return }
        guard let original else { error = "请先拍摄或导入一张照片。"; return }
        let configuration = ProviderConfiguration(baseURL: baseURL, model: modelName, apiKey: apiKey)
        let backend = photoBackend
        let callID = UUID()
        let availableZooms = photoZooms
        let capturedZoom = photoZoom
        let capturedOutline = selectedOutline
        let analysisContext = AnalysisContext(style:photographyStyle, selectedBounds:capturedOutline?.bounds, sourceAspect:Double(original.width)/Double(original.height))
        let expectedPhotoID = currentProject?.activePhotoID
        let expectedProjectID = currentProject?.id
        let sourceLabel = photoSource == .demo ? "演示画面分析 · 非实拍" : (backend == .gemma ? "本机照片分析" : "在线照片分析")
        DiagnosticLog.shared.record(.info, .analysis, "开始照片分析", detail: backend.rawValue, operationID: callID)
        busy = true; analyzingPhoto = true; progress = "正在分析照片的光线、构图与背景"
        error = nil
        photoTask = Task {
            defer { busy = false; analyzingPhoto = false; progress = "" }
            do {
                // 配置校验先于图像处理与网络请求。
                if backend == .online {
                    _ = try VisionRequest.make(config: configuration, frames: [.init(jpeg: Data([1]), zoom: capturedZoom)], availableZooms: availableZooms)
                } else if !GemmaModelStore.isInstalled { throw LocalModelFailure.missing }
                let jpeg = try await Task.detached(priority: .userInitiated) {
                    let data = try PhotoProcessor.jpeg(original, quality: 0.75)
                    let image = try PhotoProcessor.load(data, maxPixel: 1024)
                    return try PhotoProcessor.jpeg(image, quality: 0.75)
                }.value
                try Task.checkCancellation()
                let analyst: any PhotoAnalyzing = backend == .gemma ? GemmaPhotoAnalyst(context:analysisContext) : OnlinePhotoAnalyst(config: configuration, context:analysisContext, transport: photoTransport)
                let observation = try await ModelDiagnostics.$operationID.withValue(callID) {
                    try await analyst.analyze(frame: .init(jpeg: jpeg, zoom: capturedZoom), availableZooms: availableZooms)
                }
                try Task.checkCancellation()
                guard currentProject?.id == expectedProjectID, currentProject?.activePhotoID == expectedPhotoID else { throw CancellationError() }
                progress = "正在检索摄影知识并计算目标构图"
                let report = try RecommendationEngine.recommend(report:observation, context:analysisContext, outline:capturedOutline, availableZooms:availableZooms, capturedZoom:capturedZoom)
                DiagnosticLog.shared.record(.info, .analysis, "照片分析通过结构校验", detail: "推荐模板数量：\(report.plans.count)", operationID: callID)
                photoAnalysis = report
                photoAnalysisSource = sourceLabel + " · " + (backend == .gemma ? "Gemma 4 E2B" : configuration.model) + " · 摄影知识规则 v1"
                currentProject?.addRecommendation(report, source: photoAnalysisSource)
                persistCurrentProject()
                notice = "已保存这一轮推荐，选择模板开始跟拍。"
                if let project=currentProject,let photo=project.activePhoto,let batch=photo.selectedBatch,references.enabled {
                    for plan in report.plans { references.enqueue(ReferenceImageRequest(projectID:project.id,photoID:photo.id,batchID:batch.id,plan:plan),jpeg:jpeg) }
                }
            } catch is CancellationError { DiagnosticLog.shared.record(.warning, .analysis, "照片分析已取消", operationID: callID); notice = "已取消照片分析。" }
            catch let failure as URLError where failure.code == .cancelled { DiagnosticLog.shared.record(.warning, .analysis, "照片分析已取消", operationID: callID); notice = "已取消照片分析。" }
            catch { DiagnosticLog.shared.failure(error, .analysis, "照片分析或结果校验失败", operationID: callID); self.error = error.localizedDescription }
        }
    }
    func generateReference(_ plan:ShotPlan,retry:Bool = false) {
        guard let project=currentProject,let photo=project.activePhoto,let batch=photo.selectedBatch, batch.report.plans.contains(plan),let original else { return }
        let request=ReferenceImageRequest(projectID:project.id,photoID:photo.id,batchID:batch.id,plan:plan)
        Task {
            do {
                let jpeg=try await Task.detached { try PhotoProcessor.jpeg(PhotoProcessor.load(PhotoProcessor.jpeg(original),maxPixel:768),quality:0.8) }.value
                references.enqueue(request,jpeg:jpeg,retry:retry)
            } catch { references.configurationError="参考图输入准备失败，请重新打开照片。" }
        }
    }
    func installLocalModel(_ url: URL) {
        guard !busy, !installingModel else { return }
        installingModel = true; busy = true
        localModelStatus = "正在复制并校验 Gemma 文件，请保持应用在前台"
        task = Task {
            defer { installingModel = false; busy = false }
            do {
                let worker = Task.detached(priority: .utility) { try GemmaModelStore.install(from: url) }
                try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
                localModelStatus = "Gemma 4 E2B 已校验并安装 · 可离线分析照片"
            } catch is CancellationError { localModelStatus = "Gemma 安装已取消" }
            catch { localModelStatus = "Gemma 安装失败"; DiagnosticLog.shared.failure(error, .model, "Gemma 安装失败"); self.error = error.localizedDescription }
        }
    }
    func savePhotographyStyle() { UserDefaults.standard.set(photographyStyle.rawValue,forKey:"recommendation.style") }
    func planForFollowing(_ plan: ShotPlan) -> ShotPlan {
        guard let project = currentProject, let photo = project.activePhoto, let batch = photo.selectedBatch,
              let job = references.job(projectID:project.id,photoID:photo.id,batchID:batch.id,planID:plan.id),
              job.state == .ready, let design = job.design, design.approvedOutline != nil,
              let adopted = try? plan.adopting(design) else { return plan }
        return adopted
    }
    func applyPhotoPlan(_ plan: ShotPlan) {
        guard !busy, photoAnalysis?.plans.contains(plan) == true else { return }
        let plan = planForFollowing(plan)
        #if os(iOS)
        startCamera(plan: plan)
        #else
        plans = photoAnalysis?.plans ?? []; planSource = photoAnalysisSource
        choose(plan); guideOutline = plan.design?.outline ?? (plan.design == nil ? selectedOutline : nil); showEditor = false
        #endif
    }
    func suspend() {
        references.suspend()
        cancel()
        cameraDriver.stop()
        if source == .camera { source = .demo; zooms = [1,2]; zoom = 1; resetPlans() }
    }
    func capture() {
        guard !busy else { return }
        DiagnosticLog.shared.record(.info, .camera, source == .camera ? "开始拍摄" : "开始生成练习照片（非实拍）")
        busy = true; progress = "正在保存这一刻"
        task = Task {
            defer { busy = false; progress = "" }
            do {
                let image: CGImage
                let capturedData: Data
                if source == .camera {
                    let data = try await cameraDriver.capture(); try Task.checkCancellation()
                    image = try PhotoProcessor.load(data, maxPixel: 4096); capturedData = data
                } else {
                    if source == .imported, let imported { image = imported; capturedData = try importedData ?? PhotoProcessor.jpeg(image) }
                    else { image = try renderedDemo(); capturedData = try PhotoProcessor.jpeg(image) }
                }
                photoAnalysis = nil; photoAnalysisSource = ""
                photoSource = source; photoZoom = zoom; photoZooms = zooms
                if source == .camera { cameraDriver.stop() }
                notice = "新照片已加入当前项目，生成推荐后可以继续跟拍。"
                DiagnosticLog.shared.record(.info, .camera, source == .camera ? "照片拍摄完成" : "练习照片已生成（非实拍）", detail: ModelDiagnostics.imageSummary(capturedData))
                originalData = capturedData; original = image; edited = image; compare = false; style = .natural; amount = 0.6
                showEditor = true; rememberCurrentPhoto(capturedData); updateEdit(); extractSubjectOutlines(image)
            } catch is CancellationError { notice = "已取消拍摄。" }
            catch { DiagnosticLog.shared.failure(error, .camera, "照片拍摄失败"); self.error = error.localizedDescription }
        }
    }
    func updateEdit() {
        guard let original else { return }
        persistCurrentProject()
        editTask?.cancel(); editGeneration += 1
        let generation = editGeneration, style = style, amount = amount
        editTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(80))
                let image = try await Task.detached(priority: .userInitiated) { try PhotoProcessor.render(original, style: style, amount: amount) }.value
                try Task.checkCancellation()
                guard generation == editGeneration else { return }
                edited = image
            } catch is CancellationError {} catch { DiagnosticLog.shared.failure(error, .storage, "照片预览处理失败"); self.error = error.localizedDescription }
        }
    }
    func exportData(original shouldUseOriginal: Bool) throws -> Data {
        if shouldUseOriginal, let originalData { return originalData }
        guard let original else { throw PhotoError.render }
        // 根据当前配方同步生成，避免滑块防抖期间导出旧预览。
        return try PhotoProcessor.jpeg(PhotoProcessor.render(original, style: style, amount: amount))
    }
    #if os(iOS)
    func saveToPhotos(original: Bool) {
        guard !savingPhoto else { return }
        savingPhoto = true
        Task {
            defer { savingPhoto = false }
            do {
                let data = try exportData(original: original)
                let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
                guard status == .authorized || status == .limited else { error = "相册写入权限未开启，可在系统设置中允许保存照片。"; return }
                try await PHPhotoLibrary.shared().performChanges {
                    PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil)
                }
                DiagnosticLog.shared.record(.info, .storage, "照片已保存到系统相册")
                notice = original ? "原片已保存到相册。" : "调色副本已保存到相册。"
            } catch { DiagnosticLog.shared.failure(error, .storage, "相册保存失败"); self.error = error.localizedDescription }
        }
    }
    #endif
}

@MainActor extension StudioModel {
    func renameProject(_ title: String) {
        currentProject?.rename(title)
        persistCurrentProject()
    }
    var followedPlan: ShotPlan? {
        guard let project = currentProject, let photo = project.activePhoto else { return nil }
        return project.followedPlan(for: photo)
    }
    var followedOutline: SubjectOutline? { currentProject?.activePhoto?.capturedFollowing?.outline }
    var recommendationBatches: [RecommendationBatch] { currentProject?.activePhoto?.recommendations ?? [] }
    var projectTitle: String { currentProject?.title ?? "新的拍摄" }
    var currentPhotoNumber: Int { (currentProject?.photos.firstIndex(where: { $0.id == currentProject?.activePhotoID }) ?? 0) + 1 }
    func rememberCurrentPhoto(_ data: Data) {
        selectedOutlineID = nil; subjectOutlines = []; outlineNotice = ""
        if currentProject == nil { currentProject = ShootingProject() }
        let origin: String = photoSource == .camera ? "camera" : (photoSource == .imported ? "imported" : "demo")
        let photo = ProjectPhoto(origin:origin,zoom:photoZoom,availableZooms:photoZooms,capturedFollowing:captureReference)
        pendingOriginals[photo.id] = data
        currentProject?.append(photo)
        captureReference = nil
    }
    func persistCurrentProject() {
        guard var snapshot = currentProject, let index = snapshot.photos.firstIndex(where: { $0.id == snapshot.activePhotoID }) else { return }
        snapshot.photos[index].editStyle = style.rawValue; snapshot.photos[index].editAmount = amount
        if !outlining { snapshot.photos[index].selectedOutlineID = selectedOutlineID }
        snapshot.updatedAt = Date(); currentProject = snapshot
        projectHistory.removeAll { $0.id == snapshot.id }; projectHistory.insert(snapshot,at:0)
        guard let projectStore else { return }
        let bytes = pendingOriginals.filter { id, _ in snapshot.photos.contains { $0.id == id } }
        let previous = projectSaveTask
        unsavedProjectIDs.insert(snapshot.id); pendingProjectSaves += 1
        projectSaveTask = Task {
            await previous?.value
            defer { pendingProjectSaves -= 1 }
            do {
                try await projectStore.save(snapshot,originals:bytes)
                for id in bytes.keys { pendingOriginals.removeValue(forKey:id) }
                // 同一个项目后面若还有快照，保留待保存标记到最后一次完成。
                if projectHistory.first(where: { $0.id == snapshot.id })?.updatedAt == snapshot.updatedAt { unsavedProjectIDs.remove(snapshot.id) }
                historySaveFailed = !unsavedProjectIDs.isEmpty && pendingProjectSaves == 1
            } catch {
                DiagnosticLog.shared.failure(error, .storage, "项目保存失败")
                historySaveFailed = true
                historyMessage = "项目未能保存到本机。请保留应用并重试保存，原片仍在当前会话。"
            }
        }
    }
    func waitForProjectSave() async { await projectSaveTask?.value }
    func refreshProjectHistory() async {
        await waitForProjectSave()
        guard let projectStore else { return }
        do {
            let result = try await projectStore.list()
            let unsaved = projectHistory.filter { unsavedProjectIDs.contains($0.id) }
            projectHistory = (result.projects.filter { !unsavedProjectIDs.contains($0.id) } + unsaved).sorted { $0.updatedAt > $1.updatedAt }
            if !historySaveFailed { historyMessage = result.unreadableCount > 0 ? "有 \(result.unreadableCount) 个项目暂时无法读取，其余历史可正常打开。" : "" }
        } catch { DiagnosticLog.shared.failure(error, .storage, "历史记录读取失败"); historyMessage = "无法读取本机历史，请稍后重试。" }
    }
    func openProject(_ id: UUID) async {
        guard !busy else { return }
        busy = true; progress = "正在恢复拍摄项目"
        defer { busy = false; progress = "" }
        await waitForProjectSave()
        do {
            let project: ShootingProject
            if let memory = projectHistory.first(where: { $0.id == id }), unsavedProjectIDs.contains(id) || projectStore == nil { project = memory }
            else if let projectStore { project = try await projectStore.load(id) }
            else { throw ProjectFailure.damaged }
            guard let photo = project.activePhoto else { throw ProjectFailure.damaged }
            try await restorePhoto(photo, in:project)
        } catch { DiagnosticLog.shared.failure(error, .storage, "项目打开失败"); self.error = error.localizedDescription }
    }
    func selectProjectPhoto(_ id: UUID) async {
        guard !busy, let project = currentProject, let photo = project.photos.first(where: { $0.id == id }) else { return }
        if id == project.activePhotoID { return }
        busy = true; progress = "正在打开项目照片"
        defer { busy = false; progress = "" }
        await waitForProjectSave()
        do { try await restorePhoto(photo,in:project); persistCurrentProject() }
        catch { DiagnosticLog.shared.failure(error, .storage, "项目照片读取失败"); self.error = error.localizedDescription }
    }
    private func restorePhoto(_ photo: ProjectPhoto, in project: ShootingProject) async throws {
        let bytes: Data
        if let pending = pendingOriginals[photo.id] { bytes = pending }
        else if let projectStore { bytes = try await projectStore.original(projectID:project.id,photoID:photo.id) }
        else { throw ProjectFailure.missingOriginal }
        let image = try await Task.detached(priority:.userInitiated) { try PhotoProcessor.load(bytes) }.value
        try Task.checkCancellation()
        cameraDriver.stop(); outlineTask?.cancel(); editTask?.cancel(); resetPlans()
        var restored = project; restored.activePhotoID = photo.id; currentProject = restored
        originalData = bytes; original = image; edited = image; imported = image; importedData = bytes
        photoSource = photo.origin == "camera" ? .camera : (photo.origin == "demo" ? .demo : .imported)
        source = .imported; zoom = 1; zooms = [1]; photoZoom = photo.zoom; photoZooms = photo.availableZooms
        style = ColorStyle(rawValue:photo.editStyle) ?? .natural; amount = photo.editAmount; compare = false
        selectedOutlineID = photo.selectedOutlineID
        photoAnalysis = photo.selectedBatch?.report; photoAnalysisSource = photo.selectedBatch?.source ?? ""
        captureReference = nil; showEditor = true
        updateEdit(); extractSubjectOutlines(image)
    }
    func chooseRecommendationBatch(_ id: UUID) {
        guard !busy, var project = currentProject,
              let index = project.photos.firstIndex(where: { $0.id == project.activePhotoID }),
              let batch = project.photos[index].recommendations.first(where: { $0.id == id }) else { return }
        project.photos[index].selectedBatchID = id; currentProject = project
        photoAnalysis = batch.report; photoAnalysisSource = batch.source
        persistCurrentProject()
    }
    func chooseOutline(_ id: Int) { selectedOutlineID = id; persistCurrentProject() }
    func newProject() {
        guard !busy else { return }
        cancel(); editTask?.cancel(); currentProject = nil; original = nil; originalData = nil; edited = nil
        imported = nil; importedData = nil; photoAnalysis = nil; photoAnalysisSource = ""
        subjectOutlines = []; selectedOutlineID = nil; captureReference = nil; showEditor = false; resetPlans()
        #if os(iOS)
        startCamera()
        #else
        source = .demo
        #endif
    }
    func retakeInProject() {
        guard !busy else { return }
        #if os(iOS)
        startCamera()
        #else
        source = .demo; resetPlans(); showEditor = false
        #endif
    }
    func enterCameraIfNeeded() {
        #if os(iOS)
        guard !busy, !showEditor, source != .camera, !ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("--melody-check-") }) else { return }
        startCamera(plan:selected)
        #endif
    }
    func pauseCameraForHistory() { cameraDriver.stop(); if source == .camera { source = .demo } }
    /// 独立加载画廊页，不切换编辑状态，不触发分割或在线分析。
    func galleryPhoto(_ id: UUID, original useOriginal: Bool) async throws -> GalleryPhoto {
        guard let project = currentProject, let photo = project.photos.first(where: { $0.id == id }) else { throw ProjectFailure.missingOriginal }
        let bytes: Data
        if let pending = pendingOriginals[id] { bytes = pending }
        else if let projectStore { bytes = try await projectStore.original(projectID:project.id,photoID:id) }
        else { throw ProjectFailure.missingOriginal }
        try Task.checkCancellation()
        let data: Data
        if useOriginal { data = bytes }
        else {
            data = try await Task.detached(priority:.userInitiated) {
                let image = try PhotoProcessor.load(bytes)
                return try PhotoProcessor.jpeg(PhotoProcessor.render(image,style:ColorStyle(rawValue:photo.editStyle) ?? .natural,amount:photo.editAmount))
            }.value
        }
        try Task.checkCancellation()
        return GalleryPhoto(id:id,data:data,plan:project.followedPlan(for:photo),outline:photo.capturedFollowing?.outline)
    }
    func thumbnail(projectID: UUID, photoID: UUID) async -> CGImage? {
        let data: Data?
        if let pending = pendingOriginals[photoID] { data = pending }
        else { data = try? await projectStore?.original(projectID:projectID,photoID:photoID) }
        guard let data else { return nil }
        return await Task.detached(priority:.utility) { try? PhotoProcessor.load(data,maxPixel:240) }.value
    }
}

struct GalleryPhoto: Identifiable, Sendable {
    let id: UUID
    let data: Data
    let plan: ShotPlan?
    let outline: SubjectOutline?
}
