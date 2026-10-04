import Foundation
import Testing
@testable import MelodyCore

private func sampleReport(_ evidence: SceneEvidence?) throws -> PhotoAnalysis {
    let json = """
    {"subjectName":"测试主体","detectedSubject":{"x":0.4,"y":0.2,"width":0.2,"height":0.6},"summary":"主体在中央。","observations":{"light":"侧光。","composition":"居中。","background":"背景有干扰。","pose":"保持当前姿态。","quality":"缩略图无法测量细节。"},"nextStep":"先观察背景。","limitations":"模型观察需要核对。","plans":[{"id":"old","title":"原建议","instruction":"保持主体完整。","reason":"避免切边。","zoom":1,"subject":{"x":0.2,"y":0.1,"width":0.6,"height":0.8}}]}
    """
    var report = try PhotoAnalysisCodec.decode(json, availableZooms: [1,2])
    report.scene = evidence
    return report
}

@Test func knowledgeIsVersionedAndEveryTechniqueHasReviewedSources() throws {
    try PhotographyKnowledge.validate()
    #expect(PhotographyKnowledge.cards.count >= 8)
    #expect(PhotographyKnowledge.cards.allSatisfy { !$0.sources.isEmpty && !$0.caution.isEmpty })
}

@Test func missingEvidenceUsesExplicitConservativeFallback() throws {
    let report = try RecommendationEngine.recommend(report: sampleReport(nil), context: .init(), outline: nil, availableZooms: [1], capturedZoom: 1)
    #expect(report.plans.count == 1)
    #expect(report.plans[0].design?.kind == .framingOnly)
    #expect(report.plans[0].design?.warnings.contains(where: { $0.contains("结构化") }) == true)
    #expect(report.plans[0].design?.outline == nil)
}

@Test func gazeSpaceIsKeptInFacingDirectionAndLowLightAvoidsTelephoto() throws {
    var scene = SceneEvidence(); scene.subjectKind = .person; scene.facing = .right; scene.lighting = .low
    let report = try RecommendationEngine.recommend(report: sampleReport(scene), context: .init(style: .natural), outline: nil, availableZooms: [1,2], capturedZoom: 1)
    let gaze = try #require(report.plans.first { $0.design?.techniqueID == "gaze-space" })
    #expect(gaze.subject.x + gaze.subject.width / 2 < 0.5)
    #expect(report.plans.allSatisfy { $0.zoom == 1 && $0.subject.isValid })
}

@Test func stylesSelectDifferentTechniquesAndNeverInventLensCapabilities() throws {
    var scene = SceneEvidence(); scene.subjectKind = .product; scene.shape = .cylinder; scene.hasTable = true
    let minimal = try RecommendationEngine.recommend(report: sampleReport(scene), context: .init(style: .minimal), outline: nil, availableZooms: [1], capturedZoom: 1)
    let product = try RecommendationEngine.recommend(report: sampleReport(scene), context: .init(style: .product), outline: nil, availableZooms: [1], capturedZoom: 1)
    #expect(minimal.plans.first?.design?.techniqueID != product.plans.first?.design?.techniqueID)
    #expect(product.plans.allSatisfy { $0.zoom == 1 })
    #expect(Set(product.plans.map(\.id)).count == product.plans.count)
}

@Test func novelObjectViewUsesDesignedGeometryAndPersonNeverGetsBottleOutline() throws {
    var scene = SceneEvidence(); scene.subjectKind = .product; scene.shape = .cylinder; scene.hasTable = true
    let report = try RecommendationEngine.recommend(report: sampleReport(scene), context: .init(style: .product), outline: nil, availableZooms: [1], capturedZoom: 1)
    let designed = try #require(report.plans.first { $0.design?.kind == .geometricDesign })
    #expect(designed.design?.outline != nil)
    #expect(designed.viewpoint != scene.viewpoint.camera)
    scene.subjectKind = .person; scene.shape = .organic
    let person = try RecommendationEngine.recommend(report: sampleReport(scene), context: .init(), outline: nil, availableZooms: [1], capturedZoom: 1)
    #expect(person.plans.allSatisfy { $0.design?.kind != .geometricDesign })
}

@Test func groupSubjectsDoNotAdoptOnePersonsSegmentAsWholeGroup() throws {
    var scene = SceneEvidence(); scene.subjectKind = .person; scene.subjectCount = 3
    let outline = try SubjectOutline(id: 1, paths: [[.init(x:0.4,y:0.2),.init(x:0.6,y:0.2),.init(x:0.6,y:0.8),.init(x:0.4,y:0.8)]], sourceAspect: 0.75)
    let result = try RecommendationEngine.recommend(report: sampleReport(scene), context: .init(), outline: outline, availableZooms: [1], capturedZoom: 1)
    #expect(result.plans.allSatisfy { $0.design?.outline == nil })
}

@Test func evidenceRejectsOutOfBoundsAndUnboundedCollections() {
    var scene = SceneEvidence(); scene.subjectCount = 100
    #expect(throws: (any Error).self) { try scene.validate() }
    scene.subjectCount = 1; scene.horizonY = .nan
    #expect(throws: (any Error).self) { try scene.validate() }
    scene.horizonY = -1; scene.distractions = Array(repeating: .init(x:0,y:0,width:0.1,height:0.1), count:9)
    #expect(throws: (any Error).self) { try scene.validate() }
}

@Test func generatedDesignRequiresAllUserChecksAndBoundJobIdentity() throws {
    let outline = try SubjectOutline(id: 1, paths: [[.init(x:0.3,y:0.2),.init(x:0.7,y:0.2),.init(x:0.7,y:0.8),.init(x:0.3,y:0.8)]], sourceAspect: 1)
    let job = UUID()
    var design = try ReferenceDesign(jobID: job, candidates: [outline])
    #expect(design.approvedOutline == nil)
    #expect(throws: (any Error).self) { try design.approve(candidateID:1, checks: .init(identity:true, composition:false, executable:true), expectedJobID:job) }
    #expect(throws: (any Error).self) { try design.approve(candidateID:1, checks: .init(identity:true, composition:true, executable:true), expectedJobID:UUID()) }
    try design.approve(candidateID:1, checks:.init(identity:true, composition:true, executable:true), expectedJobID:job)
    let approved = try #require(design.approvedOutline)
    #expect(approved.sourceAspect == 0.75)
    #expect(abs(approved.bounds.width - 0.4 / 0.75) < 0.0001)
    let restored = try JSONDecoder().decode(ReferenceDesign.self, from: JSONEncoder().encode(design))
    #expect(restored.approvedOutline == approved)
}

@Test func croppingGeneratedImageMustNotSilentlyCutSubject() throws {
    let wide = try SubjectOutline(id:1, paths:[[.init(x:0.01,y:0.1),.init(x:0.99,y:0.1),.init(x:0.99,y:0.9)]],sourceAspect:1.5)
    let design = try ReferenceDesign(jobID:UUID(), candidates:[wide])
    #expect(design.candidates.isEmpty)
}

@Test func legacyReportRemainsReadableAndDesignedGeometrySurvivesCodec() throws {
    let old = try sampleReport(nil)
    #expect(old.plans[0].design == nil)
    var scene = SceneEvidence(); scene.subjectKind = .product; scene.shape = .cylinder; scene.hasTable = true
    let report = try RecommendationEngine.recommend(report: sampleReport(scene), context:.init(style:.product), outline:nil, availableZooms:[1], capturedZoom:1)
    let restored = try PhotoAnalysisCodec.decode(String(decoding:JSONEncoder().encode(report),as:UTF8.self), availableZooms:[1])
    #expect(restored == report)
}

@Test(arguments:PhotographyStyle.allCases,SubjectKind.allCases)
func recommendationScenarioMatrixHonorsGeometryAndKnowledge(style:PhotographyStyle,kind:SubjectKind) throws {
    var scene = SceneEvidence(); scene.subjectKind = kind; scene.background = .busy
    if kind == .product { scene.shape = .box; scene.hasTable = true }
    if kind == .food { scene.shape = .flat; scene.hasTable = true }
    if kind == .landscape { scene.horizonY = 0.6 }
    let result = try RecommendationEngine.recommend(report:sampleReport(scene),context:.init(style:style),outline:nil,availableZooms:[0.5,1,2],capturedZoom:1)
    #expect((1...3).contains(result.plans.count))
    for plan in result.plans {
        let design = try #require(plan.design)
        #expect(PhotographyKnowledge.card(design.techniqueID) != nil)
        #expect(plan.subject.isValid)
        #expect(plan.instruction.count <= 160)
        try design.validate()
    }
}

@Test func pipelineDoesNotAcceptModelFabricatedApprovalOrKnowledge() throws {
    var scene = SceneEvidence(); scene.subjectKind = .product
    let result = try RecommendationEngine.recommend(report:sampleReport(scene),context:.init(),outline:nil,availableZooms:[1],capturedZoom:1)
    let json = String(decoding:try JSONEncoder().encode(result),as:UTF8.self)
    let modelResponse = try PhotoAnalysisCodec.decode(json,availableZooms:[1],allowLocalDesign:false)
    #expect(modelResponse.plans.allSatisfy { $0.design == nil })
}

@Test func generatedTargetSnapshotSurvivesLaterReferenceChanges() throws {
    var scene = SceneEvidence(); scene.subjectKind = .product
    let report = try RecommendationEngine.recommend(report:sampleReport(scene),context:.init(),outline:nil,availableZooms:[1],capturedZoom:1)
    let outline = try SubjectOutline(id:1,paths:[[.init(x:0.3,y:0.2),.init(x:0.6,y:0.2),.init(x:0.6,y:0.8)]],sourceAspect:1)
    var reference = try ReferenceDesign(jobID:UUID(),candidates:[outline])
    try reference.approve(candidateID:1,checks:.init(identity:true,composition:true,executable:true),expectedJobID:reference.jobID)
    let adopted = try report.plans[0].adopting(reference)
    var project = ShootingProject()
    let original = ProjectPhoto(origin:"imported",zoom:1,availableZooms:[1])
    project.append(original); project.addRecommendation(report,source:"固定场景测试")
    let batch = try #require(project.activePhoto?.selectedBatch)
    let capture = ProjectPhoto(origin:"camera",zoom:1,availableZooms:[1],capturedFollowing:.init(photoID:original.id,batchID:batch.id,planID:adopted.id,outline:adopted.design?.outline,planSnapshot:adopted))
    project.append(capture); reference.revoke()
    let reopened = try JSONDecoder().decode(ShootingProject.self,from:JSONEncoder().encode(project)).validated()
    #expect(reopened.followedPlan(for:capture) == adopted)
    #expect(reopened.activePhoto?.capturedFollowing?.outline == adopted.design?.outline)
}

@Test func longObservationAndContoursRespectHistorySizeBudget() throws {
    var scene = SceneEvidence(); scene.subjectKind = .person; scene.facing = .right; scene.background = .busy
    let seed = try sampleReport(scene)
    var json = try #require(JSONSerialization.jsonObject(with:JSONEncoder().encode(seed)) as? [String:Any])
    let text = String(repeating:"观",count:400)
    for field in ["summary","nextStep","limitations"] { json[field] = text }
    json["observations"] = Dictionary(uniqueKeysWithValues:["light","composition","background","pose","quality"].map { ($0,text) })
    let input = try PhotoAnalysisCodec.decode(String(decoding:JSONSerialization.data(withJSONObject:json),as:UTF8.self),availableZooms:[1,2])
    let points = (0..<48).map { i in OutlinePoint(x:0.5+0.2*cos(Double(i)/48*2*Double.pi),y:0.5+0.3*sin(Double(i)/48*2*Double.pi)) }
    let outline = try SubjectOutline(id:1,paths:[points,points],sourceAspect:0.75)
    let result = try RecommendationEngine.recommend(report:input,context:.init(),outline:outline,availableZooms:[1,2],capturedZoom:1)
    #expect(!result.plans.isEmpty)
    #expect(try JSONEncoder().encode(result).count <= 32_768)
}

@Test func adoptedReferenceGuidanceUsesNewTargetInsteadOfOldPlacement() throws {
    var scene = SceneEvidence(); scene.subjectKind = .person; scene.facing = .right
    let report = try RecommendationEngine.recommend(report:sampleReport(scene),context:.init(),outline:nil,availableZooms:[1],capturedZoom:1)
    let old = try #require(report.plans.first { $0.design?.techniqueID == "gaze-space" })
    #expect(old.instruction.contains("偏左"))
    let right = try SubjectOutline(id:1,paths:[[.init(x:0.65,y:0.2),.init(x:0.85,y:0.2),.init(x:0.85,y:0.8),.init(x:0.65,y:0.8)]],sourceAspect:0.75)
    var reference = try ReferenceDesign(jobID:UUID(),candidates:[right])
    try reference.approve(candidateID:1,checks:.init(identity:true,composition:true,executable:true),expectedJobID:reference.jobID)
    let adopted = try old.adopting(reference)
    #expect(adopted.instruction.contains("偏右"))
    #expect(!adopted.instruction.contains("偏左"))
    #expect(adopted.design?.steps.contains { $0.contains("重新对照") } == true)
}
