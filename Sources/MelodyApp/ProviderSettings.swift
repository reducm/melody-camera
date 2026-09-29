import SwiftUI

struct ProviderSettings: View {
    @ObservedObject var studio: StudioModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment:.leading,spacing:20) {
            HStack { Text("模型与隐私").font(.title2); Spacer(); Button("完成") { studio.saveSettings(); dismiss() } }
            ScrollView {
                VStack(alignment:.leading,spacing:16) {
                    Text("在线视觉模型").font(.headline)
                    Text("使用支持图像输入的 OpenAI Chat Completions 兼容接口。请按服务商文档填写根地址（如 https://服务域名/v1），不要包含 /chat/completions。").font(.caption).foregroundStyle(.secondary)
                    field("接口根地址",value:$studio.baseURL,prompt:"https://…/v1")
                    field("视觉模型名称",value:$studio.modelName,prompt:"填写控制台中的视觉模型 ID")
                    VStack(alignment:.leading,spacing:6) { Text("API Key").font(.caption); SecureField("只保存到本机钥匙串",text:$studio.apiKey).textFieldStyle(.roundedBorder) }
                    Text("GLM / Kimi / DeepSeek 等品牌名不等于视觉能力。请确认具体模型支持 image_url、JSON 文本输出及相应接口；本版未逐一完成服务商实测。").font(.caption).foregroundStyle(.secondary)
                    Toggle("允许本次会话上传取景缩略图",isOn:$studio.uploadEnabled).tint(Color.melodyLime)
                    Text("仅在点击「AI 看看怎么拍」时上传最多 3 张压缩图。模型服务可能按自己的政策保留数据并计费。关闭应用后需重新开启。不会自动在失败后改用其他服务。").font(.caption).foregroundStyle(.secondary)
                    Divider()
                    Label("端侧 Gemma · 规划中",systemImage:"iphone.gen3").font(.headline)
                    Text("Google AI Edge Gallery 已提供 iOS 体验，LiteRT-LM Swift 支持多模态。后续将增加独立端侧适配器，并先验证内存、速度和发热。当前「离线构图」是摄影规则，不是已经安装的 Gemma。").font(.caption).foregroundStyle(.secondary)
                    Button("清除已保存的密钥") { studio.apiKey = ""; studio.saveSettings() }.foregroundStyle(Color.melodyLime)
                }
            }
        }.padding(24).frame(idealWidth:520,idealHeight:600).background(Color.melodyBackground).preferredColorScheme(.dark)
    }
    private func field(_ title: String,value: Binding<String>,prompt: String) -> some View {
        VStack(alignment:.leading,spacing:6) { Text(title).font(.caption); TextField(prompt,text:value).textFieldStyle(.roundedBorder).autocorrectionDisabled() }
    }
}
