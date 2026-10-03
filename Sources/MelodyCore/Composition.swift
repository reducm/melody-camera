import Foundation

public enum SceneKind: String, Codable, CaseIterable, Sendable {
    case garden = "花园散步", city = "城市街角", cafe = "窗边咖啡"
}
public struct SubjectBox: Codable, Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
    public var isValid: Bool {
        [x, y, width, height].allSatisfy(\.isFinite) && x >= 0 && y >= 0 &&
        width > 0 && height > 0 && x + width <= 1 && y + height <= 1
    }
}
public struct ShotPlan: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let instruction: String
    public let reason: String
    public let zoom: Double
    public let subject: SubjectBox
    public let viewpoint: CameraViewpoint?
    public var design: CompositionDesign?
    public init(id: String, title: String, instruction: String, reason: String, zoom: Double, subject: SubjectBox, viewpoint: CameraViewpoint? = nil, design: CompositionDesign? = nil) {
        self.id = id; self.title = title; self.instruction = instruction; self.reason = reason; self.zoom = zoom; self.subject = subject; self.viewpoint = viewpoint; self.design = design
    }
}
public enum CompositionError: Error, LocalizedError, Equatable {
    case invalidPlan, noFrames, invalidEndpoint, missingCredentials, http(Int), malformedResponse
    public var errorDescription: String? {
        switch self {
        case .invalidPlan: return "模型返回的构图方案不符合要求，请重试或使用离线方案。"
        case .noFrames: return "需要 1–3 张有效取景图，每张不超过 2 MB。"
        case .invalidEndpoint: return "请填写不带账号、查询参数的 HTTPS 接口根地址。"
        case .missingCredentials: return "请先填写模型名称和 API Key。"
        case .http(let status): return "模型服务返回 HTTP \(status)。请检查权限、额度和模型的视觉能力。"
        case .malformedResponse: return "无法读取模型响应，请使用支持图像输入的 Chat Completions 接口。"
        }
    }
}
public struct PlanCodec {
    private struct Envelope: Decodable { let plans: [ShotPlan] }
    public static func decode(_ text: String, availableZooms: [Double]) throws -> [ShotPlan] {
        guard text.utf8.count <= 32_768 else { throw CompositionError.invalidPlan }
        var json = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if json.hasPrefix("```json\n"), json.hasSuffix("```") { json = String(json.dropFirst(8).dropLast(3)) }
        else if json.hasPrefix("```\n"), json.hasSuffix("```") { json = String(json.dropFirst(4).dropLast(3)) }
        let plans: [ShotPlan]
        do { plans = try JSONDecoder().decode(Envelope.self, from: Data(json.utf8)).plans }
        catch { throw CompositionError.malformedResponse }
        func validText(_ text: String, max: Int) -> Bool {
            !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && text.count <= max
        }
        guard (1...3).contains(plans.count), Set(plans.map(\.id)).count == plans.count,
              plans.allSatisfy({ p in
                  validText(p.id, max: 64) && validText(p.title, max: 24) &&
                  validText(p.instruction, max: 160) && validText(p.reason, max: 160) &&
                  p.subject.isValid && p.zoom.isFinite && p.zoom > 0 &&
                  availableZooms.contains(where: { abs($0 - p.zoom) < 0.001 })
              }) else { throw CompositionError.invalidPlan }
        for plan in plans {
            try plan.design?.validate()
            if let outline = plan.design?.outline {
                let b = outline.bounds, s = plan.subject
                guard abs(b.x-s.x) < 0.001, abs(b.y-s.y) < 0.001,
                      abs(b.width-s.width) < 0.001, abs(b.height-s.height) < 0.001 else { throw CompositionError.invalidPlan }
            }
        }
        return plans
    }
}

/// 离线摄影规则：根据用户选择的场景给建议，不声称理解了图像。
public struct OfflineDirector {
    public init() {}
    public func plans(scene: SceneKind, availableZooms: [Double]) -> [ShotPlan] {
        let valid = availableZooms.filter { $0.isFinite && $0 > 0 }
        guard !valid.isEmpty else { return [] }
        func lens(_ preferred: Double) -> Double { valid.min(by: { abs($0-preferred) < abs($1-preferred) })! }
        let reasons: [SceneKind: String] = [.garden: "用树影和小路形成层次，脸部避开斑驳直射光。", .city: "用建筑线条引导视线，注意背景不要穿过头部。", .cafe: "让柔和窗光落在脸侧，避免窗外过亮。"]
        return [
            ShotPlan(id: "thirds", title: "留一点风景", instruction: "人物移到左侧，眼睛看向画面右边；摄影者保持手机竖直。", reason: reasons[scene]!, zoom: lens(1), subject: .init(x: 0.17, y: 0.2, width: 0.32, height: 0.69)),
            ShotPlan(id: "portrait", title: "靠近一点点", instruction: "切换推荐倍率后后退半步，把眼睛放在上三分线附近，肩膀微微侧转。", reason: "适当后退再用较长焦段，让面部透视更自然；弱光时优先主摄。", zoom: lens(2), subject: .init(x: 0.24, y: 0.14, width: 0.52, height: 0.81)),
            ShotPlan(id: "full", title: "走进画面里", instruction: "手机放到腰部附近，保持竖直；脚靠近下边缘，头顶留出呼吸感。", reason: "低一点的机位配合完整四肢，比后期拉伸更自然。", zoom: lens(1), subject: .init(x: 0.39, y: 0.17, width: 0.3, height: 0.77))
        ]
    }
}
