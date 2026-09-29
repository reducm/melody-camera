import SwiftUI
import UniformTypeIdentifiers
import MelodyCore
import MelodyImaging

struct StudioView: View {
    @StateObject private var studio: StudioModel
    init(studio: StudioModel) { _studio = StateObject(wrappedValue: studio) }
    init() { _studio = StateObject(wrappedValue: StudioModel()) }
    @State private var settings = false
    @State private var importing = false
    @Environment(\.scenePhase) private var phase
    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width > 760
            VStack(spacing: 0) {
                header(wide: wide)
                if wide {
                    HStack(alignment: .top, spacing: 30) {
                        intro.frame(width: 185)
                        cameraColumn.frame(maxWidth: 390)
                        ScrollView { planPanel }.frame(maxWidth: 330)
                    }.padding(30).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                } else {
                    ScrollView {
                        VStack(spacing: 20) {
                            cameraColumn
                            planPanel
                        }.padding(.horizontal, 18).padding(.vertical, 12)
                    }
                }
                if !studio.notice.isEmpty {
                    Text(studio.notice).font(.caption).foregroundStyle(Color.melodyLime).padding(10).frame(maxWidth:.infinity).background(Color.melodySurface)
                }
            }.background(Color.melodyBackground).foregroundStyle(.white)
        }
        .preferredColorScheme(.dark)
        .buttonStyle(.plain)
        .sheet(isPresented: $settings) { ProviderSettings(studio: studio) }
        .sheet(isPresented: $studio.showEditor) { PhotoEditor(studio: studio) }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.image]) { result in
            switch result { case .success(let url): studio.loadPhoto(url); case .failure(let error): studio.error = error.localizedDescription }
        }
        .alert("暂时没能完成", isPresented: Binding(get: { studio.error != nil }, set: { if !$0 { studio.error = nil } })) {
            Button("知道了", role: .cancel) { studio.error = nil }
        } message: { Text(studio.error ?? "") }
        .onChange(of: phase) { _, value in if value == .background { studio.suspend() } }
    }
    private func header(wide: Bool) -> some View {
        HStack {
            HStack(spacing:10) {
                Image(systemName:"viewfinder").font(.title2).foregroundStyle(Color.melodyLime)
                Text("melody").font(.system(size:25,weight:.medium,design:.serif))
                if wide { Text("把喜欢的人，拍成喜欢的样子").font(.caption).foregroundStyle(Color.melodyMuted).padding(.leading,18) }
            }
            Spacer()
            Button { settings = true } label: { Label("模型设置",systemImage:"slider.horizontal.3").font(.caption).padding(10).background(Color.melodySurface,in:Capsule()) }
                .disabled(studio.busy)
        }.padding(.horizontal,24).padding(.vertical,19).overlay(alignment:.bottom) { Rectangle().fill(.white.opacity(0.07)).frame(height:1) }
    }
    private var intro: some View {
        VStack(alignment:.leading,spacing:22) {
            Text("为 Melody 而做").font(.caption).tracking(3).foregroundStyle(Color.melodyLime)
            Text("先看见美，\n再按快门。").font(.system(size:28,weight:.regular,design:.serif)).lineSpacing(8)
            Text("不必记住摄影术语。\n选一个建议，跟着轮廓，\n慢慢找到属于她的画面。").font(.system(size:13)).lineSpacing(7).foregroundStyle(Color.melodyMuted)
            Rectangle().fill(.white.opacity(0.1)).frame(height:1).padding(.vertical,8)
            step("01", "观察", "看看光线与环境")
            step("02", "构图", "选择一个拍摄方案")
            step("03", "留住", "拍摄后，自然调色")
            Spacer(minLength:30)
            Text("首版 · 拍摄练习室\nMac 演示 / iPhone 原生工程").font(.system(size:10)).lineSpacing(5).foregroundStyle(Color.melodyMuted)
        }.padding(.top,22)
    }
    private func step(_ number: String, _ title: String, _ subtitle: String) -> some View {
        HStack(alignment:.top,spacing:14) {
            Text(number).font(.system(size:11,design:.monospaced)).foregroundStyle(Color.melodyLime).padding(.top,3)
            VStack(alignment:.leading,spacing:5) { Text(title).font(.subheadline); Text(subtitle).font(.caption).foregroundStyle(Color.melodyMuted) }
        }
    }
    private var cameraColumn: some View {
        VStack(spacing:14) {
            HStack {
                Label(studio.source.rawValue,systemImage:studio.source == .camera ? "circle.fill" : "sparkle").font(.caption).foregroundStyle(Color.melodyLime)
                Spacer()
                Button { studio.grid.toggle() } label: { Image(systemName:"grid").foregroundStyle(studio.grid ? Color.melodyLime : .gray) }.accessibilityLabel("切换九宫格")
                Button { importing = true } label: { Image(systemName:"photo.on.rectangle") }.accessibilityLabel("导入照片").disabled(studio.busy)
                #if os(iOS)
                Button { studio.startCamera() } label: { Image(systemName:"camera") }.accessibilityLabel("启动实景相机").disabled(studio.busy)
                #endif
            }
            viewfinder
            HStack(spacing:12) {
                ForEach(studio.zooms,id:\.self) { value in
                    Button { studio.chooseZoom(value) } label: {
                        Text("\(value.formatted())×").font(.system(size:12,weight:.semibold)).frame(width:48,height:32)
                            .background(studio.zoom == value ? Color.melodyLime : Color.melodySurface,in:Capsule())
                            .foregroundStyle(studio.zoom == value ? Color.melodyBackground : .white)
                    }.disabled(studio.busy)
                }
                Spacer()
                Text(studio.source == .camera ? "顺序观察" : "演示为数字裁切").font(.system(size:10)).foregroundStyle(Color.melodyMuted)
            }
            HStack(spacing:20) {
                Button { studio.analyze() } label: { VStack(spacing:5) { Image(systemName:"sparkles").foregroundStyle(Color.melodyLime); Text(studio.mode == .offline ? "构图灵感" : "AI 构图").font(.system(size:10)) }.frame(width:58) }.disabled(studio.busy)
                Spacer()
                Button { studio.capture() } label: {
                    Circle().stroke(.white.opacity(0.6),lineWidth:2).frame(width:68,height:68)
                        .overlay { Circle().fill(Color.melodyLime).padding(6).overlay { Image(systemName:"camera.fill").foregroundStyle(Color.melodyBackground).font(.title3) } }
                }.accessibilityLabel(studio.source == .camera ? "拍照" : "生成练习照片").disabled(studio.busy)
                Spacer()
                Button { studio.showEditor = true } label: { VStack(spacing:5) { Image(systemName:"slider.horizontal.3"); Text("最近照片").font(.system(size:10)) }.frame(width:58) }.disabled(studio.original == nil)
            }.padding(.top,2)
        }
    }
    private var viewfinder: some View {
        ZStack {
            GeometryReader { geometry in
                ZStack {
                    if studio.source == .camera {
                        #if os(iOS)
                        CameraPreview(session:studio.camera.session)
                        #endif
                    } else if let image = studio.previewImage, studio.source == .imported {
                        Image(decorative:image,scale:1).resizable().scaledToFit()
                    } else {
                        DemoScene(scene:studio.scene).scaleEffect(studio.zoom).clipped()
                    }
                    CompositionOverlay(subject:studio.selected?.subject,grid:studio.grid,opacity:studio.guideOpacity)
                }.frame(width:geometry.size.width,height:geometry.size.height)
            }
            VStack {
                HStack {
                    Text(studio.source == .demo ? "矢量练习画面 · 非实拍" : (studio.source == .imported ? "本机照片" : "相机取景"))
                        .font(.system(size:10)).padding(.horizontal,10).padding(.vertical,7).background(.black.opacity(0.35),in:Capsule())
                    Spacer()
                    Image(systemName:"viewfinder").foregroundStyle(.white.opacity(0.85))
                }
                Spacer()
                if let plan = studio.selected {
                    Text(plan.title + " · 轮廓为目标位置").font(.caption).padding(.horizontal,12).padding(.vertical,8).background(.black.opacity(0.45),in:Capsule())
                } else {
                    Text("先选一个方案，让构图更有把握").font(.caption).padding(9).background(.black.opacity(0.4),in:Capsule())
                }
            }.padding(14)
        }
        .aspectRatio(previewAspect,contentMode:.fit)
        .background(.black)
        .clipShape(RoundedRectangle(cornerRadius:20))
        .overlay { RoundedRectangle(cornerRadius:20).stroke(.white.opacity(0.12),lineWidth:1) }
    }
    private var previewAspect: CGFloat {
        if studio.source == .imported, let image = studio.previewImage { return CGFloat(image.width)/CGFloat(image.height) }
        return 0.75
    }
    private var planPanel: some View {
        VStack(alignment:.leading,spacing:18) {
            HStack { Text("你的构图小助手").font(.system(size:21,weight:.medium,design:.serif)); Spacer(); Image(systemName:"sparkles").foregroundStyle(Color.melodyLime) }
            Text("好照片，从一个小小的调整开始。").font(.caption).foregroundStyle(Color.melodyMuted)
            Picker("场景",selection:$studio.scene) {
                ForEach(SceneKind.allCases,id:\.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.menu).tint(Color.melodyLime).disabled(studio.busy)
                .onChange(of:studio.scene) { _,_ in studio.changeScene() }
            Picker("建议来源",selection:$studio.mode) {
                ForEach(DirectorMode.allCases,id:\.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented).disabled(studio.busy)
            Button { studio.analyze() } label: {
                HStack { Image(systemName:"sparkles"); Text(studio.mode == .offline ? "给我拍摄灵感" : "AI 看看怎么拍").fontWeight(.semibold); Spacer(); Image(systemName:"arrow.up.right") }
                    .padding(15).background(Color.melodyLime,in:RoundedRectangle(cornerRadius:14)).foregroundStyle(Color.melodyBackground)
            }.disabled(studio.busy)
            if studio.busy {
                HStack { ProgressView().controlSize(.small); Text(studio.progress).font(.caption); Spacer(); Button("取消") { studio.cancel() }.font(.caption).foregroundStyle(Color.melodyLime) }
            }
            if studio.plans.isEmpty {
                VStack(alignment:.leading,spacing:12) {
                    Image(systemName:"rectangle.dashed").font(.title).foregroundStyle(Color.melodyLime)
                    Text("留白、靠近、走进风景").font(.subheadline)
                    Text("生成方案后，轻点卡片，把人物放进取景框。离线模式依据所选场景给建议，不识别画面。").font(.caption).lineSpacing(5).foregroundStyle(Color.melodyMuted)
                }.padding(20).frame(maxWidth:.infinity,alignment:.leading).background(Color.melodySurface,in:RoundedRectangle(cornerRadius:16))
            } else {
                Text(studio.planSource).font(.system(size:10)).foregroundStyle(Color.melodyMuted)
                ForEach(Array(studio.plans.enumerated()),id:\.element.id) { index, plan in
                    Button { studio.choose(plan) } label: {
                        VStack(alignment:.leading,spacing:10) {
                            HStack {
                                Text("0\(index+1)").font(.system(size:11,design:.monospaced)).foregroundStyle(Color.melodyLime)
                                Text(plan.title).font(.system(size:15,weight:.medium)); Spacer()
                                Text("\(plan.zoom.formatted())×").font(.caption).foregroundStyle(Color.melodyLime)
                            }
                            Text(plan.instruction).font(.system(size:12)).lineSpacing(4).fixedSize(horizontal:false,vertical:true)
                            if studio.selected?.id == plan.id { Text(plan.reason).font(.system(size:11)).foregroundStyle(Color.melodyMuted).lineSpacing(3).fixedSize(horizontal:false,vertical:true) }
                        }.padding(15).frame(maxWidth:.infinity,alignment:.leading)
                            .background(studio.selected?.id == plan.id ? Color.melodyLime.opacity(0.09) : Color.melodySurface,in:RoundedRectangle(cornerRadius:14))
                            .overlay { RoundedRectangle(cornerRadius:14).stroke(studio.selected?.id == plan.id ? Color.melodyLime.opacity(0.6) : .clear,lineWidth:1) }
                    }.disabled(studio.busy)
                }
                HStack { Text("轮廓透明度").font(.caption).foregroundStyle(Color.melodyMuted); Slider(value:$studio.guideOpacity,in:0.15...1).tint(Color.melodyLime) }
            }
            if studio.source != .demo {
                Button("回到练习场景") { studio.demo() }.font(.caption).foregroundStyle(Color.melodyLime).disabled(studio.busy)
            }
            HStack(alignment:.top,spacing:8) { Image(systemName:"lock.shield"); Text(studio.mode == .offline ? "离线建议不上传画面。照片的样子，由你们决定。" : "在线分析需先配置支持视觉的模型，并允许本次会话上传。") }.font(.system(size:10)).foregroundStyle(Color.melodyMuted).lineSpacing(4)
        }.padding(.top,8)
    }
}
