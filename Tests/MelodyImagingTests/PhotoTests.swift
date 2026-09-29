import Testing
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import MelodyImaging
func testImage() -> CGImage {
    let c = CGContext(data: nil, width: 60, height: 80, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    c.setFillColor(CGColor(red: 0.3, green: 0.5, blue: 0.4, alpha: 1)); c.fill(CGRect(x: 0, y: 0, width: 60, height: 80))
    return c.makeImage()!
}
@Test func exportsReadableJPEGAndResizes() throws {
    let data = try PhotoProcessor.jpeg(testImage())
    #expect(data.count > 100)
    let image = try PhotoProcessor.load(data, maxPixel: 40)
    #expect(image.width == 30)
    #expect(image.height == 40)
}
@Test func cropModelsDigitalZoom() throws {
    let image = try PhotoProcessor.crop(testImage(), zoom: 2)
    #expect(image.width == 30)
    #expect(image.height == 40)
}
@Test func originalAndZeroIntensityPreserveImage() throws {
    let image = testImage()
    #expect(try PhotoProcessor.render(image, style: .original, amount: 1) === image)
    #expect(try PhotoProcessor.render(image, style: .warm, amount: 0) === image)
}
@Test func colorAdjustmentChangesPixelsWithoutChangingSize() throws {
    let image = testImage()
    let edited = try PhotoProcessor.render(image, style: .warm, amount: 0.8)
    #expect(edited.width == image.width && edited.height == image.height)
    #expect(try PhotoProcessor.jpeg(edited) != PhotoProcessor.jpeg(image))
}
@Test func rejectsCorruptInput() {
    #expect(throws: PhotoError.self) { try PhotoProcessor.load(Data("invalid".utf8)) }
}
@Test func normalizesOrientationAndStripsLocationForUpload() throws {
    let encoded = NSMutableData()
    let destination = CGImageDestinationCreateWithData(encoded, UTType.jpeg.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, testImage(), [
        kCGImagePropertyOrientation: 6,
        kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 31.2, kCGImagePropertyGPSLatitudeRef: "N"]
    ] as CFDictionary)
    #expect(CGImageDestinationFinalize(destination))
    let oriented = try PhotoProcessor.load(encoded as Data)
    #expect(oriented.width == 80 && oriented.height == 60)
    let clean = try PhotoProcessor.jpeg(oriented,quality:0.75)
    let source = CGImageSourceCreateWithData(clean as CFData,nil)!
    let metadata = CGImageSourceCopyPropertiesAtIndex(source,0,nil) as? [CFString:Any]
    #expect(metadata?[kCGImagePropertyGPSDictionary] == nil)
}
