import Foundation

public enum PhotographyStyle: String, Codable, CaseIterable, Sendable {
    case natural, environmental, minimal, product
    public var title: String {
        switch self {
        case .natural: return "自然纪实"
        case .environmental: return "环境叙事"
        case .minimal: return "简洁留白"
        case .product: return "主体质感"
        }
    }
}
public enum SubjectKind: String, Codable, CaseIterable, Sendable { case person, animal, product, food, architecture, landscape, unknown }
public enum SubjectShape: String, Codable, CaseIterable, Sendable { case cylinder, box, flat, organic, unknown }
public enum FacingDirection: String, Codable, CaseIterable, Sendable { case left, right, front, unknown }
public enum SceneBackground: String, Codable, CaseIterable, Sendable { case simple, busy, unknown }
public enum SceneLighting: String, Codable, CaseIterable, Sendable { case soft, hard, backlit, low, unknown }
public enum ObservedViewpoint: String, Codable, CaseIterable, Sendable {
    case eyeLevel, low, high, overhead, left45, right45, unknown
    public var camera: CameraViewpoint? { CameraViewpoint(rawValue: rawValue) }
}

/// 模型观察，不是测量值；unknown 与缺失不能解释成“没有问题”。
public struct SceneEvidence: Codable, Equatable, Sendable {
    public var subjectKind: SubjectKind = .unknown
    public var shape: SubjectShape = .unknown
    public var subjectCount: Int = 1
    public var facing: FacingDirection = .unknown
    public var background: SceneBackground = .unknown
    public var lighting: SceneLighting = .unknown
    public var viewpoint: ObservedViewpoint = .unknown
    public var hasTable = false
    /// -1 表示无法可靠判断地平线。
    public var horizonY: Double = -1
    public var distractions: [SubjectBox] = []
    public init() {}
    public func validate() throws {
        guard (0...20).contains(subjectCount), horizonY.isFinite,
              horizonY == -1 || (0...1).contains(horizonY),
              distractions.count <= 8, distractions.allSatisfy(\.isValid) else { throw CompositionError.invalidPlan }
    }
}

public struct AnalysisContext: Sendable {
    public var style: PhotographyStyle
    public var selectedBounds: SubjectBox?
    public var sourceAspect: Double
    public init(style: PhotographyStyle = .natural, selectedBounds: SubjectBox? = nil, sourceAspect: Double = 0.75) {
        self.style = style; self.selectedBounds = selectedBounds; self.sourceAspect = sourceAspect
    }
    public var prompt: String {
        var text = "用户希望的拍摄风格：\(style.title)。scene 只写观察，不要为了迎合风格而编造场景。"
        if let box = selectedBounds, box.isValid {
            text += " 用户在原图中选定的主体范围：x=\(box.x),y=\(box.y),width=\(box.width),height=\(box.height)。重点分析这个范围内的主体，周围只作背景；此框来自分割候选，若不对应可靠主体请说明。"
        }
        return text
    }
}

public struct TechniqueSource: Equatable, Sendable {
    public let title: String
    public let url: String
}
public struct PhotographyTechnique: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let principle: String
    public let caution: String
    public let styles: [PhotographyStyle]
    public let sources: [TechniqueSource]
}

/// 自写的可执行知识卡；外部文章仅作出处，不复制全文、示例图或训练数据。
public enum PhotographyKnowledge {
    public static let version = "2026-10-03.1"
    private static let composition = TechniqueSource(title: "Nikon：构图指导", url: "https://www.nikonusa.com/learn-and-explore/c/tips-and-techniques/5-easy-composition-guidelines")
    private static let portraits = TechniqueSource(title: "Nikon：人像与背景", url: "https://www.nikonusa.com/learn-and-explore/c/tips-and-techniques/take-better-portraits")
    private static let depth = TechniqueSource(title: "Nikon：摄影中的层次", url: "https://www.nikonusa.com/learn-and-explore/c/ideas-and-inspiration/the-composition-triangle")
    private static let food = TechniqueSource(title: "Nikon：自然光食物摄影", url: "https://www.nikonusa.com/learn-and-explore/c/tips-and-techniques/create-your-light-food-photography-at-home")
    private static let adobe = TechniqueSource(title: "Adobe：摄影构图基础", url: "https://www.adobe.com/creativecloud/photography/technique/composition.html")
    public static let cards: [PhotographyTechnique] = [
        .init(id:"gaze-space", title:"给视线留空间", principle:"在人物或动物朝向的一侧保留更多空间，使观看方向自然延伸。", caution:"朝向不明确时不强行指定左右；不要求主体改变表情。", styles:[.natural,.environmental], sources:[composition]),
        .init(id:"thirds", title:"错开中心", principle:"让主体与画面空白形成不对称关系，避免所有元素挤在中心。", caution:"三分位置只是候选，主体过宽或多人时优先完整。", styles:[.natural], sources:[composition,adobe]),
        .init(id:"negative-space", title:"简洁留白", principle:"降低主体占比，用连贯的空白突出主体的形状与方向。", caution:"背景复杂时先找简洁背景；不能把未观察区域认定为空白。", styles:[.minimal], sources:[adobe]),
        .init(id:"environment", title:"保留环境关系", principle:"同时保留主体和有意义的场景，让背景说明拍摄地点与情境。", caution:"减少主体比例后仍应清楚；不要求凭空增加前景或场景。", styles:[.environmental], sources:[depth]),
        .init(id:"isolate", title:"减少背景干扰", principle:"适度收紧取景，避免高对比杂物或线条争夺注意力。", caution:"不要为填满画面切断主体；接近主体可能改变透视。", styles:[.natural,.product], sources:[portraits]),
        .init(id:"center", title:"稳定呈现主体", principle:"以居中和均衡边距突出主体形态，便于观察商品或建筑。", caution:"居中不是质量保证；仍需检查背景和垂直线。", styles:[.product], sources:[adobe]),
        .init(id:"tabletop", title:"桌面俯拍", principle:"从上方组织平面食物或物件的形状，利用桌面统一背景。", caution:"仅在桌面和可俯拍的平面主体均有依据时提供；站稳并避免遮光。", styles:[.product,.minimal], sources:[food]),
        .init(id:"volume", title:"较高机位看体积", principle:"对简单立体物件保留侧面并看到部分顶面，表达体积关系。", caution:"只提供类别几何示意，不预测商标、背面或真实尺寸；需现场可移动。", styles:[.product], sources:[depth]),
        .init(id:"group", title:"完整保留多人", principle:"将多人作为整体留出边距，优先保留每个人的头部与肢体。", caution:"单个分割实例不等于整组；不能用一个人的轮廓代表其他人。", styles:[.natural,.environmental], sources:[portraits]),
        .init(id:"horizon", title:"安排地平线", principle:"为天空或地面选择明确的主次，保持可见地平线水平。", caution:"仅对可靠观察到的地平线启用；反射和对称场景可以保留居中。", styles:[.environmental,.minimal], sources:[composition])
    ]
    public static func card(_ id: String) -> PhotographyTechnique? { cards.first { $0.id == id } }
    public static func validate() throws {
        guard Set(cards.map(\.id)).count == cards.count,
              cards.allSatisfy({ !$0.principle.isEmpty && !$0.caution.isEmpty && !$0.sources.isEmpty && $0.sources.allSatisfy { URL(string:$0.url)?.scheme == "https" } }) else { throw CompositionError.invalidPlan }
    }
}
