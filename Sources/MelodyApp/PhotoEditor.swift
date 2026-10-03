import SwiftUI
import UniformTypeIdentifiers
import ImageIO
import MelodyImaging
import MelodyCore

struct JPEGDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.image] }
    var data: Data
    init(data:Data) { self.data = data }
    init(configuration:ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration:WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents:data) }
}
private struct PhotoPreview: Identifiable {
    let id = UUID()
    let data: Data
    let plan: ShotPlan?
    let outline: SubjectOutline?
    let showTemplate: Bool
    let photoIDs: [UUID]
    let initialID: UUID
    let useOriginal: Bool
}
struct PhotoEditor: View {
    @ObservedObject var studio: StudioModel
    @State private var settings = false
    @State private var exporting = false
    @State private var exportType: UTType = .jpeg
    @State private var document: JPEGDocument?
    @State private var name = "Melody-调色副本"
    @State private var section = 0
    @State private var showTemplate = false
    @State private var preview: PhotoPreview?
    @State private var viewerScale = 1.0
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:18) {
                photoStrip
                if let image = studio.compare ? studio.original : studio.edited {
                    Image(decorative:image,scale:1).resizable().scaledToFit()
                        .overlay {
                            if showTemplate, let plan = studio.followedPlan {
                                CompositionOverlay(subject:plan.subject,grid:false,opacity:0.8,showPerson:false)
                                if let outline = studio.followedOutline { SubjectOutlineView(outline:outline,target:plan.subject) }
                            }
                        }
                        .frame(maxWidth:.infinity,maxHeight:260)
                        .clipShape(RoundedRectangle(cornerRadius:18))
                        .contentShape(Rectangle())
                        .onTapGesture { openViewer() }
                        .accessibilityLabel("查看完整照片")
                    HStack {
                        Text("第 \(studio.currentPhotoNumber) 张 · \(studio.compare ? "原片" : studio.style.rawValue)").font(.caption)
                        Spacer()
                        if studio.followedPlan != nil {
                            Button { showTemplate.toggle() } label: { Image(systemName:showTemplate ? "square.on.square.fill" : "square.on.square") }
                                .accessibilityLabel(showTemplate ? "隐藏跟拍模板" : "显示跟拍模板")
                                .tint(showTemplate ? Color.melodyLime : .white)
                        }
                        Button { openViewer() } label: { Image(systemName:"arrow.up.left.and.arrow.down.right") }.accessibilityLabel("全屏查看照片")
                        Menu {
                            Button("保存原片") { save(original:true) }
                            Button("保存调色副本") { save(original:false) }
                        } label: { Image(systemName:"square.and.arrow.down") }.disabled(studio.savingPhoto).accessibilityLabel("保存到相册")
                    }.buttonStyle(.bordered)
                    if studio.savingPhoto { Text("正在保存到相册…").font(.caption).foregroundStyle(.secondary) }
                    else if studio.notice.contains("已保存到相册") { Text(studio.notice).font(.caption).foregroundStyle(Color.melodyLime) }
                    if showTemplate, studio.followedPlan != nil {
                        Text(studio.followedOutline == nil ? "跟拍模板 · 此记录无主体描边，仅显示目标范围" : "跟拍时的模板 · 仅叠加预览，保存照片不带描边").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Picker("项目工作区",selection:$section) { Text("推荐与模板").tag(0); Text("编辑照片").tag(1) }.pickerStyle(.segmented)
                if section == 0 { analysisPanel }
                else { editingPanel }
                if !studio.notice.isEmpty { Text(studio.notice).font(.caption).foregroundStyle(.secondary) }
            }.padding(18).frame(maxWidth:700).frame(maxWidth:.infinity)
        }.background(Color.melodyBackground)
        .safeAreaInset(edge:.bottom,spacing:0) { sessionActions }
        .sheet(isPresented:$settings) { ProviderSettings(studio:studio) }
        .onDisappear { studio.cancelPhotoAnalysis() }
        .onChange(of:studio.currentProject?.activePhotoID) { _,_ in showTemplate = false }
        #if os(iOS)
        .fullScreenCover(item:$preview) { item in
            PhotoViewer(studio:studio,photoIDs:item.photoIDs,currentID:item.initialID,useOriginal:item.useOriginal,showTemplate:item.showTemplate)
        }
        #else
        .sheet(item:$preview) { item in
            VStack {
                HStack { Text("照片预览"); Slider(value:$viewerScale,in:1...6); Button("完成") { preview = nil } }.padding()
                ScrollView([.horizontal,.vertical]) {
                    if let image = NSImage(data:item.data) {
                        Image(nsImage:image).resizable().scaledToFit().frame(width:600 * viewerScale)
                    }
                }
            }.frame(width:800,height:700)
        }
        #endif
        .fileExporter(isPresented:$exporting,document:document,contentType:exportType,defaultFilename:name) { result in
            switch result { case .success: studio.notice = "照片已导出。"; case .failure: studio.error = "照片导出失败，请重试。" }
        }
    }
    private var photoStrip: some View {
        VStack(alignment:.leading,spacing:10) {
            HStack {
                Text("项目照片").font(.subheadline.bold())
                Spacer()
                Text("重拍与选图都会保留旧照片").font(.caption2).foregroundStyle(.secondary)
            }
            if let project = studio.currentProject {
                ScrollView(.horizontal,showsIndicators:false) {
                    HStack(spacing:10) {
                        ForEach(Array(project.photos.enumerated()),id:\.element.id) { index, photo in
                            Button { Task { await studio.selectProjectPhoto(photo.id) } } label: {
                                VStack(spacing:6) {
                                ProjectThumbnail(studio:studio,projectID:project.id,photoID:photo.id).frame(width:68,height:80)
                                    .overlay(alignment:.bottomLeading) { Text("\(index+1)").font(.caption2.bold()).padding(5).background(.black.opacity(0.6),in:Capsule()).padding(4) }
                                    .clipShape(RoundedRectangle(cornerRadius:10))
                                    .overlay { RoundedRectangle(cornerRadius:10).stroke(photo.id == project.activePhotoID ? Color.melodyLime : .clear,lineWidth:2) }
                                Text(project.role(of:photo)).font(.caption2).foregroundStyle(photo.id == project.activePhotoID ? Color.melodyLime : .secondary)
                                }
                            }.buttonStyle(.plain).disabled(studio.busy).accessibilityLabel("打开项目第\(index+1)张照片，\(project.role(of:photo))，\(photo.recommendations.count)轮推荐")
                        }
                    }.padding(2)
                }
            }
        }
    }
    private var sessionActions: some View {
        VStack(spacing:10) {
            if studio.busy {
                HStack { Text(studio.progress).font(.caption); Spacer(); Button("取消") { studio.cancel() }.font(.caption) }
                ProgressView().progressViewStyle(.linear).tint(Color.melodyLime)
            }
            HStack(spacing:18) {
                Button { studio.retakeInProject() } label: { VStack(spacing:6) { Image(systemName:"camera.rotate"); Text("重新拍摄").font(.caption2) } }.disabled(studio.busy)
                SystemPhotoButton(studio:studio,compact:true)
                Button { section = 0; studio.analyzePhoto() } label: {
                    Label(studio.photoAnalysis == nil ? "生成推荐" : "再生成一轮",systemImage:"sparkles")
                        .font(.subheadline.bold()).frame(maxWidth:.infinity).padding(.vertical,14)
                        .background(Color.melodyLime,in:RoundedRectangle(cornerRadius:14)).foregroundStyle(Color.melodyBackground)
                }.disabled(studio.busy)
            }
        }.padding(.horizontal,20).padding(.vertical,14).background(Color.melodySurface)
    }
    private var analysisPanel: some View {
        VStack(alignment:.leading,spacing:16) {
            HStack {
                Picker("分析方式",selection:$studio.photoBackend) { ForEach(PhotoBackend.allCases,id:\.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.menu).disabled(studio.busy)
                Spacer()
                Button("模型设置") { settings = true }.font(.caption).disabled(studio.busy)
            }
            if studio.photoBackend == .online {
                Text("点击生成推荐才上传；原片与历史仅保存在本机。").font(.caption2).foregroundStyle(.secondary)
            } else { Text("本机 Gemma 完成照片分析。").font(.caption).foregroundStyle(.secondary) }
            ReferenceDestinationNotice(controller:studio.references)
            Picker("拍摄风格",selection:$studio.photographyStyle) {
                ForEach(PhotographyStyle.allCases,id:\.self) { Text($0.title).tag($0) }
            }.pickerStyle(.segmented).disabled(studio.busy)
                .onChange(of:studio.photographyStyle) { _,_ in studio.savePhotographyStyle() }
            Text("风格用于下一轮推荐；每个方案会说明摄影依据、操作顺序与适用条件。").font(.caption2).foregroundStyle(.secondary)
            if studio.photoSource == .demo { Text("当前是演示画面，不是真实拍摄。").font(.caption).foregroundStyle(.orange) }
            if !studio.recommendationBatches.isEmpty {
                HStack {
                    Text("历次推荐").font(.subheadline.bold())
                    Spacer()
                    Menu {
                        ForEach(Array(studio.recommendationBatches.enumerated()),id:\.element.id) { index, batch in
                            Button("第 \(index+1) 轮 · \(batch.createdAt.formatted(date:.omitted,time:.shortened))") { studio.chooseRecommendationBatch(batch.id) }
                        }
                    } label: {
                        let index = studio.recommendationBatches.firstIndex { $0.id == studio.currentProject?.activePhoto?.selectedBatchID } ?? 0
                        Label("第 \(index+1) 轮 / 共 \(studio.recommendationBatches.count) 轮",systemImage:"chevron.down").font(.caption)
                    }.disabled(studio.busy)
                }
            }
            if let report = studio.photoAnalysis {
                Text(report.subjectName ?? "这张照片的拍摄建议").font(.title3.bold())
                Text(report.summary).font(.subheadline).foregroundStyle(.secondary)
                Label(report.nextStep,systemImage:"arrow.turn.up.right").font(.subheadline).foregroundStyle(Color.melodyLime)
                DisclosureGroup("查看详细照片分析") {
                    VStack(alignment:.leading,spacing:14) {
                        analysisSection("光线",report.observations.light)
                        analysisSection("构图与留白",report.observations.composition)
                        analysisSection("背景与层次",report.observations.background)
                        analysisSection("主体姿态与摆放",report.observations.pose)
                        analysisSection("成像细节",report.observations.quality)
                        analysisSection("判断边界",report.limitations)
                    }.padding(.top,12)
                }.font(.subheadline)
                Text(studio.photoAnalysisSource).font(.caption2).foregroundStyle(.secondary)
                outlinePanel
                Text("选一个模板，开始跟拍").font(.headline)
                ForEach(report.plans) { plan in
                    VStack(alignment:.leading,spacing:12) {
                        HStack { Text(plan.title).font(.headline); Spacer(); Text("\(plan.zoom.formatted())×").foregroundStyle(Color.melodyLime) }
                        ShotTemplatePreview(plan:plan,outline:studio.selectedOutline)
                        Text(plan.instruction).font(.subheadline)
                        Text(plan.reason).font(.caption).foregroundStyle(.secondary)
                        if let design = plan.design {
                            VStack(alignment:.leading,spacing:6) {
                                ForEach(Array(design.steps.enumerated()),id:\.offset) { index, step in Text("\(index+1). \(step)").font(.caption) }
                            }
                            DisclosureGroup("摄影依据与适用条件") {
                                VStack(alignment:.leading,spacing:8) {
                                    ForEach(design.warnings,id:\.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                                    if let card = PhotographyKnowledge.card(design.techniqueID) {
                                        ForEach(card.sources,id:\.url) { source in
                                            if let url = URL(string:source.url) { Link(source.title,destination:url).font(.caption) }
                                        }
                                    }
                                    Text("知识规则 \(design.knowledgeVersion) · \(design.style.title) · 不是审美评分").font(.caption2).foregroundStyle(.secondary)
                                }.padding(.top,8)
                            }.font(.caption)
                        }
                        if let project=studio.currentProject,let photo=project.activePhoto,let batch=photo.selectedBatch {
                            ReferenceCard(controller:studio.references,request:ReferenceImageRequest(projectID:project.id,photoID:photo.id,batchID:batch.id,plan:plan)) { retry in studio.generateReference(plan,retry:retry) }
                        }
                        Button { studio.applyPhotoPlan(plan) } label: {
                            Label("按这个模板拍摄",systemImage:"camera.fill").font(.subheadline.bold()).frame(maxWidth:.infinity).padding(12)
                        }.buttonStyle(.bordered).tint(Color.melodyLime).disabled(studio.busy || studio.outlining)
                    }.padding(16).background(Color.melodySurface,in:RoundedRectangle(cornerRadius:20))
                }
            } else {
                VStack(alignment:.leading,spacing:12) {
                    Image(systemName:"sparkles.rectangle.stack").font(.title).foregroundStyle(Color.melodyLime)
                    Text("从这张照片，找到下一张的拍法").font(.headline)
                    Text("生成建议后，选择模板回到相机。跟拍的新照片和每一轮推荐都会留在这个项目里。").font(.subheadline).foregroundStyle(.secondary)
                }.padding(20).frame(maxWidth:.infinity,alignment:.leading).background(Color.melodySurface,in:RoundedRectangle(cornerRadius:20))
                outlinePanel
            }
        }
    }
    private var editingPanel: some View {
        VStack(alignment:.leading,spacing:18) {
            Text("自然调色").font(.headline)
            Picker("调色风格",selection:$studio.style) { ForEach(ColorStyle.allCases,id:\.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
                .onChange(of:studio.style) { _,_ in studio.updateEdit() }
            HStack {
                Text("强度").font(.caption)
                Slider(value:$studio.amount,in:0...1).tint(Color.melodyLime).onChange(of:studio.amount) { _,_ in studio.updateEdit() }
                Text("\(Int(studio.amount*100))%").font(.caption).monospacedDigit().frame(width:40)
            }
            Toggle("对比原片",isOn:$studio.compare).tint(Color.melodyLime)
            HStack {
                Button("保存原片") { save(original:true) }.buttonStyle(.bordered)
                Spacer()
                Button("保存调色副本") { save(original:false) }.buttonStyle(.borderedProminent).tint(Color.melodyLime).foregroundStyle(Color.melodyBackground)
            }
            Text("调色配方会自动保存在当前照片中。保存副本不覆盖原片。").font(.caption).foregroundStyle(.secondary)
        }.disabled(studio.busy)
    }
    private func analysisSection(_ title:String,_ text:String) -> some View {
        VStack(alignment:.leading,spacing:5) { Text(title).font(.subheadline.bold()); Text(verbatim:text).font(.subheadline).foregroundStyle(.secondary) }
    }
    private var outlinePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("主体轮廓模板").font(.title3.bold())
                Spacer()
                Button("重新提取") { if let image = studio.original { studio.extractSubjectOutlines(image) } }.disabled(studio.outlining || studio.busy)
            }
            if studio.outlining { ProgressView("正在本机提取主体轮廓") }
            Text(studio.outlineNotice).font(.caption).foregroundStyle(.secondary)
            if let image = studio.original, let outline = studio.selectedOutline {
                ZStack {
                    Image(decorative: image, scale: 1).resizable().scaledToFit().opacity(0.65)
                    SubjectOutlineView(outline: outline)
                }.aspectRatio(CGFloat(image.width)/CGFloat(image.height), contentMode: .fit)
                    .frame(maxHeight: 260).clipShape(RoundedRectangle(cornerRadius: 12))
                Text("当前照片 · 实际分割轮廓；主体选择用于下一轮推荐").font(.caption).foregroundStyle(Color.melodyLime)
                if studio.subjectOutlines.count > 1 {
                    ScrollView(.horizontal) {
                        HStack {
                            ForEach(Array(studio.subjectOutlines.enumerated()), id: \.element.id) { index, candidate in
                                Button("主体 \(index + 1)") { studio.chooseOutline(candidate.id) }
                                    .buttonStyle(.bordered).tint(studio.selectedOutlineID == candidate.id ? Color.melodyLime : .gray).disabled(studio.busy)
                            }
                        }
                    }
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func openViewer() {
        do { preview = PhotoPreview(data:try studio.exportData(original:studio.compare),plan:studio.followedPlan,outline:studio.followedOutline,showTemplate:showTemplate,photoIDs:studio.currentProject?.photos.map(\.id) ?? [],initialID:studio.currentProject?.activePhotoID ?? UUID(),useOriginal:studio.compare); viewerScale = 1 }
        catch { studio.error = error.localizedDescription }
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
