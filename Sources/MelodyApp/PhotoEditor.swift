import SwiftUI
import UniformTypeIdentifiers
import ImageIO
import MelodyImaging

struct JPEGDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.image] }
    var data: Data
    init(data:Data) { self.data = data }
    init(configuration:ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration:WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents:data) }
}
struct PhotoEditor: View {
    @ObservedObject var studio: StudioModel
    @Environment(\.dismiss) private var dismiss
    @State private var exporting = false
    @State private var exportType: UTType = .jpeg
    @State private var document: JPEGDocument?
    @State private var name = "Melody-调色副本"
    var body: some View {
        VStack(spacing:18) {
            HStack { VStack(alignment:.leading,spacing:5) { Text("留住这一刻").font(.title2); Text("自然调色 · 原片始终保留").font(.caption).foregroundStyle(.secondary) }; Spacer(); Button("返回取景") { dismiss() } }
            if let image = studio.compare ? studio.original : studio.edited {
                Image(decorative:image,scale:1).resizable().scaledToFit().frame(maxHeight:480).clipShape(RoundedRectangle(cornerRadius:14))
                    .overlay(alignment:.topLeading) { Text(studio.compare ? "原片" : studio.style.rawValue).font(.caption).padding(8).background(.black.opacity(0.5),in:Capsule()).padding(12) }
            }
            Picker("调色风格",selection:$studio.style) { ForEach(ColorStyle.allCases,id:\.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
                .onChange(of:studio.style) { _,_ in studio.updateEdit() }
            HStack { Text("强度").font(.caption); Slider(value:$studio.amount,in:0...1).tint(Color.melodyLime).onChange(of:studio.amount) { _,_ in studio.updateEdit() }; Text("\(Int(studio.amount*100))%").font(.caption).monospacedDigit().frame(width:40) }
            Toggle("对比原片",isOn:$studio.compare).tint(Color.melodyLime)
            HStack {
                Button("保存原片") { save(original:true) }.buttonStyle(.bordered)
                Spacer()
                Button("保存调色副本") { save(original:false) }.buttonStyle(.borderedProminent).tint(Color.melodyLime).foregroundStyle(Color.melodyBackground)
            }
            Text("当前支持曝光、色温与色彩调整。磨皮、瘦脸和睁眼修复尚未接入。").font(.caption2).foregroundStyle(.secondary)
            if !studio.notice.isEmpty { Text(studio.notice).font(.caption).foregroundStyle(Color.melodyLime) }
        }.padding(24).frame(idealWidth:520,idealHeight:780).background(Color.melodyBackground).preferredColorScheme(.dark)
        .fileExporter(isPresented:$exporting,document:document,contentType:exportType,defaultFilename:name) { result in
            switch result { case .success: studio.notice = "照片已导出。"; case .failure(let error): studio.error = error.localizedDescription }
        }
        .alert("保存失败",isPresented:Binding(get:{studio.error != nil},set:{if !$0 {studio.error = nil}})) { Button("知道了") {studio.error = nil} } message: {Text(studio.error ?? "")}
    }
    private func save(original:Bool) {
        #if os(iOS)
        studio.saveToPhotos(original:original)
        #else
        do {
            let data = try studio.exportData(original:original)
            if let source = CGImageSourceCreateWithData(data as CFData,nil), let type = CGImageSourceGetType(source) {
                exportType = UTType(type as String) ?? .jpeg
            } else { exportType = .jpeg }
            document = JPEGDocument(data:data); name = original ? "Melody-原片" : "Melody-调色副本"; exporting = true
        }
        catch {studio.error = error.localizedDescription}
        #endif
    }
}
