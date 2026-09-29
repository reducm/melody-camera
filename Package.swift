// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "MelodyCamera",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "MelodyImaging", targets: ["MelodyImaging"]), .library(name: "MelodyCore", targets: ["MelodyCore"]), .executable(name: "MelodyCamera", targets: ["MelodyApp"])],
    targets: [
        .target(name: "MelodyCore"),
        .target(name: "MelodyImaging"),
        .executableTarget(name: "MelodyApp", dependencies: ["MelodyCore", "MelodyImaging"]),
        .testTarget(name: "MelodyImagingTests", dependencies: ["MelodyImaging"]),
        .testTarget(name: "MelodyAppTests", dependencies: ["MelodyApp"]),
        .testTarget(name: "MelodyCoreTests", dependencies: ["MelodyCore"])
    ],
    swiftLanguageModes: [.v5]
)
