import SwiftUI
import MelodyImaging

struct DiagnosticLogView: View {
    @ObservedObject var references: ReferenceGenerationController
    @Environment(\.dismiss) private var dismiss
    @AppStorage(DiagnosticLog.detailsPreference) private var modelDetails = true
    @State private var snapshot = DiagnosticSnapshot(entries: [], bytes: 0, storageError: nil)
    @State private var level: DiagnosticLevel?
    @State private var category: DiagnosticCategory?
    @State private var confirmClear = false
    @State private var clearing = false
    @State private var selected: DiagnosticEntry?
    private var filtered: [DiagnosticEntry] {
        snapshot.entries.filter { (level == nil || $0.level == level) && (category == nil || $0.category == category) }
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("记录模型输入与输出", isOn: $modelDetails)
                    Text("可展开查看提示词、模型返回文字和生成图结果。文字可能包含照片内容描述；仅保存在此设备，不上传。关闭后停止记录新的模型正文，已有记录可清理。")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Picker("级别", selection: $level) {
                            Text("全部级别").tag(DiagnosticLevel?.none)
                            ForEach(DiagnosticLevel.allCases, id: \.self) { Text($0.rawValue).tag(Optional($0)) }
                        }
                        Picker("功能", selection: $category) {
                            Text("全部功能").tag(DiagnosticCategory?.none)
                            ForEach(DiagnosticCategory.allCases, id: \.self) { Text($0.rawValue).tag(Optional($0)) }
                        }
                    }.pickerStyle(.menu)
                    Text("\(filtered.count) / \(snapshot.entries.count) 条 · \(ByteCountFormatter.string(fromByteCount: Int64(snapshot.bytes), countStyle: .file)) · 最新在前")
                        .font(.caption).foregroundStyle(.secondary)
                    if let error = snapshot.storageError { Text(error).foregroundStyle(.orange).font(.caption) }
                }
                Section {
                    if filtered.isEmpty {
                        ContentUnavailableView(snapshot.entries.isEmpty ? "暂无日志" : "没有匹配的日志", systemImage: "doc.text.magnifyingglass", description: Text("使用相机或生成推荐后，这里会显示新的运行记录。"))
                    }
                    ForEach(filtered) { entry in
                        Button { selected = entry } label: {
                            VStack(alignment: .leading, spacing: 7) {
                                HStack {
                                    Text(entry.level.rawValue).font(.caption.monospaced().bold()).foregroundStyle(entry.level.color)
                                    Text(entry.category.rawValue).font(.caption).foregroundStyle(.secondary)
                                    Spacer()
                                    Text(entry.date, format: .dateTime.hour().minute().second()).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                }
                                HStack { Text(verbatim: entry.message).font(.subheadline).foregroundStyle(.primary); Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary) }
                            }.padding(.vertical, 3)
                        }.buttonStyle(.plain)
                    }
                } footer: {
                    Text("保留最近 7 天，最多 500 条 / 2 MB；单条正文最多 32 KB，超出会标注截断。不会记录密钥、图像正文或 EXIF 定位。清理仅移除这里的本机记录；iOS 系统诊断由系统管理。正在运行的任务可能继续产生新日志。")
                }
            }
            .navigationTitle("诊断日志")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button("清理", systemImage: "trash", role: .destructive) { confirmClear = true }
                        .disabled(clearing || (snapshot.entries.isEmpty && snapshot.storageError == nil))
                        .accessibilityLabel("清理日志")
                }
            }
            .confirmationDialog("清理此设备的全部日志？", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("清理全部日志", role: .destructive) {
                    clearing = true
                    Task { snapshot = await DiagnosticLog.shared.clear(); selected = nil; clearing = false }
                }
                Button("取消", role: .cancel) {}
            } message: { Text("包含当前筛选外的记录。不会删除照片、项目或模型。") }
            .refreshable { snapshot = await DiagnosticLog.shared.snapshot() }
            .task {
                while !Task.isCancelled {
                    let updated = await DiagnosticLog.shared.snapshot()
                    if updated != snapshot { snapshot = updated }
                    do { try await Task.sleep(for: .seconds(2)) } catch { break }
                }
            }
            .sheet(item: $selected) { entry in
                DiagnosticEntryView(entry: entry, references: references,
                    related: snapshot.entries.filter { entry.operationID != nil && $0.operationID == entry.operationID }.reversed())
            }
        }.preferredColorScheme(.dark).frame(idealWidth: 640, idealHeight: 720)
    }
}

private struct DiagnosticEntryView: View {
    let entry: DiagnosticEntry
    @ObservedObject var references: ReferenceGenerationController
    let related: [DiagnosticEntry]
    @Environment(\.dismiss) private var dismiss
    @State private var preview = false
    @State private var imageData: Data?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text(entry.date, format: .dateTime.year().month().day().hour().minute().second()).font(.caption).foregroundStyle(.secondary)
                    if let id = entry.operationID { Text("调用编号：\(id.uuidString)").font(.caption.monospaced()).textSelection(.enabled) }
                    ForEach(related.isEmpty ? [entry] : related) { item in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack { Text(item.level.rawValue).foregroundStyle(item.level.color); Text(verbatim: item.message).bold() }.font(.subheadline)
                            Text(item.date, format: .dateTime.hour().minute().second()).font(.caption).foregroundStyle(.secondary)
                            Text(verbatim: item.detail ?? "未记录正文。").font(.system(.footnote, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Divider()
                    }
                    if let imageData, let image = try? PhotoProcessor.load(imageData, maxPixel: 768) {
                        Text("AI 生成结果 · 非实拍").font(.headline)
                        Button { preview = true } label: { Image(decorative: image, scale: 1).resizable().scaledToFit() }.accessibilityLabel("放大日志关联的生成图")
                        Text("读取原参考图，日志中没有另存图片；清理日志会保留这张图。").font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(20)
            }.navigationTitle("调用详情")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .task { if entry.category == .reference, let id = entry.operationID { imageData = references.imageData(id) } }
            .sheet(isPresented: $preview) {
                VStack {
                    HStack { Text("AI 生成参考 · 非实拍"); Spacer(); Button("完成") { preview = false } }.padding()
                    if let imageData {
                        #if os(iOS)
                        ReferenceZoomView(data: imageData, onDismiss: { preview = false })
                        #else
                        if let image = NSImage(data: imageData) { Image(nsImage: image).resizable().scaledToFit() }
                        #endif
                    }
                }.background(.black).preferredColorScheme(.dark)
            }
        }.frame(idealWidth: 640, idealHeight: 720)
    }
}
private extension DiagnosticLevel {
    var color: Color {
        switch self { case .debug: return .secondary; case .info: return .blue; case .warning: return .orange; case .error: return .red }
    }
}
