import SwiftUI
import UniformTypeIdentifiers
import MelodyCore
#if os(iOS)
import PhotosUI
#endif

struct SystemPhotoButton: View {
    @ObservedObject var studio: StudioModel
    var compact = false
    @State private var importing = false
    #if os(iOS)
    @State private var item: PhotosPickerItem?
    #endif
    private var label: some View {
        VStack(spacing:6) { Image(systemName:"photo.on.rectangle").font(compact ? .body : .title2); Text("选照片").font(.caption2) }
    }
    var body: some View {
        Group {
            #if os(iOS)
            PhotosPicker(selection:$item,matching:.images,preferredItemEncoding:.current) { label }
                .onChange(of:item) { _, value in
                    guard let value else { return }
                    Task {
                        do {
                            guard let bytes = try await value.loadTransferable(type:Data.self) else { throw ProjectFailure.missingOriginal }
                            await studio.importPhotoData(bytes)
                        } catch { studio.error = "无法打开所选照片，请等待 iCloud 下载后重试。" }
                        item = nil
                    }
                }
            #else
            Button { importing = true } label: { label }
                .fileImporter(isPresented:$importing,allowedContentTypes:[.image]) { result in
                    if case .success(let url) = result {
                        Task {
                            let access = url.startAccessingSecurityScopedResource()
                            defer { if access { url.stopAccessingSecurityScopedResource() } }
                            do {
                                guard (try url.resourceValues(forKeys:[.fileSizeKey])).fileSize ?? 0 <= 40_000_000 else { throw ProjectFailure.missingOriginal }
                                await studio.importPhotoData(try Data(contentsOf:url))
                            } catch { studio.error = "无法读取这张照片，请选择小于40MB的图片。" }
                        }
                    }
                }
            #endif
        }.disabled(studio.busy).accessibilityLabel("打开系统照片")
    }
}
struct ProjectThumbnail: View {
    @ObservedObject var studio: StudioModel
    let projectID: UUID
    let photoID: UUID
    @State private var image: CGImage?
    var body: some View {
        ZStack {
            Color.melodySurface
            if let image { Image(decorative:image,scale:1).resizable().scaledToFill() }
            else { Image(systemName:"photo").foregroundStyle(.secondary) }
        }.clipped().task(id:photoID) { image = await studio.thumbnail(projectID:projectID,photoID:photoID) }
    }
}
struct ProjectHistoryView: View {
    @ObservedObject var studio: StudioModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment:.leading,spacing:16) {
                    Text("每个项目保留照片、历次推荐和调色配方。仅保存在这台设备，卸载应用会删除。").font(.caption).foregroundStyle(.secondary)
                    if !studio.historyMessage.isEmpty { Text(studio.historyMessage).font(.caption).foregroundStyle(.orange) }
                    if studio.projectHistory.isEmpty {
                        ContentUnavailableView("还没有拍摄项目",systemImage:"camera",description:Text("拍摄或选择第一张照片后，项目会自动保存到这里。"))
                    }
                    ForEach(studio.projectHistory) { project in
                        Button {
                            Task { await studio.openProject(project.id); if studio.currentProject?.id == project.id && studio.showEditor { dismiss() } }
                        } label: {
                            HStack(spacing:16) {
                                if let photo = project.activePhoto {
                                    ProjectThumbnail(studio:studio,projectID:project.id,photoID:photo.id).frame(width:80,height:96).clipShape(RoundedRectangle(cornerRadius:12))
                                }
                                VStack(alignment:.leading,spacing:8) {
                                    Text(project.title).font(.headline).lineLimit(2)
                                    Text("\(project.photos.count) 张照片 · \(project.photos.reduce(0) { $0 + $1.recommendations.count }) 轮推荐").font(.caption).foregroundStyle(.secondary)
                                    Text(project.updatedAt.formatted(date:.abbreviated,time:.shortened)).font(.caption2).foregroundStyle(.secondary)
                                    Text("继续编辑与拍摄").font(.caption).foregroundStyle(Color.melodyLime)
                                }
                                Spacer(minLength:0); Image(systemName:"chevron.right").font(.caption)
                            }.padding(14).background(Color.melodySurface,in:RoundedRectangle(cornerRadius:20))
                        }.buttonStyle(.plain).disabled(studio.busy)
                    }
                }.padding(20)
            }.background(Color.melodyBackground).navigationTitle("拍摄历史")
                .toolbar { ToolbarItem(placement:.confirmationAction) { Button("完成") { dismiss() } } }
        }.preferredColorScheme(.dark).task { await studio.refreshProjectHistory() }
    }
}
