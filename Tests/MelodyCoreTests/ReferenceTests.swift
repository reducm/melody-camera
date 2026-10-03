import Foundation
import Testing
@testable import MelodyCore

@Test func referenceJobRejectsInvalidProgressAndCrossAssociation() throws {
    let request = ReferenceImageRequest(projectID:UUID(),photoID:UUID(),batchID:UUID(),plan:OfflineDirector().plans(scene:.garden,availableZooms:[1])[0])
    #expect(request.prompt.contains(request.plan.instruction))
    #expect(request.prompt.contains("参考"))
    #expect(throws:(any Error).self) { try ReferenceRemoteStatus(id:UUID(),state:.ready,progress:1).validated(for:request.id) }
    #expect(throws:(any Error).self) { try ReferenceRemoteStatus(id:request.id,state:.running,progress:1.2).validated(for:request.id) }
    #expect(try ReferenceRemoteStatus(id:request.id,state:.running,progress:0.5).validated(for:request.id).progress == 0.5)
}

@Test func referenceRequestRejectsCorruptPersistedPlan() throws {
    let bad=ShotPlan(id:"invalid",title:"参考",instruction:"换机位",reason:"构图",zoom:1,subject:SubjectBox(x:-1,y:0,width:1,height:1))
    let request=ReferenceImageRequest(projectID:UUID(),photoID:UUID(),batchID:UUID(),plan:bad)
    #expect(throws:(any Error).self) { try request.validated() }
}
