import Foundation

/// 不暴露 AVFoundation 的拍摄接口，使后台/取消行为可以脱离硬件测试。
protocol CameraOperating: Sendable {
    func start() async throws -> [Double]
    func setZoom(_ zoom: Double) async throws
    func capture() async throws -> Data
    func stop()
}
enum CameraFailure: Error, LocalizedError {
    case permission, unavailable, busy, capture, timeout
    var errorDescription: String? {
        switch self {
        case .permission: return "相机权限未开启，请到系统设置允许 Melody 使用相机；也可以从相册选择照片。"
        case .unavailable: return "当前设备没有可用相机，请从相册选择照片继续。"
        case .busy: return "相机正在拍摄，请稍候。"
        case .capture: return "拍摄失败，请重新启动相机。"
        case .timeout: return "相机响应超时，请重新启动相机。"
        }
    }
}
struct UnavailableCamera: CameraOperating {
    func start() async throws -> [Double] { throw CameraFailure.unavailable }
    func setZoom(_ zoom: Double) async throws { throw CameraFailure.unavailable }
    func capture() async throws -> Data { throw CameraFailure.unavailable }
    func stop() {}
}
