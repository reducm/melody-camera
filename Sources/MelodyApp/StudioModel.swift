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
    @Published var baseURL: String = UserDefaults.standard.string(forKey: "provider.baseURL") ?? ""
    @Published var modelName: String = UserDefaults.standard.string(forKey: "provider.model") ?? ""
    @Published var apiKey = ""
    @Published var uploadEnabled = false
    private var task: Task<Void, Never>?
    private var editTask: Task<Void, Never>?
    private var editGeneration = 0
    #if os(iOS)
    let camera: CameraController
    #endif

    private let cameraDriver: any CameraOperating
    init(loadCredentials: Bool = true, cameraDriver: (any CameraOperating)? = nil) {
        #if os(iOS)
        let hardware = CameraController()
        camera = hardware
        self.cameraDriver = cameraDriver ?? hardware
        #else
        self.cameraDriver = cameraDriver ?? UnavailableCamera()
        #endif
        if loadCredentials { apiKey = KeyStore.read() }
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
        } catch { self.error = error.localizedDescription }
    }
    func resetPlans() { plans = []; selected = nil; planSource = "" }
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
        } catch { self.error = error.localizedDescription }
    }
    func startCamera() {
        guard !busy else { return }
        busy = true; progress = "正在启动相机"
        task = Task {
            defer { busy = false; progress = "" }
            do {
                let available = try await cameraDriver.start()
                try Task.checkCancellation()
                guard !available.isEmpty else { throw CameraFailure.unavailable }
                let initialZoom = available.contains(1) ? 1 : available[0]
                try await cameraDriver.setZoom(initialZoom)
                // 设置倍率的硬件回调不能保证响应取消，因此在提交 UI 状态前再次检查。
                try Task.checkCancellation()
                zooms = available; zoom = initialZoom; source = .camera; resetPlans()
            } catch is CancellationError { cameraDriver.stop() }
            catch { self.error = error.localizedDescription }
        }
    }
    func chooseZoom(_ value: Double) {
        guard !busy else { return }
        if source == .camera {
            busy = true
            task = Task {
                defer { busy = false }
                do { try await cameraDriver.setZoom(value); try Task.checkCancellation(); zoom = value; selected = nil }
                catch is CancellationError {}
                catch { self.error = error.localizedDescription }
            }
            return
        }
        zoom = value; selected = nil
    }
    func choose(_ plan: ShotPlan) {
        guard !busy else { return }
        if source == .camera {
            busy = true
            task = Task {
                defer { busy = false }
                do { try await cameraDriver.setZoom(plan.zoom); try Task.checkCancellation(); zoom = plan.zoom; selected = plan }
                catch is CancellationError {}
                catch { self.error = error.localizedDescription }
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
            plans = OfflineDirector().plans(scene: scene, availableZooms: zooms)
            planSource = "离线规则 · 按所选场景推荐，未分析画面"
            if let first = plans.first { choose(first) }
            return
        }
        guard uploadEnabled else { error = "请先在模型设置中允许本次会话上传取景缩略图。"; return }
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
                let director = OnlineDirector(config: configuration, transport: { try await NetworkTransport.shared.send($0) })
                let results = try await director.recommend(frames: frames, availableZooms: zooms)
                try Task.checkCancellation()
                plans = results; selected = nil
                planSource = "在线视觉 · \(modelName) · \(frames.count) 张取景图"
                notice = "分析完成，选择一个方案开始构图。"
            } catch is CancellationError { notice = "已取消分析。" }
            catch let error as URLError where error.code == .cancelled { notice = "已取消分析。" }
            catch { self.error = error.localizedDescription }
        }
    }
    func cancel() { task?.cancel() }
    func suspend() {
        cancel()
        cameraDriver.stop()
        if source == .camera { source = .demo; zooms = [1,2]; zoom = 1; resetPlans() }
    }
    func capture() {
        guard !busy else { return }
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
                originalData = capturedData; original = image; edited = image; compare = false; style = .natural; amount = 0.6
                showEditor = true; updateEdit()
            } catch is CancellationError { notice = "已取消拍摄。" }
            catch { self.error = error.localizedDescription }
        }
    }
    func updateEdit() {
        guard let original else { return }
        editTask?.cancel(); editGeneration += 1
        let generation = editGeneration, style = style, amount = amount
        editTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(80))
                let image = try await Task.detached(priority: .userInitiated) { try PhotoProcessor.render(original, style: style, amount: amount) }.value
                try Task.checkCancellation()
                guard generation == editGeneration else { return }
                edited = image
            } catch is CancellationError {} catch { self.error = error.localizedDescription }
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
        Task {
            do {
                let data = try exportData(original: original)
                let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
                guard status == .authorized || status == .limited else { error = "相册写入权限未开启，可在系统设置中允许保存照片。"; return }
                try await PHPhotoLibrary.shared().performChanges {
                    PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil)
                }
                notice = original ? "原片已保存到相册。" : "调色副本已保存到相册。"
            } catch { self.error = error.localizedDescription }
        }
    }
    #endif
}
