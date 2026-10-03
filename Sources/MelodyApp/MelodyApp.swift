import SwiftUI

@main struct MelodyApp: App {
    init() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版"
        DiagnosticLog.shared.record(.info, .app, "应用启动", detail: "版本 \(version) · 系统 \(ProcessInfo.processInfo.operatingSystemVersionString)")
    }
    var body: some Scene {
        WindowGroup("Melody · 拍摄练习室") {
            StudioView()
                #if os(macOS)
                .frame(minWidth:960,minHeight:800)
                #endif
        }
        #if os(macOS)
        .defaultSize(width:1120,height:880)
        #endif
    }
}
