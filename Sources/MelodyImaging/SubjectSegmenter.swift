import Foundation
import Vision
import CoreImage
import MelodyCore

public enum SegmentationFailure: Error, LocalizedError {
    case noSubject
    public var errorDescription: String? { "没有分离出可靠主体。请换用主体更清晰、背景更简单的照片；不会用人物示意线替代识别结果。" }
}
public enum SubjectSegmenter {
    public static func outlines(in image: CGImage) throws -> [SubjectOutline] {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: image, orientation: .up)
        try handler.perform([request])
        try Task.checkCancellation()
        guard let observation = request.results?.first else { throw SegmentationFailure.noSubject }
        var results: [SubjectOutline] = []
        for id in observation.allInstances.prefix(6) {
            try Task.checkCancellation()
            let mask = try observation.generateScaledMaskForImage(forInstances: IndexSet(integer: id), from: handler)
            let contours = VNDetectContoursRequest()
            contours.detectsDarkOnLight = false
            contours.maximumImageDimension = 512
            try VNImageRequestHandler(cvPixelBuffer: mask, orientation: .up).perform([contours])
            guard let result = contours.results?.first else { continue }
            let paths: [[OutlinePoint]] = result.topLevelContours.prefix(16).compactMap { contour in
                guard let polygon = try? contour.polygonApproximation(epsilon: 0.003) else { return nil }
                let points = polygon.normalizedPoints
                guard points.count >= 3 else { return nil }
                let step = max(1, Int(ceil(Double(points.count)/512)))
                return stride(from: 0, to: points.count, by: step).map { i in
                    OutlinePoint(x: min(1, max(0, Double(points[i].x))), y: min(1, max(0, 1-Double(points[i].y))))
                }
            }
            if let outline = try? SubjectOutline(id: id, paths: paths, sourceAspect: Double(image.width)/Double(image.height)),
               outline.bounds.width * outline.bounds.height > 0.002 {
                results.append(outline)
            }
        }
        guard !results.isEmpty else { throw SegmentationFailure.noSubject }
        return results.sorted { $0.bounds.width * $0.bounds.height > $1.bounds.width * $1.bounds.height }
    }
}
