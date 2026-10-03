import Foundation

public struct OutlinePoint: Codable, Equatable, Sendable {
    public let x: Double
    public let y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}
/// 由本地像素分割得到的轮廓，坐标相对已转正照片，左上为原点。
public struct SubjectOutline: Codable, Equatable, Sendable, Identifiable {
    public let id: Int
    public let paths: [[OutlinePoint]]
    public let sourceAspect: Double
    public let bounds: SubjectBox
    public init(id: Int, paths: [[OutlinePoint]], sourceAspect: Double) throws {
        let points = paths.flatMap { $0 }
        guard sourceAspect.isFinite, sourceAspect > 0, (1...16).contains(paths.count),
              paths.allSatisfy({ (3...512).contains($0.count) }),
              points.allSatisfy({ $0.x.isFinite && $0.y.isFinite && (0...1).contains($0.x) && (0...1).contains($0.y) }),
              let x = points.map(\.x).min(), let y = points.map(\.y).min(),
              let maxX = points.map(\.x).max(), let maxY = points.map(\.y).max() else { throw CompositionError.invalidPlan }
        let bounds = SubjectBox(x: x, y: y, width: maxX-x, height: maxY-y)
        guard bounds.isValid else { throw CompositionError.invalidPlan }
        self.id = id; self.paths = paths; self.sourceAspect = sourceAspect; self.bounds = bounds
    }
    private enum CodingKeys: String, CodingKey { case id, paths, sourceAspect }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(id: values.decode(Int.self, forKey: .id),
                      paths: values.decode([[OutlinePoint]].self, forKey: .paths),
                      sourceAspect: values.decode(Double.self, forKey: .sourceAspect))
    }
    /// 等比摆放，不能把平面轮廓拉伸成虚假的新视角。
    public func placed(in target: SubjectBox, canvasAspect: Double) throws -> SubjectOutline {
        guard target.isValid, canvasAspect.isFinite, canvasAspect > 0 else { throw CompositionError.invalidPlan }
        let physicalAspect = bounds.width * sourceAspect / bounds.height
        let width = min(target.width, target.height * physicalAspect / canvasAspect)
        let height = width * canvasAspect / physicalAspect
        let x = target.x + (target.width-width)/2, y = target.y + (target.height-height)/2
        let mapped = paths.map { path in path.map { p in
            OutlinePoint(x: min(1, max(0, x + (p.x-bounds.x)/bounds.width*width)),
                         y: min(1, max(0, y + (p.y-bounds.y)/bounds.height*height)))
        }}
        return try SubjectOutline(id: id, paths: mapped, sourceAspect: canvasAspect)
    }
}
public enum CameraViewpoint: String, Codable, CaseIterable, Sendable {
    case eyeLevel, low, high, overhead, left45, right45
    public var title: String {
        switch self {
        case .eyeLevel: return "平视"; case .low: return "低机位仰拍"; case .high: return "高机位俯拍"
        case .overhead: return "正上方俯拍"; case .left45: return "左前方约45°"; case .right45: return "右前方约45°"
        }
    }
}
