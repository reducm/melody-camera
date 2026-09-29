import SwiftUI

@main struct MelodyApp: App {
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
