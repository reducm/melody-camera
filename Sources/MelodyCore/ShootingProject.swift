import Foundation

public struct RecommendationBatch: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let createdAt: Date
    public let source: String
    public let report: PhotoAnalysis
    public init(report: PhotoAnalysis, source: String) {
        id = UUID(); createdAt = Date(); self.report = report; self.source = source
    }
}
public struct CaptureReference: Codable, Equatable, Sendable {
    public let photoID: UUID
    public let batchID: UUID
    public let outline: SubjectOutline?
    public let planID: String
    public init(photoID: UUID, batchID: UUID, planID: String, outline: SubjectOutline? = nil) { self.outline = outline; self.photoID = photoID; self.batchID = batchID; self.planID = planID }
}
public struct ProjectPhoto: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let createdAt: Date
    public let origin: String
    public let zoom: Double
    public let availableZooms: [Double]
    public var editStyle: String = "自然透亮"
    public var editAmount: Double = 0.6
    public var recommendations: [RecommendationBatch] = []
    public var selectedBatchID: UUID?
    public var selectedOutlineID: Int?
    public var capturedFollowing: CaptureReference?
    public init(origin: String, zoom: Double, availableZooms: [Double], capturedFollowing: CaptureReference? = nil) {
        id = UUID(); createdAt = Date(); self.origin = origin; self.zoom = zoom
        self.availableZooms = availableZooms; self.capturedFollowing = capturedFollowing
    }
    public var selectedBatch: RecommendationBatch? { recommendations.first { $0.id == selectedBatchID } ?? recommendations.last }
}
public struct ShootingProject: Codable, Identifiable, Equatable, Sendable {
    public var schemaVersion = 1
    public let id: UUID
    public let createdAt: Date
    public var updatedAt: Date
    public var titleIsCustom = false
    public var title: String
    public var photos: [ProjectPhoto] = []
    public var activePhotoID: UUID?
    public init() { id = UUID(); createdAt = Date(); updatedAt = createdAt; title = "拍摄项目" }
    private enum CodingKeys: String, CodingKey { case schemaVersion, id, createdAt, updatedAt, title, titleIsCustom, photos, activePhotoID }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy:CodingKeys.self)
        schemaVersion = try values.decodeIfPresent(Int.self,forKey:.schemaVersion) ?? 1
        id = try values.decode(UUID.self,forKey:.id)
        createdAt = try values.decode(Date.self,forKey:.createdAt)
        updatedAt = try values.decode(Date.self,forKey:.updatedAt)
        titleIsCustom = try values.decodeIfPresent(Bool.self,forKey:.titleIsCustom) ?? false
        title = try values.decode(String.self,forKey:.title)
        photos = try values.decode([ProjectPhoto].self,forKey:.photos)
        activePhotoID = try values.decodeIfPresent(UUID.self,forKey:.activePhotoID)
    }
    public var activePhoto: ProjectPhoto? { photos.first { $0.id == activePhotoID } }
    public mutating func append(_ photo: ProjectPhoto) {
        photos.append(photo); activePhotoID = photo.id; updatedAt = Date()
    }
    public mutating func addRecommendation(_ report: PhotoAnalysis, source: String) {
        guard let index = photos.firstIndex(where: { $0.id == activePhotoID }) else { return }
        let batch = RecommendationBatch(report: report, source: source)
        photos[index].recommendations.append(batch); photos[index].selectedBatchID = batch.id
        if !titleIsCustom, let subject = report.subjectName { title = subject }
        updatedAt = Date()
    }
    public mutating func rename(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 100 else { return }
        title = trimmed; titleIsCustom = true; updatedAt = Date()
    }
    public func role(of photo: ProjectPhoto) -> String {
        if photo.id == photos.first?.id { return "主照片" }
        if photo.capturedFollowing != nil { return "模板跟拍" }
        return photo.origin == "imported" ? "相册导入" : "补拍照片"
    }
    public func followedPlan(for photo: ProjectPhoto) -> ShotPlan? {
        guard let ref = photo.capturedFollowing else { return nil }
        return photos.first { $0.id == ref.photoID }?.recommendations.first { $0.id == ref.batchID }?.report.plans.first { $0.id == ref.planID }
    }
    public func validated() throws -> Self {
        guard schemaVersion == 1, !photos.isEmpty, Set(photos.map(\.id)).count == photos.count,
              activePhoto != nil, !title.isEmpty, title.count <= 100 else { throw ProjectFailure.damaged }
        for photo in photos {
            guard ["camera","imported","demo"].contains(photo.origin), photo.zoom.isFinite, photo.zoom > 0,
                  !photo.availableZooms.isEmpty, photo.availableZooms.allSatisfy({ $0.isFinite && $0 > 0 }),
                  photo.editAmount.isFinite, (0...1).contains(photo.editAmount),
                  Set(photo.recommendations.map(\.id)).count == photo.recommendations.count else { throw ProjectFailure.damaged }
            for batch in photo.recommendations {
                let data = try JSONEncoder().encode(batch.report)
                _ = try PhotoAnalysisCodec.decode(String(decoding:data,as:UTF8.self), availableZooms:photo.availableZooms)
            }
        }
        return self
    }
}
public enum ProjectFailure: LocalizedError {
    case damaged, missingOriginal
    public var errorDescription: String? {
        switch self {
        case .damaged: return "这个拍摄项目的记录不完整，其他项目不受影响。"
        case .missingOriginal: return "这张照片的原始文件不可用。"
        }
    }
}
/// 只在应用沙盒保存，文件名由 UUID 生成；原片独立且不可覆盖，元数据原子写入。
public actor ProjectLibrary {
    public let root: URL
    public init(root: URL) { self.root = root }
    private func directory(_ id: UUID) -> URL { root.appendingPathComponent(id.uuidString,isDirectory:true) }
    public func save(_ project: ShootingProject, originals: [UUID:Data] = [:]) throws {
        _ = try project.validated()
        let metadata = try JSONEncoder().encode(project)
        guard metadata.count <= 8_000_000 else { throw ProjectFailure.damaged }
        let folder = directory(project.id)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        for (id, data) in originals where project.photos.contains(where: { $0.id == id }) {
            let file = folder.appendingPathComponent(id.uuidString + ".original")
            if !FileManager.default.fileExists(atPath:file.path) { try data.write(to:file,options:.atomic) }
        }
        for photo in project.photos {
            guard FileManager.default.fileExists(atPath:folder.appendingPathComponent(photo.id.uuidString + ".original").path) else { throw ProjectFailure.missingOriginal }
        }
        try metadata.write(to:folder.appendingPathComponent("project.json"),options:.atomic)
        var localRoot = root
        var attributes = URLResourceValues(); attributes.isExcludedFromBackup = true
        try localRoot.setResourceValues(attributes)
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey:FileProtectionType.completeUntilFirstUserAuthentication],ofItemAtPath:folder.path)
        #endif
    }
    public func load(_ id: UUID) throws -> ShootingProject {
        let file = directory(id).appendingPathComponent("project.json")
        guard (try file.resourceValues(forKeys:[.fileSizeKey])).fileSize ?? 0 <= 8_000_000 else { throw ProjectFailure.damaged }
        let project = try JSONDecoder().decode(ShootingProject.self,from:Data(contentsOf:file))
        guard project.id == id else { throw ProjectFailure.damaged }
        return try project.validated()
    }
    public func original(projectID: UUID, photoID: UUID) throws -> Data {
        let file = directory(projectID).appendingPathComponent(photoID.uuidString + ".original")
        guard FileManager.default.fileExists(atPath:file.path),
              (try file.resourceValues(forKeys:[.fileSizeKey])).fileSize ?? 0 <= 100_000_000 else { throw ProjectFailure.missingOriginal }
        return try Data(contentsOf:file)
    }
    public struct Listing: Sendable { public let projects: [ShootingProject]; public let unreadableCount: Int }
    public func list() throws -> Listing {
        guard FileManager.default.fileExists(atPath:root.path) else { return Listing(projects:[],unreadableCount:0) }
        var projects: [ShootingProject] = []; var unreadable = 0
        for file in try FileManager.default.contentsOfDirectory(at:root,includingPropertiesForKeys:nil) {
            guard let id = UUID(uuidString:file.lastPathComponent) else { continue }
            do { projects.append(try load(id)) } catch { unreadable += 1 }
        }
        return Listing(projects:projects.sorted { $0.updatedAt > $1.updatedAt },unreadableCount:unreadable)
    }
}
