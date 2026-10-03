import SwiftUI
import MelodyCore
import MelodyImaging
#if os(iOS)
import UIKit
#endif

struct ReferenceSettings: View {
    @ObservedObject var controller: ReferenceGenerationController
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            Label("推荐参考图",systemImage:"photo.badge.sparkles").font(.headline)
            Toggle("生成推荐时同时生成参考图",isOn:$controller.enabled)
            Text("Draw Things 引擎在此 iPhone 内运行 Qwen Image Edit。照片留在手机，模板可先跟拍，参考图按顺序生成。").font(.caption).foregroundStyle(.secondary)
            Picker("全局参考图分辨率",selection:$controller.resolution) {
                ForEach(ReferenceResolution.allCases,id:\.self) { Text($0.title).tag($0) }
            }
            Text("用于之后的新任务；更高分辨率需要更多时间和内存。已有参考图不变。").font(.caption).foregroundStyle(.secondary)
            TimelineView(.periodic(from:.now,by:2)) { _ in
                VStack(alignment:.leading) {
                    Text(controller.modelStatus).font(.caption).foregroundStyle(.secondary)
                    if PhoneReferenceProvider.installationFraction > 0 && PhoneReferenceProvider.installationFraction < 1 {
                        ProgressView(value:PhoneReferenceProvider.installationFraction)
                    }
                }
            }
            if let error=controller.configurationError { Text(error).font(.caption).foregroundStyle(.orange) }
        }.onChange(of:controller.resolution) { _,_ in controller.saveSettings() }
         .onChange(of:controller.enabled) { _,_ in controller.saveSettings() }
    }
}
struct ReferenceDestinationNotice: View {
    @ObservedObject var controller:ReferenceGenerationController
    var body:some View {
        if controller.enabled {
            VStack(alignment:.leading,spacing:4) {
                Label("此 iPhone 生成参考图，模板可先跟拍",systemImage:"iphone")
                Text("照片留在手机 · \(controller.resolution.width) × \(controller.resolution.height)")
            }.font(.caption2).foregroundStyle(.secondary)
        }
    }
}
struct ReferenceCard: View {
    @ObservedObject var controller: ReferenceGenerationController
    let request: ReferenceImageRequest
    let generate: (Bool) -> Void
    @State private var preview=false
    @State private var reviewing=false
    private var job: ReferenceJob? { controller.job(projectID:request.projectID,photoID:request.photoID,batchID:request.batchID,planID:request.plan.id) }
    var body: some View {
        VStack(alignment:.leading,spacing:10) {
            Divider()
            Label("AI 拍法参考图",systemImage:"photo.badge.sparkles").font(.subheadline.bold())
            if let job {
                if job.state == .ready,let data=controller.imageData(job.id),let image=try? PhotoProcessor.load(data) {
                    Button { preview=true } label: { Image(decorative:image,scale:1).resizable().scaledToFit().frame(maxHeight:240).clipShape(RoundedRectangle(cornerRadius:12)) }.buttonStyle(.plain).accessibilityLabel("放大 AI 参考图")
                }
                Text(job.message).font(.caption).foregroundStyle(.secondary)
                if job.state == .ready, let design = job.design, !design.candidates.isEmpty {
                    if design.approvedOutline != nil, let adopted = try? request.plan.adopting(design) {
                        Text("已选用生成图的新轮廓，点击下方跟拍按钮即可使用。").font(.caption).foregroundStyle(Color.melodyLime)
                        ShotTemplatePreview(plan:adopted,outline:nil)
                        Button("恢复知识构图模板") { controller.revokeDesign(job.id) }.font(.caption)
                    }
                    Button(design.approvedOutline == nil ? "核对并选择参考图轮廓" : "重新核对参考图轮廓") { reviewing = true }.font(.caption)
                } else if job.state == .ready, request.plan.design != nil {
                    Text("未提取到完整且适合竖向取景的轮廓，继续使用知识构图模板。").font(.caption2).foregroundStyle(.secondary)
                }
                if let fraction=job.progress,job.isActive {
                    HStack { ProgressView(value:fraction).tint(Color.melodyLime); Text("\(Int(fraction*100))%").monospacedDigit().font(.caption) }
                    Text("采样进度；解码与保存另计").font(.caption2).foregroundStyle(.secondary)
                }
                HStack {
                    Text(job.provider).font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    if job.isActive { Button("取消参考图") { controller.cancel(job.id) }.font(.caption) }
                    else if controller.enabled { Button(job.state == .ready ? "重新生成" : "重试") { generate(true) }.font(.caption) }
                }
            } else if controller.enabled {
                Button("生成这张参考图") { generate(false) }.font(.caption)
            } else {
                Text("在模型设置中开启手机参考图；当前模板可直接跟拍。").font(.caption).foregroundStyle(.secondary)
            }
            Text("仅供角度与构图参考，可能改变细节，不代表真实拍摄效果。").font(.caption2).foregroundStyle(.secondary)
        }
        .sheet(isPresented:$preview) {
            VStack {
                HStack { Text("AI 生成参考 · 非实拍"); Spacer(); Button("完成") { preview=false } }.padding()
                if let job,let data=controller.imageData(job.id) {
                    #if os(iOS)
                    ReferenceZoomView(data:data,onDismiss:{preview=false})
                    #else
                    if let image=NSImage(data:data) { Image(nsImage:image).resizable().scaledToFit() }
                    #endif
                }
            }.background(Color.black).preferredColorScheme(.dark)
        }
        .sheet(isPresented:$reviewing) {
            if let job { ReferenceDesignReview(controller:controller,jobID:job.id) }
        }
    }
}

private struct ReferenceDesignReview: View {
    @ObservedObject var controller: ReferenceGenerationController
    let jobID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var selectedID: Int?
    @State private var identity = false
    @State private var composition = false
    @State private var executable = false
    @State private var error: String?
    private var job: ReferenceJob? { controller.jobs.first { $0.id == jobID } }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:16) {
                    Text("先核对画面，再把描边用于跟拍").font(.headline)
                    Text("这里显示下一次竖向取景使用的 3:4 中央区域。描边来自 AI 合成图片，分割成功并不保证主体、角度或细节正确。").font(.caption).foregroundStyle(.secondary)
                    if let data = controller.imageData(jobID), let image = try? PhotoProcessor.load(data) {
                        GeometryReader { geometry in
                            Image(decorative:image,scale:1).resizable().scaledToFill()
                                .frame(width:geometry.size.width,height:geometry.size.height).clipped()
                                .overlay {
                                    if let outline = job?.design?.candidates.first(where: { $0.id == selectedID }) {
                                        SubjectOutlineView(outline:outline)
                                    }
                                }
                        }.aspectRatio(0.75,contentMode:.fit).clipShape(RoundedRectangle(cornerRadius:14))
                    }
                    if let candidates = job?.design?.candidates {
                        Picker("选择主体轮廓",selection:$selectedID) {
                            Text("请选择").tag(Int?.none)
                            ForEach(Array(candidates.enumerated()),id:\.element.id) { index, outline in Text("主体 \(index+1)").tag(Optional(outline.id)) }
                        }
                    }
                    Toggle("主体身份、数量和重要细节与原照片一致",isOn:$identity)
                    Toggle("描边选对主体，角度与构图符合这条建议",isOn:$composition)
                    Toggle("现场可以完成这些机位和取景动作",isOn:$executable)
                    Text("如果不符合，可关闭并继续使用原构图模板，或重新生成参考图。").font(.caption).foregroundStyle(.secondary)
                    if let error { Text(error).font(.caption).foregroundStyle(.orange) }
                    Button("选用这个设计轮廓") {
                        guard let selectedID else { return }
                        do {
                            try controller.approveDesign(jobID:jobID,candidateID:selectedID,checks:.init(identity:identity,composition:composition,executable:executable))
                            dismiss()
                        } catch { self.error = "此参考图已更新或核对不完整，请关闭后重新打开。" }
                    }.buttonStyle(.borderedProminent).disabled(selectedID == nil || !identity || !composition || !executable)
                }.padding(20)
            }
            .navigationTitle("核对设计轮廓")
            .toolbar { ToolbarItem(placement:.cancellationAction) { Button("关闭") { dismiss() } } }
            .onAppear { selectedID = job?.design?.candidates.first?.id }
            .onChange(of:selectedID) { _,_ in identity = false; composition = false; executable = false }
        }
        .preferredColorScheme(.dark)
    }
}
#if os(iOS)
struct ReferenceZoomView: UIViewRepresentable {
    let data: Data
    let onDismiss: () -> Void
    func makeUIView(context:Context) -> PhotoScrollView {
        let view=PhotoScrollView(); view.imageView.image=UIImage(data:data)
        view.finishedDrag={ distance,velocity in if distance > 110 || velocity > 900 { onDismiss() } }
        return view
    }
    func updateUIView(_ view:PhotoScrollView,context:Context) {}
}
#endif
