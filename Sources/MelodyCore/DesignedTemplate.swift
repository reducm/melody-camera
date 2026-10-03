import Foundation

public enum TemplateKind: String, Codable, Sendable {
    case observedPlacement, geometricDesign, framingOnly, generatedReference
    public var title: String {
        switch self {
        case .observedPlacement: return "原片轮廓 · 同视角构图"
        case .geometricDesign: return "类别几何设计 · 非真实重建"
        case .framingOnly: return "构图范围 · 无可靠新轮廓"
        case .generatedReference: return "生成图设计轮廓 · 用户已核对"
        }
    }
}
public struct CompositionDesign: Codable, Equatable, Sendable {
    public let engineVersion: String
    public let knowledgeVersion: String
    public let techniqueID: String
    public let style: PhotographyStyle
    public let kind: TemplateKind
    public let outline: SubjectOutline?
    public let steps: [String]
    public let warnings: [String]
    public let horizonY: Double?
    public let referenceJobID: UUID?
    public init(techniqueID: String, style: PhotographyStyle, kind: TemplateKind, outline: SubjectOutline?, steps: [String], warnings: [String], horizonY: Double? = nil, referenceJobID: UUID? = nil) {
        engineVersion = "knowledge-planner-v1"; knowledgeVersion = PhotographyKnowledge.version
        self.techniqueID = techniqueID; self.style = style; self.kind = kind; self.outline = outline
        self.steps = steps; self.warnings = warnings; self.horizonY = horizonY; self.referenceJobID = referenceJobID
    }
    public func validate() throws {
        guard engineVersion == "knowledge-planner-v1", knowledgeVersion.count <= 40,
              PhotographyKnowledge.card(techniqueID) != nil,
              (1...6).contains(steps.count), steps.allSatisfy({ !$0.isEmpty && $0.count <= 160 }),
              warnings.count <= 8, warnings.allSatisfy({ !$0.isEmpty && $0.count <= 200 }),
              horizonY.map({ $0.isFinite && (0...1).contains($0) }) ?? true,
              (kind != .framingOnly || outline == nil),
              (kind == .framingOnly || outline != nil),
              (kind != .generatedReference || referenceJobID != nil) else { throw CompositionError.invalidPlan }
        if let outline {
            guard abs(outline.sourceAspect - 0.75) < 0.0001, outline.paths.count <= 2,
                  outline.paths.allSatisfy({ $0.count <= 48 }) else { throw CompositionError.invalidPlan }
        }
    }
}

public extension SubjectOutline {
    func simplifiedForTemplate() throws -> SubjectOutline {
        let compact = paths.prefix(2).map { path in
            let count = min(path.count, 48)
            return (0..<count).map { path[$0 * path.count / count] }
        }
        return try SubjectOutline(id:id, paths:compact, sourceAspect:sourceAspect)
    }
    /// 与参考图“居中填满 3:4”的预览完全相同。切到主体即拒绝，不补造轮廓。
    func centerCroppedForCamera() throws -> SubjectOutline {
        let targetAspect = 0.75
        let width = min(1, targetAspect / sourceAspect), height = min(1, sourceAspect / targetAspect)
        let x = (1-width)/2, y = (1-height)/2
        guard bounds.x >= x, bounds.y >= y, bounds.x+bounds.width <= x+width,
              bounds.y+bounds.height <= y+height else { throw CompositionError.invalidPlan }
        return try SubjectOutline(id:id, paths:paths.map { $0.map { .init(x:($0.x-x)/width,y:($0.y-y)/height) } }, sourceAspect:targetAspect).simplifiedForTemplate()
    }
}

public struct ReferenceReviewChecks: Codable, Equatable, Sendable {
    public let identity: Bool
    public let composition: Bool
    public let executable: Bool
    public init(identity: Bool, composition: Bool, executable: Bool) {
        self.identity = identity; self.composition = composition; self.executable = executable
    }
    public var complete: Bool { identity && composition && executable }
}
public struct ReferenceDesign: Codable, Equatable, Sendable {
    public let jobID: UUID
    public let candidates: [SubjectOutline]
    public private(set) var selectedID: Int?
    public private(set) var checks: ReferenceReviewChecks?
    public private(set) var reviewedAt: Date?
    public init(jobID: UUID, candidates: [SubjectOutline]) throws {
        guard candidates.count <= 6, Set(candidates.map(\.id)).count == candidates.count else { throw CompositionError.invalidPlan }
        self.jobID = jobID
        self.candidates = candidates.compactMap { try? $0.centerCroppedForCamera() }
    }
    public var approvedOutline: SubjectOutline? {
        guard checks?.complete == true, reviewedAt != nil else { return nil }
        return candidates.first { $0.id == selectedID }
    }
    public mutating func approve(candidateID: Int, checks: ReferenceReviewChecks, expectedJobID: UUID) throws {
        guard jobID == expectedJobID, checks.complete, candidates.contains(where: { $0.id == candidateID }) else { throw CompositionError.invalidPlan }
        selectedID = candidateID; self.checks = checks; reviewedAt = Date()
    }
    public mutating func revoke() { selectedID = nil; checks = nil; reviewedAt = nil }
    public func validate(for expectedJobID: UUID) throws {
        guard jobID == expectedJobID, candidates.count <= 6, Set(candidates.map(\.id)).count == candidates.count,
              candidates.allSatisfy({ abs($0.sourceAspect-0.75) < 0.0001 && $0.paths.count <= 2 && $0.paths.allSatisfy { $0.count <= 48 } }),
              selectedID == nil || approvedOutline != nil else { throw CompositionError.invalidPlan }
    }
}

public extension ShotPlan {
    func adopting(_ reference: ReferenceDesign) throws -> ShotPlan {
        try reference.validate(for:reference.jobID)
        guard let outline = reference.approvedOutline, let old = design else { throw CompositionError.invalidPlan }
        let replacement = CompositionDesign(techniqueID:old.techniqueID, style:old.style, kind:.generatedReference,
            outline:outline, steps:old.steps, warnings:old.warnings + ["描边提取自合成参考图；用户核对不等于模型身份或角度验证。"],
            horizonY:nil, referenceJobID:reference.jobID)
        try replacement.validate()
        return ShotPlan(id:id, title:title, instruction:instruction, reason:reason, zoom:zoom, subject:outline.bounds, viewpoint:viewpoint, design:replacement)
    }
}
