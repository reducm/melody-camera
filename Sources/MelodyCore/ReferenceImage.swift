import Foundation

public enum ReferenceResolution: String, Codable, CaseIterable, Sendable {
    case square512, portrait512, landscape512, square768
    public var width: Int { self == .landscape512 || self == .square768 ? 768 : 512 }
    public var height: Int { self == .portrait512 || self == .square768 ? 768 : 512 }
    public var title: String {
        switch self {
        case .square512: return "512 × 512 · 方形（默认）"
        case .portrait512: return "512 × 768 · 竖图"
        case .landscape512: return "768 × 512 · 横图"
        case .square768: return "768 × 768 · 方形"
        }
    }
}

public struct ReferenceImageRequest: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let projectID: UUID
    public let photoID: UUID
    public let batchID: UUID
    public let plan: ShotPlan
    public var resolution: ReferenceResolution?
    public init(projectID:UUID,photoID:UUID,batchID:UUID,plan:ShotPlan) {
        id = UUID(); self.projectID = projectID; self.photoID = photoID; self.batchID = batchID; self.plan = plan
    }
    public func validated() throws -> Self {
        struct Envelope:Encodable { let plans:[ShotPlan] }
        let data=try JSONEncoder().encode(Envelope(plans:[plan]))
        _ = try PlanCodec.decode(String(decoding:data,as:UTF8.self),availableZooms:[plan.zoom])
        return self
    }
    public var prompt: String {
        """
        基于输入照片生成一张摄影构图参考图。保持同一个主体的身份、外形、颜色和材质，不添加物体，不添加文字或描边。只改变推荐中需要改变的机位、主体位置和留白。原图是身份参考，不要仅复刻原来的构图。
        严格保持原图物体清单：禁止新增原图中不存在的人、摄影者、相机、镜头、线缆或配件。无线物体必须保持无线。下面“摄影者、坐姿、端起相机、移动”等词仅描述画面外操作者怎样调整观察视点，绝对不要把这些人或设备生成到图中。保持原有背景中的物体，不用新场景替换背景。
        拍摄目标：\(plan.title)
        具体动作：\(plan.instruction)
        摄影理由：\(plan.reason)
        机位：\(plan.viewpoint?.title ?? "按具体动作调整")
        主体在画面的目标范围（左上原点，0至1）：x=\(plan.subject.x), y=\(plan.subject.y), width=\(plan.subject.width), height=\(plan.subject.height)。不在成图写这些数值。
        \(designPrompt)
        这是低分辨率的视觉参考草稿，不是真实拍摄或三维重建。
        """
    }
    private var designPrompt: String {
        guard let design = plan.design else { return "" }
        let card = PhotographyKnowledge.card(design.techniqueID)
        return "风格：\(design.style.title)。摄影依据：\(card?.principle ?? plan.reason)。前提：\(card?.caution ?? "核对现场条件")。\n构图参数属于竖向3:4取景。若输出画幅不同，将完整构图放在成图正中央的3:4区域内，裁到该区域后主体必须完整且符合目标范围。不要改变人物身份和姿态，不新增未见的光源或道具。\n轮廓来源：\(design.kind.title)。类别几何仅表达体块，细节沿用输入照片，不照着粗体块改变真实物体形状。"
    }
}
public enum ReferenceState: String, Codable, Sendable { case queued, running, ready, failed, cancelled }
public struct ReferenceRemoteStatus: Codable, Sendable {
    public let id: UUID
    public let state: ReferenceState
    public let progress: Double?
    public let stage: String?
    public init(id:UUID,state:ReferenceState,progress:Double? = nil,stage:String? = nil) { self.id=id; self.state=state; self.progress=progress; self.stage=stage }
    public func validated(for expected:UUID) throws -> Self {
        guard id == expected, progress.map({ $0.isFinite && (0...1).contains($0) }) ?? true,
              (stage?.count ?? 0) <= 160 else { throw ReferenceFailure.invalidResponse }
        return self
    }
}
public struct ReferenceJob: Codable, Identifiable, Sendable {
    public var id: UUID { request.id }
    public let request: ReferenceImageRequest
    public let createdAt: Date
    public let provider: String
    public var state: ReferenceState
    public var progress: Double?
    public var message: String
    public var design: ReferenceDesign?
    public init(request:ReferenceImageRequest,provider:String) {
        self.request=request; self.provider=provider; createdAt=Date(); state = .queued; message="等待生成参考图"; progress=nil
    }
    public var isActive: Bool { state == .queued || state == .running }
}
public protocol ReferenceImageGenerating: Sendable {
    func generate(_ request:ReferenceImageRequest,jpeg:Data,progress:@escaping @Sendable (ReferenceRemoteStatus) async -> Void) async throws -> Data
}
public enum ReferenceFailure: LocalizedError {
    case configuration, invalidResponse, failed, cancelled, expired
    public var errorDescription: String? {
        switch self {
        case .configuration: return "请先配置参考图生成服务的地址和连接密钥。"
        case .invalidResponse: return "参考图服务返回的数据不完整，请重试。"
        case .failed: return "参考图生成失败，原有模板仍可使用。请确认手机模型已就绪。"
        case .cancelled: return "参考图生成已取消。"
        case .expired: return "参考图等待超时，可以稍后重试；原有模板仍可使用。"
        }
    }
}
