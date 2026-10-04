#if DEBUG
import Foundation
import ImageIO
import MelodyCore
import MelodyImaging
#if os(iOS)
import Photos
#endif

/// 显式启动的公开照片回归。网络和快门均为标明的替身，图像处理、Vision 与持久化运行真实代码。
@MainActor enum PublicPhotoRegression {
    struct Sample: Decodable {
        let file: String
        let kind: SubjectKind
        let shape: SubjectShape
        let hasTable: Bool
        let lighting: SceneLighting
    }
    struct Result: Codable {
        let file: String
        var checks: [String: Bool] = [:]
        var segmentation = "未运行"
        var outlines = 0
        var error: String?
        var passed: Bool { error == nil && !checks.isEmpty && checks.values.allSatisfy { $0 } }
    }
    struct Report: Codable {
        var mode = "公开照片真实处理；场景文字与快门为固定测试夹具，不联网、不代表模型识别或真机拍摄"
        var samples: [Result] = []
        var completed = false
        var passed = false
        var error: String?
    }
    struct FixtureCamera: CameraOperating {
        let data: Data
        func start() async throws -> [Double] { [0.5, 1, 2] }
        func setZoom(_ zoom: Double) async throws {}
        func capture() async throws -> Data { data }
        func stop() {}
    }
    private static func settle(_ studio: StudioModel) async throws {
        for _ in 0..<600 {
            if !studio.busy && !studio.outlining { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw CameraFailure.timeout
    }
    static func run(fixtures: URL, output: URL) async -> Report {
        var report = Report()
        func save() {
            try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try? encoder.encode(report).write(to: output.appendingPathComponent("result.json"), options: .atomic)
        }
        save()
        do {
            let samples = try JSONDecoder().decode([Sample].self, from: Data(contentsOf: fixtures.appendingPathComponent("scenarios.json")))
            guard !samples.isEmpty, samples.count <= 30 else { throw PhotoError.unreadable }
            for sample in samples {
                var result = Result(file: sample.file)
                do {
                    guard sample.file == URL(fileURLWithPath: sample.file).lastPathComponent else { throw PhotoError.unreadable }
                    let bytes = try Data(contentsOf: fixtures.appendingPathComponent(sample.file))
                    let root = output.appendingPathComponent(UUID().uuidString)
                    let library = ProjectLibrary(root: root)
                    let response = try fixtureResponse(sample)
                    let studio = StudioModel(loadCredentials: false, projectStore: library, cameraDriver: FixtureCamera(data: bytes), photoTransport: { _ in (response, 200) })
                    studio.baseURL = "https://fixture.invalid"; studio.modelName = "固定场景夹具（不联网）"; studio.apiKey = "fixture-only"
                    await studio.importPhotoData(bytes)
                    try await settle(studio)
                    guard let photoID = studio.currentProject?.activePhotoID, let projectID = studio.currentProject?.id, let image = studio.original else { throw PhotoError.unreadable }
                    result.checks["导入打开编辑页且保留原字节"] = studio.showEditor && studio.originalData == bytes
                    result.outlines = studio.subjectOutlines.count
                    result.segmentation = studio.outlineNotice
                    result.checks["分割有受控轮廓或明确降级说明"] = !studio.subjectOutlines.isEmpty || !studio.outlineNotice.isEmpty
                    for style in PhotographyStyle.allCases {
                        studio.photographyStyle = style; studio.analyzePhoto()
                        try await settle(studio)
                        guard let analysis = studio.photoAnalysis, studio.error == nil else { throw CompositionError.invalidPlan }
                        result.checks["知识推荐-\(style.rawValue)"] = (1...3).contains(analysis.plans.count) && analysis.plans.allSatisfy { $0.design?.style == style && $0.subject.isValid }
                        try JSONEncoder().encode(analysis).write(to: output.appendingPathComponent("\(sample.file)-\(style.rawValue).json"))
                    }
                    result.checks["四轮推荐独立保存"] = studio.recommendationBatches.count == 4
                    studio.renameProject("公开照片回归-\(sample.file)")
                    for style in ColorStyle.allCases {
                        studio.style = style; studio.amount = 0.8; studio.updateEdit()
                        let exported = try studio.exportData(original: false)
                        let decoded = try PhotoProcessor.load(exported)
                        let source = CGImageSourceCreateWithData(exported as CFData, nil)!
                        let metadata = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
                        result.checks["编辑导出-\(style.rawValue)"] = decoded.width == image.width && decoded.height == image.height && metadata?[kCGImagePropertyGPSDictionary] == nil
                    }
                    result.checks["编辑后原片逐字节一致"] = try studio.exportData(original: true) == bytes
                    #if targetEnvironment(simulator)
                    // 权限由模拟器测试脚本预置；不在无人值守时等待系统弹窗。
                    if sample.file == samples.first?.file {
                        let permission = PHPhotoLibrary.authorizationStatus(for: .addOnly)
                        if permission == .authorized || permission == .limited || permission == .denied {
                            for original in [true, false] {
                                studio.saveToPhotos(original: original)
                                for _ in 0..<200 where studio.savingPhoto { try await Task.sleep(for: .milliseconds(50)) }
                                result.checks["系统相册保存-原片\(original)-权限\(permission.rawValue)"] = !studio.savingPhoto && (permission == .denied ? studio.error?.contains("权限") == true : studio.error == nil && studio.notice.contains("已保存到相册"))
                                studio.error = nil
                            }
                        }
                    }
                    #endif
                    let gallery = try await studio.galleryPhoto(photoID, original: true)
                    result.checks["画廊独立读取不改变选中照片"] = gallery.data == bytes && studio.currentProject?.activePhotoID == photoID
                    await studio.importPhotoData(Data([0,1,2]))
                    result.checks["损坏输入不覆盖照片或推荐"] = studio.error != nil && studio.originalData == bytes && studio.recommendationBatches.count == 4
                    studio.error = nil
                    guard let plan = studio.photoAnalysis?.plans.first else { throw CompositionError.invalidPlan }
                    studio.startCamera(plan: plan); try await settle(studio)
                    for zoom in [0.5, 1, 2] {
                        studio.chooseZoom(zoom); try await settle(studio)
                        result.checks["替身倍率切换保留模板-\(zoom)"] = studio.selected == plan && studio.guideOutline == plan.design?.outline
                    }
                    studio.capture(); try await settle(studio)
                    result.checks["替身跟拍拍摄保留来源快照"] = studio.currentProject?.photos.count == 2 && studio.followedPlan == plan && studio.originalData == bytes
                    await studio.selectProjectPhoto(photoID); try await settle(studio)
                    await studio.waitForProjectSave()
                    let reopened = StudioModel(loadCredentials: false, enableSegmentation: false, projectStore: library)
                    await reopened.openProject(projectID)
                    result.checks["历史恢复原片标题编辑与四轮推荐"] = reopened.originalData == bytes && reopened.recommendationBatches.count == 4 && reopened.style == .film && reopened.projectTitle == "公开照片回归-\(sample.file)"
                    #if targetEnvironment(simulator) || os(macOS)
                    studio.references.enabled = true
                    studio.generateReference(plan)
                    for _ in 0..<200 where studio.references.jobs.isEmpty || studio.references.jobs.contains(where: \.isActive) { try await Task.sleep(for: .milliseconds(50)) }
                    result.checks["无本机生图能力时明确失败且保留模板"] = studio.references.jobs.last?.state == .failed && studio.photoAnalysis?.plans.contains(plan) == true
                    #endif
                    studio.cancel()
                } catch { result.error = error.localizedDescription }
                report.samples.append(result); save()
            }
            report.completed = true; report.passed = report.samples.allSatisfy(\.passed)
        } catch { report.error = error.localizedDescription }
        save(); return report
    }
    private static func fixtureResponse(_ sample: Sample) throws -> Data {
        var scene = SceneEvidence(); scene.subjectKind = sample.kind; scene.shape = sample.shape
        scene.hasTable = sample.hasTable; scene.lighting = sample.lighting; scene.background = .busy
        if sample.kind == .landscape { scene.horizonY = 0.4 }
        let text = "固定场景夹具，仅检验软件流程，不是模型识别结果。"
        let object: [String: Any] = ["subjectName": "公开样图夹具", "summary": text, "nextStep": text, "limitations": text,
            "detectedSubject": ["x":0.2,"y":0.1,"width":0.6,"height":0.8],
            "scene": try JSONSerialization.jsonObject(with: JSONEncoder().encode(scene)),
            "observations": Dictionary(uniqueKeysWithValues: ["light","composition","background","pose","quality"].map { ($0,text) }),
            "plans": [["id":"fixture","title":"固定场景夹具","instruction":text,"reason":text,"zoom":1,"subject":["x":0.2,"y":0.1,"width":0.6,"height":0.8]]]]
        let content = String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
        return try JSONSerialization.data(withJSONObject: ["choices":[["message":["content":content]]]])
    }
}
#endif
