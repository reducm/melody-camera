import SwiftUI
import UniformTypeIdentifiers

struct ProviderSettings: View {
    @ObservedObject var studio: StudioModel
    @State private var importingModel = false
    @State private var showingLogs = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment:.leading,spacing:20) {
            HStack { Text("设置").font(.title2); Spacer(); Button("完成") { studio.saveSettings(); studio.references.saveSettings(); dismiss() } }
            ScrollView {
                VStack(alignment:.leading,spacing:16) {
                    Button { showingLogs = true } label: {
                        HStack { Label("诊断日志", systemImage: "doc.text.magnifyingglass"); Spacer(); Text("查看与清理").font(.caption); Image(systemName: "chevron.right").font(.caption) }
                    }.padding(.vertical, 6)
                    Divider()
                    Picker("照片分析方式", selection: $studio.photoBackend) {
                        ForEach(PhotoBackend.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented).disabled(studio.busy)
                    Text("在线视觉模型").font(.headline)
                    Button("使用 DeepSeek Flash 官方接口") {
                        studio.baseURL = "https://api.deepseek.com"; studio.modelName = "deepseek-flash"
                    }.disabled(studio.busy)
                    Text("使用支持图像输入的 OpenAI Chat Completions 兼容接口。请按服务商文档填写根地址（如 https://服务域名/v1），不要包含 /chat/completions。").font(.caption).foregroundStyle(.secondary)
                    field("接口根地址",value:$studio.baseURL,prompt:"https://…/v1")
                    field("视觉模型名称",value:$studio.modelName,prompt:"填写控制台中的视觉模型 ID")
                    VStack(alignment:.leading,spacing:6) { Text("API Key").font(.caption); SecureField("只保存到本机钥匙串",text:$studio.apiKey).textFieldStyle(.roundedBorder) }
                    Text("DeepSeek Flash 已用公开样图验证图像输入。其他兼容服务需要支持 image_url 与 JSON 输出，不会自动切换服务。").font(.caption).foregroundStyle(.secondary)
                    Text("选择在线模型后，点击生成推荐才上传当前照片的压缩图。原片与历史保存在本机；服务商可能保留数据并计费。选择本机 Gemma 不上传照片，也不会在失败后自动切换服务。").font(.caption).foregroundStyle(.secondary)
                    Divider()
                    ReferenceSettings(controller:studio.references)
                    Divider()
                    Label("端侧 Gemma 4 E2B",systemImage:"iphone.gen3").font(.headline)
                    Text(studio.localModelStatus).font(.caption).foregroundStyle(.secondary)
                    Text("使用 Google LiteRT-LM 在设备上处理照片，不需要 API Key 或上传许可。首次需要导入约 2.59 GB 的指定模型；安装时校验完整 SHA-256。推理速度与可用内存以真机为准。").font(.caption).foregroundStyle(.secondary)
                    Link("下载指定 Gemma 模型", destination: URL(string: "https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/6e5c4f1/gemma-4-E2B-it.litertlm")!)
                    Button(studio.installingModel ? "正在校验模型…" : "导入 Gemma 模型文件") { importingModel = true }.disabled(studio.busy)
                    Text("主体描边始终由 Apple Vision 在本机提取。Gemma 与在线模型负责照片观察和模板建议；离线构图仍是摄影规则。").font(.caption).foregroundStyle(.secondary)
                    Button("清除已保存的密钥") { studio.apiKey = ""; studio.saveSettings() }.foregroundStyle(Color.melodyLime)
                }
            }
        }.padding(24).frame(idealWidth:520,idealHeight:600).background(Color.melodyBackground).preferredColorScheme(.dark)
        .sheet(isPresented: $showingLogs) { DiagnosticLogView(references: studio.references) }
        .fileImporter(isPresented: $importingModel, allowedContentTypes: [.data]) { result in
            switch result {
            case .success(let url): studio.installLocalModel(url)
            case .failure: studio.error = "无法打开模型文件，请重试。"
            }
        }
    }
    private func field(_ title: String,value: Binding<String>,prompt: String) -> some View {
        VStack(alignment:.leading,spacing:6) { Text(title).font(.caption); TextField(prompt,text:value).textFieldStyle(.roundedBorder).autocorrectionDisabled() }
    }
}
