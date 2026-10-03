import Foundation

/// 知识检索 + 有界候选搜索。内部代价仅用于规则排序，不是审美分数或模型置信度。
public enum RecommendationEngine {
    private struct Candidate {
        let card: PhotographyTechnique
        let box: SubjectBox
        let viewpoint: CameraViewpoint?
        let zoom: Double
        let priority: Int
    }
    public static func recommend(report: PhotoAnalysis, context: AnalysisContext, outline: SubjectOutline?, availableZooms: [Double], capturedZoom: Double) throws -> PhotoAnalysis {
        try PhotographyKnowledge.validate()
        guard context.sourceAspect.isFinite, context.sourceAspect > 0,
              context.sourceAspect <= 20, capturedZoom.isFinite, capturedZoom > 0,
              context.selectedBounds.map(\.isValid) ?? true else { throw CompositionError.invalidPlan }
        let zooms = availableZooms.filter { $0.isFinite && $0 > 0 }.sorted()
        guard !zooms.isEmpty else { throw CompositionError.invalidPlan }
        try report.scene?.validate()
        let evidence = report.scene ?? SceneEvidence()
        let group = evidence.subjectCount > 1
        let observed = group ? nil : outline
        let detected = (group ? report.detectedSubject : (context.selectedBounds ?? observed?.bounds ?? report.detectedSubject))
        let inputAspect = observed?.sourceAspect ?? context.sourceAspect
        let physicalAspect = detected.map { $0.width * inputAspect / $0.height } ?? 0.7
        let lens = zooms.min { abs($0-1) < abs($1-1) }!
        var cards = PhotographyKnowledge.cards.filter { eligible($0.id, scene:evidence) }
        if report.scene == nil || evidence.subjectKind == .unknown || evidence.subjectCount == 0 || detected == nil {
            cards = PhotographyKnowledge.cards.filter { $0.id == "center" }
        }
        if group { cards = PhotographyKnowledge.cards.filter { ["group","environment"].contains($0.id) } }
        var candidates: [Candidate] = []
        for card in cards {
            let viewpoint: CameraViewpoint? = card.id == "tabletop" ? .overhead : (card.id == "volume" ? .high : evidence.viewpoint.camera)
            let changedAngle = card.id == "tabletop" || card.id == "volume"
            let preferredZoom = card.id == "isolate" && evidence.lighting != .low && !group ? 2.0 : lens
            let zoom = zooms.min { abs($0-preferredZoom) < abs($1-preferredZoom) }!
            let ratio = changedAngle ? (card.id == "tabletop" ? 1.0 : min(1.2,max(0.35,physicalAspect))) : physicalAspect
            let target = search(cardID:card.id, scene:evidence, ratio:ratio, observed:detected)
            let priority = (card.styles.contains(context.style) ? 100 : 0) + relevance(card.id, scene:evidence)
            candidates.append(.init(card:card,box:target,viewpoint:viewpoint,zoom:zoom,priority:priority))
        }
        candidates.sort { $0.priority == $1.priority ? $0.card.id < $1.card.id : $0.priority > $1.priority }
        var plans: [ShotPlan] = []
        for candidate in candidates {
            // 同角度且中心/尺寸相近的候选不重复占卡片。
            if plans.contains(where: { $0.viewpoint == candidate.viewpoint && boxDistance($0.subject,candidate.box) < 0.16 }) { continue }
            let changed = ["tabletop","volume"].contains(candidate.card.id)
            let designed = changed ? try geometry(shape:evidence.shape,box:candidate.box,overhead:candidate.card.id == "tabletop") : nil
            let placed = !changed && report.scene != nil && evidence.subjectCount > 0 && !group ? try observed?.simplifiedForTemplate().placed(in:candidate.box,canvasAspect:0.75) : nil
            let targetOutline = designed ?? placed
            let kind: TemplateKind = designed != nil ? .geometricDesign : (placed != nil ? .observedPlacement : .framingOnly)
            let box = targetOutline?.bounds ?? candidate.box
            var warnings = [candidate.card.caution, "场景标签来自模型观察；请核对主体与现场条件。"]
            if report.scene == nil { warnings.append("缺少结构化场景观察，当前仅给出保守取景范围；重新分析可获取知识推荐。") }
            if evidence.subjectCount == 0 { warnings.append("模型未确认主体，请先核对主体选择；当前范围不是检测结果。") }
            if detected == nil { warnings.append("缺少可靠主体范围；只提供粗略框，请先核对或选择主体。") }
            if group { warnings.append("多人以整体目标框表示，不采用单个实例轮廓。") }
            if evidence.viewpoint == .unknown { warnings.append("原片机位未知，同视角方案请保持当前高度和方向。") }
            if evidence.lighting == .low { warnings.append("观察到低光，优先接近 1× 的可用倍率并稳住手机。") }
            let steps = actions(candidate:candidate, box:box, observed:detected, sourceAspect:inputAspect, capturedZoom:capturedZoom, scene:evidence)
            let design = CompositionDesign(techniqueID:candidate.card.id, style:context.style, kind:kind, outline:targetOutline,
                steps:steps, warnings:warnings, horizonY:candidate.card.id == "horizon" ? 1.0/3 : nil)
            try design.validate()
            let reason = "\(context.style.title)：\(candidate.card.principle)"
            let plan = ShotPlan(id:"knowledge-\(candidate.card.id)", title:candidate.card.title,
                instruction:steps.prefix(3).joined(separator:"；"), reason:reason, zoom:candidate.zoom,
                subject:box, viewpoint:candidate.viewpoint, design:design)
            plans.append(plan)
            if plans.count == 3 { break }
        }
        guard let first = plans.first else { throw CompositionError.invalidPlan }
        var result = report; result.plans = plans
        result.nextStep = first.design?.steps.first ?? first.instruction
        var encoded = try JSONEncoder().encode(result)
        // 长观察与轮廓一起保存时优先保留前面的方案，不突破历史合约上限。
        while encoded.count > 32_768 && result.plans.count > 1 {
            result.plans.removeLast()
            encoded = try JSONEncoder().encode(result)
        }
        return try PhotoAnalysisCodec.decode(String(decoding:encoded,as:UTF8.self), availableZooms:zooms)
    }

    private static func eligible(_ id: String, scene: SceneEvidence) -> Bool {
        switch id {
        case "gaze-space": return [.person,.animal].contains(scene.subjectKind) && [.left,.right].contains(scene.facing)
        case "tabletop": return scene.hasTable && [.food,.product].contains(scene.subjectKind) && scene.shape == .flat && scene.viewpoint != .overhead
        case "volume": return scene.hasTable && scene.subjectKind == .product && [.cylinder,.box].contains(scene.shape) && scene.viewpoint != .high
        case "group": return scene.subjectCount > 1
        case "horizon": return scene.subjectKind == .landscape && scene.horizonY >= 0
        case "isolate": return scene.background == .busy && ![.landscape,.architecture].contains(scene.subjectKind)
        default: return true
        }
    }
    private static func relevance(_ id: String, scene: SceneEvidence) -> Int {
        switch id {
        case "gaze-space": return 55
        case "group": return 70
        case "volume", "tabletop": return 45
        case "isolate": return 35
        case "horizon": return 40
        case "center": return scene.subjectKind == .product || scene.subjectKind == .architecture ? 20 : 0
        default: return 10
        }
    }
    private static func search(cardID: String, scene: SceneEvidence, ratio: Double, observed: SubjectBox?) -> SubjectBox {
        let idealHeight: Double
        switch cardID {
        case "environment", "horizon": idealHeight = 0.44
        case "negative-space": idealHeight = 0.48
        case "isolate": idealHeight = 0.80
        case "group": idealHeight = 0.64
        default: idealHeight = 0.68
        }
        let side: Double = scene.facing == .left ? 0.66 : 0.34
        let idealX = ["gaze-space","thirds","negative-space","environment"].contains(cardID) ? side : 0.5
        let idealY = cardID == "environment" ? 0.58 : 0.5
        var best = SubjectBox(x:0.2,y:0.15,width:0.6,height:0.7)
        var bestCost = Double.infinity
        // 125 个有界参数候选，随后取代价最小者；并不将输出吸附九宫格。
        for dh in [-0.12,-0.06,0,0.06,0.12] {
            let rawH = min(0.88,max(0.24,idealHeight+dh))
            let rawW = rawH * max(0.08,min(10,ratio)) / 0.75
            let factor = min(1,0.88 / rawW)
            let w = rawW * factor, h = rawH * factor
            for dx in [-0.12,-0.06,0,0.06,0.12] {
                for dy in [-0.08,-0.04,0,0.04,0.08] {
                    let cx = min(0.94-w/2,max(0.06+w/2,idealX+dx))
                    let cy = min(0.94-h/2,max(0.06+h/2,idealY+dy))
                    let box = SubjectBox(x:cx-w/2,y:cy-h/2,width:w,height:h)
                    guard box.isValid else { continue }
                    var cost = 4*pow(cx-idealX,2) + 3*pow(cy-idealY,2) + 2*pow(h-idealHeight,2)
                    if cardID == "gaze-space" {
                        cost += scene.facing == .right ? max(0,cx-0.46)*10 : max(0,0.54-cx)*10
                    }
                    if let observed {
                        // 假设同一平面重取景，估计杂物留在画内的面积；新视角不沿用此估计。
                        if !["tabletop","volume"].contains(cardID) {
                            for obstacle in scene.distractions {
                                let projected = SubjectBox(x:box.x+(obstacle.x-observed.x)*w/observed.width,
                                    y:box.y+(obstacle.y-observed.y)*h/observed.height,
                                    width:obstacle.width*w/observed.width,height:obstacle.height*h/observed.height)
                                cost += visibleArea(projected) * (cardID == "negative-space" || cardID == "isolate" ? 4 : 1)
                            }
                        }
                        // 大改构图需更大现场动作，轻微惩罚，不推断实际距离。
                        cost += 0.08 * (abs(cx-observed.x-observed.width/2) + abs(cy-observed.y-observed.height/2))
                    }
                    if cost < bestCost { bestCost = cost; best = box }
                }
            }
        }
        return best
    }
    private static func visibleArea(_ box: SubjectBox) -> Double {
        max(0,min(1,box.x+box.width)-max(0,box.x)) * max(0,min(1,box.y+box.height)-max(0,box.y))
    }
    private static func boxDistance(_ a: SubjectBox, _ b: SubjectBox) -> Double {
        abs(a.x+a.width/2-b.x-b.width/2) + abs(a.y+a.height/2-b.y-b.height/2) + abs(a.width-b.width) + abs(a.height-b.height)
    }
    private static func actions(candidate: Candidate, box: SubjectBox, observed: SubjectBox?, sourceAspect: Double, capturedZoom: Double, scene: SceneEvidence) -> [String] {
        var steps: [String] = []
        let changed = ["volume","tabletop"].contains(candidate.card.id)
        if candidate.card.id == "tabletop" { steps.append("在能站稳的位置从桌面正上方取景，保持手机与桌面平行") }
        else if candidate.card.id == "volume" { steps.append("在能站稳的位置稍微抬高机位，保留侧面并看到一点顶面") }
        else { steps.append("保持当前拍摄方向，先检查主体后方是否有杂物或线条") }
        steps.append("使用 \(candidate.zoom.formatted())×，让主体中心落在画面\(box.x+box.width/2 < 0.44 ? "偏左" : (box.x+box.width/2 > 0.56 ? "偏右" : "中央"))的目标范围")
        if !changed, let observed {
            let targetArea = box.width * box.height
            // 将倍率的面积影响计入；只输出相对动作，不虚构半步、米数。
            let cropArea = min(1,0.75/sourceAspect) * min(1,sourceAspect/0.75)
            let relativeArea = targetArea / (observed.width * observed.height / cropArea * pow(candidate.zoom/capturedZoom,2))
            if relativeArea > 1.25 { steps.append("切换倍率后缓慢靠近，直到主体接近目标大小；保留完整边缘") }
            else if relativeArea < 0.80 { steps.append("切换倍率后缓慢后退，直到主体接近目标大小；留意身后空间") }
            else { steps.append("先保持距离，再根据取景微调，保留完整主体") }
        } else { steps.append("机位调整后重新对照大小和留白，不按示意轮廓猜测实际距离") }
        if candidate.card.id == "gaze-space" { steps.append("在主体视线朝向的一侧保留更多空间，不必强行改变姿态") }
        if candidate.card.id == "horizon" { steps.append("对照水平参考线，优先保留更多地面；若天空更重要可重新选择构图") }
        if scene.lighting == .hard || scene.lighting == .backlit { steps.append("拍前查看主体亮部与阴影；有条件再换到更均匀的现有光线下") }
        return steps
    }
    private static func geometry(shape: SubjectShape, box: SubjectBox, overhead: Bool) throws -> SubjectOutline? {
        let local: [OutlinePoint]
        if overhead && shape == .flat {
            local = (0..<40).map { index in
                let angle = Double(index)/40 * 2 * Double.pi
                return .init(x:0.5+0.5*cos(angle),y:0.5+0.5*sin(angle))
            }
        } else if shape == .cylinder {
            // 类别体块：顶面椭圆 + 筒身。不推测真实瓶颈或标签。
            local = (0...16).map { index in
                let a = Double.pi + Double(index)/16 * Double.pi
                return .init(x:0.5+0.5*cos(a),y:0.13+0.13*sin(a))
            } + [.init(x:1,y:0.9),.init(x:0.85,y:1),.init(x:0.15,y:1),.init(x:0,y:0.9)]
        } else if shape == .box {
            local = [.init(x:0,y:0.18),.init(x:0.35,y:0),.init(x:1,y:0.14),.init(x:1,y:0.85),.init(x:0.66,y:1),.init(x:0,y:0.80)]
        } else { return nil }
        return try SubjectOutline(id:0,paths:[local.map { .init(x:box.x+$0.x*box.width,y:box.y+$0.y*box.height) }],sourceAspect:0.75)
    }
}
