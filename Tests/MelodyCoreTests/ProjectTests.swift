import Foundation
import Testing
@testable import MelodyCore

@Test func projectRetakesKeepPhotosAndRecommendations() throws {
    var project = ShootingProject()
    let first = ProjectPhoto(origin:"camera", zoom:1, availableZooms:[1,2])
    project.append(first)
    let report = try PhotoAnalysisCodec.decode(projectReportFixture, availableZooms:[1,2])
    project.addRecommendation(report, source:"测试模型")
    project.addRecommendation(report, source:"测试模型第二轮")
    let second = ProjectPhoto(origin:"camera", zoom:1, availableZooms:[1,2])
    project.append(second)
    #expect(project.photos.count == 2)
    #expect(project.activePhotoID == second.id)
    #expect(project.photos[0].recommendations.count == 2)
    #expect(project.photos[1].recommendations.isEmpty)
    project.activePhotoID = first.id
    #expect(project.activePhoto?.recommendations.last?.source == "测试模型第二轮")
}
@Test func libraryRoundTripPreservesOriginalBytesAndEditing() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at:root) }
    let store = ProjectLibrary(root:root)
    var project = ShootingProject()
    var photo = ProjectPhoto(origin:"imported", zoom:1, availableZooms:[1])
    photo.editStyle = "暖调"; photo.editAmount = 0.42
    project.append(photo)
    let bytes = Data([1,2,3,4])
    try await store.save(project, originals:[photo.id:bytes])
    let reopened = try await store.load(project.id)
    #expect(reopened.activePhoto?.editAmount == 0.42)
    #expect(try await store.original(projectID:project.id,photoID:photo.id) == bytes)
    #expect(try await store.list().projects.count == 1)
    // 新建议的保存不得覆盖已保存原片。
    try await store.save(project, originals:[photo.id:Data([9])])
    #expect(try await store.original(projectID:project.id,photoID:photo.id) == bytes)
}
@Test func damagedHistoryDoesNotHideOtherProjects() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at:root) }
    let store = ProjectLibrary(root:root)
    var good = ShootingProject(); let photo = ProjectPhoto(origin:"camera",zoom:1,availableZooms:[1]); good.append(photo)
    try await store.save(good,originals:[photo.id:Data([1])])
    let broken = root.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at:broken,withIntermediateDirectories:true)
    try Data("bad json".utf8).write(to:broken.appendingPathComponent("project.json"))
    let result = try await store.list()
    #expect(result.projects.map(\.id) == [good.id])
    #expect(result.unreadableCount == 1)
}
private let projectReportFixture = """
{"summary":"测试","observations":{"light":"光","composition":"构图","background":"背景","pose":"姿态","quality":"细节"},"nextStep":"下一步","limitations":"测试局限","plans":[{"id":"p1","title":"测试","instruction":"动作","reason":"原因","zoom":1,"subject":{"x":0.1,"y":0.1,"width":0.5,"height":0.5}}]}
"""

@Test func projectSchemaVersionIsExplicitAndFutureVersionsRejected() throws {
    var project = ShootingProject()
    project.append(ProjectPhoto(origin:"camera",zoom:1,availableZooms:[1]))
    #expect(project.schemaVersion == 1)
    project.schemaVersion = 99
    #expect(throws: ProjectFailure.self) { try project.validated() }
}

@Test func automaticProjectTitleFollowsLatestSubject() throws {
    var project = ShootingProject()
    project.append(ProjectPhoto(origin:"camera",zoom:1,availableZooms:[1]))
    for name in ["可乐", "玻璃瓶"] {
        let json = projectReportFixture.replacingOccurrences(of:"\"summary\":",with:"\"subjectName\":\"\(name)\",\"summary\":")
        project.addRecommendation(try PhotoAnalysisCodec.decode(json,availableZooms:[1]),source:"测试")
        #expect(project.title == name)
    }
}

@Test func customTitleAndCaptureOutlineSurvivePersistence() throws {
    var project = ShootingProject()
    let primary = ProjectPhoto(origin:"imported",zoom:1,availableZooms:[1])
    project.append(primary)
    let report = try PhotoAnalysisCodec.decode(projectReportFixture,availableZooms:[1])
    project.addRecommendation(report,source:"测试")
    project.rename("  我的可乐练习  ")
    project.addRecommendation(report,source:"测试")
    let outline = try SubjectOutline(id:1,paths:[[.init(x:0.1,y:0.1),.init(x:0.7,y:0.1),.init(x:0.5,y:0.8)]],sourceAspect:0.75)
    let reference = CaptureReference(photoID:primary.id,batchID:project.activePhoto!.selectedBatch!.id,planID:"p1",outline:outline)
    let capture = ProjectPhoto(origin:"camera",zoom:1,availableZooms:[1],capturedFollowing:reference)
    project.append(capture)
    let reopened = try JSONDecoder().decode(ShootingProject.self,from:JSONEncoder().encode(project))
    #expect(reopened.title == "我的可乐练习" && reopened.titleIsCustom)
    #expect(reopened.activePhoto?.capturedFollowing?.outline == outline)
    #expect(reopened.followedPlan(for:capture) == report.plans[0])
    #expect(reopened.role(of:primary) == "主照片")
    #expect(reopened.role(of:capture) == "模板跟拍")
    var old = try JSONSerialization.jsonObject(with:JSONEncoder().encode(project)) as! [String:Any]
    old.removeValue(forKey:"titleIsCustom")
    #expect(try JSONDecoder().decode(ShootingProject.self,from:JSONSerialization.data(withJSONObject:old)).titleIsCustom == false)
}
@Test func persistedOutlineRejectsInvalidCoordinates() {
    let invalid = Data(#"{"id":1,"paths":[[{"x":2,"y":0},{"x":0,"y":0},{"x":1,"y":1}]],"sourceAspect":0.75}"#.utf8)
    #expect(throws:(any Error).self) { try JSONDecoder().decode(SubjectOutline.self,from:invalid) }
}
