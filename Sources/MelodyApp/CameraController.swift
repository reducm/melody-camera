#if os(iOS)
import AVFoundation
import SwiftUI
import UIKit

/// 所有相机会话状态只在专用串行队列访问，避免阻塞界面。
final class CameraController: NSObject, CameraOperating, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "melody.camera.session")
    private let output = AVCapturePhotoOutput()
    private var device: AVCaptureDevice?
    private var baseFactor: CGFloat = 1
    private var pending: CheckedContinuation<Data, Error>?
    private var timeout: DispatchWorkItem?
    private var captureID: Int64?
    func start() async throws -> [Double] {
        guard await AVCaptureDevice.requestAccess(for: .video) else { throw CameraFailure.permission }
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    if self.device == nil {
                        self.session.beginConfiguration()
                        defer { self.session.commitConfiguration() }
                        self.session.sessionPreset = .photo
                        let discovery = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInTripleCamera, .builtInDualWideCamera, .builtInWideAngleCamera], mediaType: .video, position: .back)
                        guard let device = discovery.devices.first else { throw CameraFailure.unavailable }
                        let input = try AVCaptureDeviceInput(device: device)
                        guard self.session.canAddInput(input), self.session.canAddOutput(self.output) else { throw CameraFailure.unavailable }
                        self.session.addInput(input); self.session.addOutput(self.output)
                        self.device = device
                        // 虚拟超广角的最小倍率不等于系统相机 UI 的 1×，用切换点映射主摄。
                        if device.deviceType == .builtInTripleCamera || device.deviceType == .builtInDualWideCamera {
                            self.baseFactor = device.virtualDeviceSwitchOverVideoZoomFactors.first.map { CGFloat(truncating: $0) } ?? 2
                        }
                        self.output.maxPhotoQualityPrioritization = .balanced
                    }
                    if !self.session.isRunning { self.session.startRunning() }
                    guard let device = self.device else { throw CameraFailure.unavailable }
                    let zooms = [0.5, 1.0, 2.0].filter {
                        let z = CGFloat($0) * self.baseFactor
                        return z >= device.minAvailableVideoZoomFactor && z <= device.maxAvailableVideoZoomFactor
                    }
                    continuation.resume(returning: zooms)
                } catch { continuation.resume(throwing: error) }
            }
        }
    }
    func setZoom(_ zoom: Double) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    guard let device = self.device else { throw CameraFailure.unavailable }
                    try device.lockForConfiguration(); defer { device.unlockForConfiguration() }
                    device.videoZoomFactor = min(device.maxAvailableVideoZoomFactor, max(device.minAvailableVideoZoomFactor, CGFloat(zoom) * self.baseFactor))
                    continuation.resume()
                } catch { continuation.resume(throwing: error) }
            }
        }
    }
    func capture() async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                guard self.pending == nil else { continuation.resume(throwing: CameraFailure.busy); return }
                guard self.session.isRunning else { continuation.resume(throwing: CameraFailure.unavailable); return }
                self.pending = continuation
                let settings = AVCapturePhotoSettings()
                settings.photoQualityPrioritization = .balanced
                self.captureID = settings.uniqueID
                if let connection = self.output.connection(with: .video), connection.isVideoRotationAngleSupported(90) {
                    connection.videoRotationAngle = 90
                }
                let work = DispatchWorkItem { [weak self] in
                    guard let self else { return }
                    self.pending?.resume(throwing: CameraFailure.timeout)
                    self.pending = nil; self.captureID = nil
                }
                self.timeout = work
                self.queue.asyncAfter(deadline: .now() + 12, execute: work)
                self.output.capturePhoto(with: settings, delegate: self)
            }
        }
    }
    func stop() {
        queue.async {
            self.timeout?.cancel(); self.timeout = nil
            self.pending?.resume(throwing: CancellationError()); self.pending = nil; self.captureID = nil
            if self.session.isRunning { self.session.stopRunning() }
        }
    }
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let data = photo.fileDataRepresentation()
        queue.async {
            guard self.captureID == photo.resolvedSettings.uniqueID else { return }
            self.timeout?.cancel(); self.timeout = nil
            defer { self.pending = nil; self.captureID = nil }
            if let error { self.pending?.resume(throwing: error) }
            else if let data { self.pending?.resume(returning: data) }
            else { self.pending?.resume(throwing: CameraFailure.capture) }
        }
    }
}
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    final class Preview: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var cameraLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
        override func layoutSubviews() {
            super.layoutSubviews()
            if let connection = cameraLayer.connection, connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
        }
    }
    func makeUIView(context: Context) -> Preview {
        let view = Preview(); view.cameraLayer.session = session; view.cameraLayer.videoGravity = .resizeAspect
        return view
    }
    func updateUIView(_ view: Preview, context: Context) {}
}
#endif
