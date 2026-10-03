import SwiftUI
import MelodyCore

struct StudioView: View {
    @StateObject private var studio: StudioModel
    init(studio: StudioModel) { _studio = StateObject(wrappedValue:studio) }
    init() { _studio = StateObject(wrappedValue:StudioModel()) }
    @State private var settings = false
    @State private var history = false
    @State private var renaming = false
    @State private var titleDraft = ""
    @Environment(\.scenePhase) private var phase
    var body: some View {
        VStack(spacing:0) {
            HStack(spacing:14) {
                Button { studio.pauseCameraForHistory(); history = true } label: { Image(systemName:"clock.arrow.circlepath").frame(width:36,height:40) }.accessibilityLabel("拍摄历史").disabled(studio.busy)
                VStack(alignment:.leading,spacing:3) {
                    Button {
                        if studio.currentProject != nil { titleDraft = studio.projectTitle; renaming = true }
                    } label: {
                        HStack(spacing:4) {
                            Text(studio.currentProject == nil ? "melody" : studio.projectTitle).font(.headline).lineLimit(1)
                            if studio.currentProject != nil { Image(systemName:"pencil").font(.caption2) }
                        }
                    }.buttonStyle(.plain).disabled(studio.busy).accessibilityLabel("修改项目名称")
                    Text(studio.currentProject == nil ? "拍下第一张，开始一个项目" : "\(studio.currentProject?.photos.count ?? 0) 张照片 · \(studio.pendingProjectSaves > 0 ? "正在保存" : (studio.historySaveFailed ? "保存待重试" : "本机项目"))")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer(minLength:4)
                if studio.currentProject != nil {
                    Button { studio.newProject() } label: { Image(systemName:"plus").frame(width:32,height:40) }.accessibilityLabel("新建拍摄项目").disabled(studio.busy || studio.historySaveFailed)
                }
                Button { settings = true } label: { Image(systemName:"slider.horizontal.3").frame(width:36,height:40) }.accessibilityLabel("模型设置")
            }.padding(.horizontal,16).padding(.vertical,8)
            if studio.historySaveFailed {
                HStack { Text(studio.historyMessage).font(.caption); Button("重试保存") { studio.persistCurrentProject() } }.padding(12).background(Color.orange.opacity(0.15))
            }
            if studio.showEditor { PhotoEditor(studio:studio) }
            else { cameraScreen }
        }.frame(maxWidth:.infinity,maxHeight:.infinity).background(Color.melodyBackground).foregroundStyle(.white)
        .preferredColorScheme(.dark)
        .sheet(isPresented:$settings) { ProviderSettings(studio:studio) }
        .sheet(isPresented:$history,onDismiss: { studio.enterCameraIfNeeded() }) { ProjectHistoryView(studio:studio) }
        .alert("暂时没能完成",isPresented:Binding(get:{studio.error != nil},set:{if !$0 {studio.error = nil}})) {
            Button("知道了",role:.cancel) { studio.error = nil }
        } message: { Text(studio.error ?? "") }
        .alert("修改项目名称",isPresented:$renaming) {
            TextField("项目名称",text:$titleDraft)
            Button("取消",role:.cancel) {}
            Button("保存") { studio.renameProject(titleDraft) }
                .disabled(titleDraft.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || titleDraft.count > 100)
        } message: { Text("最多 100 字。手动命名后，生成推荐不会覆盖名称。") }
        .task { studio.enterCameraIfNeeded(); await studio.refreshProjectHistory() }
        .onChange(of:phase) { _, value in
            if value == .background { DiagnosticLog.shared.record(.info, .app, "应用进入后台"); studio.suspend() }
            else if value == .active && !history && !settings { studio.enterCameraIfNeeded() }
        }
    }
    private var cameraScreen: some View {
        VStack(spacing:12) {
            GeometryReader { proxy in
                ZStack {
                    viewfinder.aspectRatio(0.75,contentMode:.fit).frame(maxWidth:560).padding(.horizontal,12)
                }.frame(width:proxy.size.width,height:proxy.size.height)
            }
            if let plan = studio.selected {
                HStack(alignment:.top,spacing:10) {
                    Image(systemName:"viewfinder").foregroundStyle(Color.melodyLime)
                    VStack(alignment:.leading,spacing:4) {
                        Text(plan.title).font(.subheadline.bold())
                        Text(plan.instruction).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                    }
                    Spacer()
                    Button("换模板") { studio.pauseCameraForHistory(); studio.showEditor = true }.font(.caption).disabled(studio.busy)
                }.padding(.horizontal,20)
            } else {
                Text(studio.currentProject == nil ? "拍一张，或从相册选择照片" : "新照片会加入「\(studio.projectTitle)」")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            HStack(spacing:16) {
                ForEach(studio.zooms,id:\.self) { value in
                    Button { studio.chooseZoom(value) } label: {
                        Text("\(value.formatted())×").font(.subheadline.monospacedDigit()).frame(width:48,height:34)
                            .background(studio.zoom == value ? Color.melodyLime : Color.melodySurface,in:Capsule())
                            .foregroundStyle(studio.zoom == value ? Color.melodyBackground : .white)
                    }.disabled(studio.busy)
                }
            }
            if studio.busy {
                HStack { Text(studio.progress).font(.caption); Spacer(); Button("取消") { studio.cancel() } }.padding(.horizontal,24)
                ProgressView().progressViewStyle(.linear).tint(Color.melodyLime).padding(.horizontal,24)
            }
            HStack {
                SystemPhotoButton(studio:studio).frame(maxWidth:.infinity)
                Button { studio.capture() } label: {
                    Circle().stroke(.white,lineWidth:3).frame(width:76,height:76)
                        .overlay { Circle().fill(Color.melodyLime).padding(7) }
                }.accessibilityLabel(shutterLabel).disabled(shutterDisabled)
                Button {
                    studio.pauseCameraForHistory()
                    if studio.original != nil { studio.showEditor = true } else { history = true }
                } label: {
                    VStack(spacing:6) { Image(systemName:studio.original == nil ? "clock" : "square.stack").font(.title2); Text(studio.original == nil ? "历史" : "当前项目").font(.caption2) }
                }.frame(maxWidth:.infinity).disabled(studio.busy)
            }.padding(.horizontal,16).padding(.bottom,18)
        }.padding(.top,6)
    }
    private var shutterLabel: String {
        #if os(iOS)
        return "拍照并进入项目"
        #else
        return "生成练习照片并进入项目"
        #endif
    }
    private var shutterDisabled: Bool {
        #if os(iOS)
        return studio.busy || studio.source != .camera
        #else
        return studio.busy
        #endif
    }
    private var viewfinder: some View {
        ZStack {
            #if os(iOS)
            if studio.source == .camera { CameraPreview(session:studio.camera.session) }
            else {
                Color.black
                VStack(spacing:16) {
                    Image(systemName:"camera").font(.largeTitle)
                    Text(studio.busy ? "正在准备相机" : "选择照片也可以开始拍摄项目").font(.subheadline)
                    if !studio.busy { Button("重试相机") { studio.startCamera() }.font(.caption).tint(Color.melodyLime) }
                }.foregroundStyle(.secondary)
            }
            #else
            DemoScene(scene:studio.scene).scaleEffect(studio.zoom).clipped()
            #endif
            CompositionOverlay(subject:studio.selected?.subject,grid:studio.grid,opacity:studio.guideOpacity,showPerson:false)
            if let outline = studio.guideOutline, let plan = studio.selected { SubjectOutlineView(outline:outline,target:plan.subject,opacity:studio.guideOpacity) }
            VStack {
                HStack {
                    Text(studio.selected == nil ? previewLabel : "模板跟拍 · 目标描边").font(.caption2).padding(9).background(.black.opacity(0.45),in:Capsule())
                    Spacer()
                    Button { studio.grid.toggle() } label: { Image(systemName:"grid").padding(10).background(.black.opacity(0.4),in:Circle()) }.accessibilityLabel("切换九宫格")
                }
                Spacer()
            }.padding(12)
        }.background(.black).clipShape(RoundedRectangle(cornerRadius:24))
    }
    private var previewLabel: String {
        #if os(iOS)
        return "实景取景"
        #else
        return "Mac 练习画面 · 非实拍"
        #endif
    }
}
