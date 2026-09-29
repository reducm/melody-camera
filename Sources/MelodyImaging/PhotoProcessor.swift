import Foundation
import CoreImage
import ImageIO
import UniformTypeIdentifiers

public enum PhotoError: Error, LocalizedError {
    case unreadable, render
    public var errorDescription: String? {
        switch self { case .unreadable: return "无法读取这张图片，请换一张 JPEG、HEIC 或 PNG。"; case .render: return "照片处理失败，请保留原片并重试。" }
    }
}
public enum ColorStyle: String, CaseIterable, Sendable {
    case original = "原片", natural = "自然透亮", warm = "暖调日光", film = "柔和胶片"
}
public enum PhotoProcessor {
    private static let context = CIContext(options: [.cacheIntermediates: false])
    public static func load(_ data: Data, maxPixel: Int = 2400) throws -> CGImage {
        guard maxPixel > 0, let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixel,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { throw PhotoError.unreadable }
        return image
    }
    /// 新编码只写像素与压缩质量，不复制原片中的 EXIF/GPS。
    public static func jpeg(_ image: CGImage, quality: Double = 0.9) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { throw PhotoError.render }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: min(1, max(0, quality))] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw PhotoError.render }
        return data as Data
    }
    public static func render(_ image: CGImage, style: ColorStyle, amount: Double) throws -> CGImage {
        guard style != .original, amount.isFinite, amount > 0 else { return image }
        let value = min(amount, 1)
        var output = CIImage(cgImage: image)
        let exposure: Double = style == .film ? 0.08 : 0.22
        output = output.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: exposure * value])
        output = output.applyingFilter("CIColorControls", parameters: [
            kCIInputSaturationKey: 1 + (style == .film ? -0.18 : 0.06) * value,
            kCIInputContrastKey: 1 + (style == .film ? -0.08 : 0.025) * value
        ])
        if style == .warm {
            output = output.applyingFilter("CITemperatureAndTint", parameters: [
                "inputNeutral": CIVector(x: 6500, y: 0), "inputTargetNeutral": CIVector(x: 6500 + 900 * value, y: 0)
            ])
        }
        guard let result = context.createCGImage(output, from: output.extent) else { throw PhotoError.render }
        return result
    }
    public static func crop(_ image: CGImage, zoom: Double) throws -> CGImage {
        guard zoom.isFinite, zoom >= 1 else { throw PhotoError.render }
        let w = max(1, Int(Double(image.width) / zoom)), h = max(1, Int(Double(image.height) / zoom))
        guard let result = image.cropping(to: CGRect(x: (image.width-w)/2, y: (image.height-h)/2, width: w, height: h)) else { throw PhotoError.render }
        return result
    }
}
