import Foundation
import MelodyCore
#if os(iOS) && !targetEnvironment(simulator) && canImport(_MediaGenerationKit)
import _MediaGenerationKit
#endif

enum PhoneReferenceFailure: LocalizedError {
    case unavailable, modelsMissing
    var errorDescription: String? {
        switch self {
        case .unavailable: return "本地参考图需要装有 Draw Things 引擎的 iPhone 真机版本；模板仍可跟拍。"
        case .modelsMissing: return "手机上的 Qwen 模型尚未完整安装，请等待模型传输完成；模板仍可跟拍。"
        }
    }
}

/// 手机只启动本地引擎；没有 Mac、远程地址或云端回退路径。
struct PhoneReferenceProvider: ReferenceImageGenerating {
    static let model = "qwen_image_edit_2511_q6p.ckpt"
    static let lightning = "qwen_image_edit_2511_lightning_4_step_v1.0_lora_f16.ckpt"
    static var directory: URL {
        FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("DrawThingsModels",isDirectory:true)
    }
    // 完整权重与分离 tensor 文件都必须存在，不能把复制中的文件当作安装完成。
    static let requiredFiles: [(String, Int64)] = [
        ("custom_lora.json", 249),
        ("qwen_2.5_vl_7b_q8p.ckpt", 540672),
        ("qwen_2.5_vl_7b_q8p.ckpt-tensordata", 7820795904),
        ("qwen_2.5_vl_7b_vit_f16.ckpt", 1531904),
        ("qwen_2.5_vl_7b_vit_f16.ckpt-tensordata", 1353056256),
        ("qwen_image_edit_2511_lightning_4_step_v1.0_lora_f16.ckpt", 846954496),
        ("qwen_image_edit_2511_q6p.ckpt", 8495104),
        ("qwen_image_edit_2511_q6p.ckpt-tensordata", 17581375488),
        ("qwen_image_vae_f16.ckpt", 254500864),
    ]
    // 同一固定 SDK 首次运行将 VAE 的 SQLite 权重拆成元数据 + tensor 文件。
    static let optimizedVAEFiles: [(String,Int64)] = [
        ("qwen_image_vae_f16.ckpt",131_072),
        ("qwen_image_vae_f16.ckpt-tensordata",254_001_152)
    ]
    static func installationFraction(fileSizes:[String:Int64]) -> Double {
        let expected=requiredFiles.reduce(Int64(0)) { $0+$1.1 }
        let optimized=optimizedVAEFiles.allSatisfy { (fileSizes[$0.0] ?? 0) >= $0.1 }
        let present=requiredFiles.reduce(Int64(0)) { total,file in
            if file.0 == "qwen_image_vae_f16.ckpt",optimized { return total+file.1 }
            return total+min(max(fileSizes[file.0] ?? 0,0),file.1)
        }
        return Double(present)/Double(expected)
    }
    static var installationFraction: Double {
        let names=Set((requiredFiles+optimizedVAEFiles).map { $0.0 })
        let sizes=Dictionary(uniqueKeysWithValues:names.map { name in
            let bytes=(try? directory.appendingPathComponent(name).resourceValues(forKeys:[.fileSizeKey]).fileSize) ?? 0
            return (name,Int64(bytes))
        })
        return installationFraction(fileSizes:sizes)
    }
    static var modelStatus: String {
        let fraction=installationFraction
        if fraction == 0 { return "尚未安装手机 Qwen 模型 · 约 28 GB" }
        if fraction == 1 { return "手机模型已安装 · Qwen Image Edit 2511 + 4 步 Lightning" }
        return "手机模型文件已就绪 \(Int(fraction*100))% · 尚未完整安装"
    }
    func generate(_ request:ReferenceImageRequest,jpeg:Data,progress:@escaping @Sendable (ReferenceRemoteStatus) async -> Void) async throws -> Data {
        _ = try request.validated()
        #if os(iOS) && !targetEnvironment(simulator) && canImport(_MediaGenerationKit)
        guard Self.installationFraction == 1 else { throw PhoneReferenceFailure.modelsMissing }
        await progress(.init(id:request.id,state:.queued,stage:"等待手机完成前一个模型任务"))
        try await PhoneModelGate.shared.acquire()
        do {
            let result=try await generateLocally(request,jpeg:jpeg,progress:progress)
            await PhoneModelGate.shared.release()
            return result
        } catch {
            await PhoneModelGate.shared.release()
            throw error
        }
        #else
        throw PhoneReferenceFailure.unavailable
        #endif
    }
    #if os(iOS) && !targetEnvironment(simulator) && canImport(_MediaGenerationKit)
    private func generateLocally(_ request:ReferenceImageRequest,jpeg:Data,progress:@escaping @Sendable (ReferenceRemoteStatus) async -> Void) async throws -> Data {
        try Task.checkCancellation()
        await progress(.init(id:request.id,state:.running,stage:"正在加载手机模型"))
        var folder=Self.directory; var values=URLResourceValues(); values.isExcludedFromBackup=true
        try folder.setResourceValues(values)
        return try await DrawThingsPhoneEngine.generate(request,jpeg:jpeg,progress:progress)
    }
    #endif
}

/// Actor 本身会在 await 时重入，显式占用避免多个大型模型并行加载。
actor PhoneModelGate {
    static let shared=PhoneModelGate()
    private var occupied=false
    private var waiting: [UUID] = []
    var isOccupied: Bool { occupied }
    func acquire() async throws {
        let ticket=UUID(); waiting.append(ticket)
        do {
            while occupied || waiting.first != ticket { try await Task.sleep(for:.milliseconds(200)) }
            try Task.checkCancellation()
            waiting.removeFirst(); occupied=true
        } catch {
            waiting.removeAll { $0 == ticket }
            throw error
        }
    }
    func release() { occupied=false }
}
