import Foundation

/// 给支持约束解码的 provider 使用；最终仍须通过 PhotoAnalysisCodec 的业务校验。
public enum PhotoAnalysisSchema {
    public static func make(availableZooms: [Double]) -> [String: Any] {
        func text(_ maximum: Int) -> [String: Any] { ["type":"string", "minLength":1, "maxLength":maximum] }
        func object(_ properties: [String: Any]) -> [String: Any] {
            ["type":"object", "properties": properties, "required":properties.keys.sorted(), "additionalProperties":false]
        }
        let fraction: [String:Any] = ["type":"number", "minimum":0, "maximum":1]
        let dimension: [String:Any] = ["type":"number", "exclusiveMinimum":0, "maximum":1]
        let box = object(["x":fraction, "y":fraction, "width":dimension, "height":dimension])
        let plan = object(["id":text(64), "title":text(24), "instruction":text(160), "reason":text(160),
            "zoom":["type":"number", "enum":availableZooms], "subject":box,
            "viewpoint":["type":"string", "enum":CameraViewpoint.allCases.map(\.rawValue)]])
        return object(["subjectName":text(64), "detectedSubject":box, "summary":text(400),
            "observations":object(["light":text(400), "composition":text(400), "background":text(400), "pose":text(400), "quality":text(400)]),
            "nextStep":text(400), "limitations":text(400), "plans":["type":"array", "minItems":1, "maxItems":3, "items":plan]])
    }
}
