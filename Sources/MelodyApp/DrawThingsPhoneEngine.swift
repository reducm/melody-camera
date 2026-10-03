// Tokenizer/generator factory adapted from Draw Things MediaGenerationExecutionUtilities.swift.
// Copyright Draw Things contributors; GPL-3.0. Upstream revision b5e9fb925ca5394b747e0e98a8c293bbab5091ca.
// Local adaptation: explicitly stream weights on iPhone; do not use remote model catalogs.
#if os(iOS) && !targetEnvironment(simulator) && canImport(_MediaGenerationKit)
import Foundation
import BinaryResources
import DataModels
import Dflat
import Diffusion
import ImageGenerator
import LocalImageGenerator
import ModelZoo
import NNC
import SQLiteDflat
import Tokenizer
import MelodyCore

private enum PhoneDrawThingsFactory {
    static func make(queue:DispatchQueue,directory:URL) -> LocalImageGenerator {
        let workspace=SQLiteWorkspace(filePath:directory.appendingPathComponent("config.sqlite3").path,fileProtectionLevel:.noProtection)
        // 免费签名无扩展虚拟地址空间：所有大型权重按需加载，避免整模型映射。
        workspace.dictionary["external_store_v2"] = JITWeightsLoading.alwaysFully.rawValue
        let configurations=workspace.fetch(for:GenerationConfiguration.self).where(GenerationConfiguration.id == 0,limit:.limit(0))
    let tokenizerV1 = TextualInversionAttentionCLIPTokenizer(
      vocabulary: BinaryResources.vocab_json,
      merges: BinaryResources.merges_txt,
      textualInversions: [])
    let tokenizerV2 = TextualInversionAttentionCLIPTokenizer(
      vocabulary: BinaryResources.vocab_16e6_json,
      merges: BinaryResources.bpe_simple_vocab_16e6_txt,
      textualInversions: [])
    let tokenizerKandinsky = SentencePieceTokenizer(
      data: BinaryResources.xlmroberta_bpe_model, startToken: 0,
      endToken: 2, tokenShift: 1)
    let tokenizerXL = tokenizerV2
    let tokenizerT5 = SentencePieceTokenizer(
      data: BinaryResources.t5_spiece_model, startToken: nil,
      endToken: 1, tokenShift: 0)
    let tokenizerPileT5 = SentencePieceTokenizer(
      data: BinaryResources.pile_t5_spiece_model, startToken: nil,
      endToken: 2, tokenShift: 0)
    let tokenizerChatGLM3 = SentencePieceTokenizer(
      data: BinaryResources.chatglm3_spiece_model, startToken: nil,
      endToken: nil, tokenShift: 0)
    let tokenizerLlama3 = TiktokenTokenizer(
      vocabulary: BinaryResources.vocab_llama3_json, merges: BinaryResources.merges_llama3_txt,
      specialTokens: [
        "<|start_header_id|>": 128006, "<|end_header_id|>": 128007, "<|eot_id|>": 128009,
        "<|begin_of_text|>": 128000, "<|end_of_text|>": 128001,
      ], unknownToken: "<|end_of_text|>", startToken: "<|begin_of_text|>",
      endToken: "<|end_of_text|>")
    let tokenizerUMT5 = SentencePieceTokenizer(
      data: BinaryResources.umt5_spiece_model, startToken: nil,
      endToken: 1, tokenShift: 0)
    let tokenizerQwen25 = TiktokenTokenizer(
      vocabulary: BinaryResources.vocab_qwen2_5_json, merges: BinaryResources.merges_qwen2_5_txt,
      specialTokens: [
        "</tool_call>": 151658, "<tool_call>": 151657, "<|box_end|>": 151649,
        "<|box_start|>": 151648,
        "<|endoftext|>": 151643, "<|file_sep|>": 151664, "<|fim_middle|>": 151660,
        "<|fim_pad|>": 151662, "<|fim_prefix|>": 151659, "<|fim_suffix|>": 151661,
        "<|im_end|>": 151645, "<|im_start|>": 151644, "<|image_pad|>": 151655,
        "<|object_ref_end|>": 151647, "<|object_ref_start|>": 151646, "<|quad_end|>": 151651,
        "<|quad_start|>": 151650, "<|repo_name|>": 151663, "<|video_pad|>": 151656,
        "<|vision_end|>": 151653, "<|vision_pad|>": 151654, "<|vision_start|>": 151652,
      ], unknownToken: "<|endoftext|>", startToken: "<|endoftext|>", endToken: "<|endoftext|>")
    let tokenizerQwen3 = TiktokenTokenizer(
      vocabulary: BinaryResources.vocab_qwen3_json, merges: BinaryResources.merges_qwen3_txt,
      specialTokens: [
        "<|endoftext|>": 151643, "<|im_start|>": 151644, "<|im_end|>": 151645,
        "<|object_ref_start|>": 151646, "<|object_ref_end|>": 151647, "<|box_start|>": 151648,
        "<|box_end|>": 151649, "<|quad_start|>": 151650, "<|quad_end|>": 151651,
        "<|vision_start|>": 151652, "<|vision_end|>": 151653, "<|vision_pad|>": 151654,
        "<|image_pad|>": 151655, "<|video_pad|>": 151656, "<tool_call>": 151657,
        "</tool_call>": 151658, "<|fim_prefix|>": 151659, "<|fim_middle|>": 151660,
        "<|fim_suffix|>": 151661, "<|fim_pad|>": 151662, "<|repo_name|>": 151663,
        "<|file_sep|>": 151664, "<tool_response>": 151665, "</tool_response>": 151666,
        "<think>": 151667, "</think>": 151668, "<|boi_token|>": 151669,
        "<|bor_token|>": 151670, "<|eor_token|>": 151671, "<|bot_token|>": 151672,
        "<|tms_token|>": 151673,
      ], unknownToken: "<|endoftext|>", startToken: "<|endoftext|>", endToken: "<|endoftext|>")
    let tokenizerQwen3MinimaxH3 = TiktokenTokenizer(
      vocabulary: BinaryResources.vocab_qwen3_json, merges: BinaryResources.merges_qwen3_txt,
      specialTokens: [
        "<|endoftext|>": 151643, "<|im_start|>": 151644, "<|im_end|>": 151645,
        "<|object_ref_start|>": 151646, "<|object_ref_end|>": 151647, "<|box_start|>": 151648,
        "<|box_end|>": 151649, "<|quad_start|>": 151650, "<|quad_end|>": 151651,
        "<|vision_start|>": 151652, "<|vision_end|>": 151653, "<|vision_pad|>": 151654,
        "<|image_pad|>": 151655, "<|video_pad|>": 151656, "<tool_call>": 151657,
        "</tool_call>": 151658, "<|fim_prefix|>": 151659, "<|fim_middle|>": 151660,
        "<|fim_suffix|>": 151661, "<|fim_pad|>": 151662, "<|repo_name|>": 151663,
        "<|file_sep|>": 151664, "<tool_response>": 151665, "</tool_response>": 151666,
        "<think>": 151667, "</think>": 151668,
        "<d>": 151669, "</d>": 151670, "<|cutoff|>": 151671,
        "<|lyrics_start|>": 151672, "<|lyrics_end|>": 151673,
        "<|caption_start|>": 151674, "<|caption_end|>": 151675,
      ], unknownToken: "<|endoftext|>", startToken: "<|endoftext|>", endToken: "<|endoftext|>")
    let tokenizerMistral3 = TiktokenTokenizer(
      vocabulary: BinaryResources.vocab_mistral3_json, merges: BinaryResources.merges_mistral3_txt,
      specialTokens: [
        "<unk>": 0, "<s>": 1, "</s>": 2, "[INST]": 3, "[/INST]": 4, "[AVAILABLE_TOOLS]": 5,
        "[/AVAILABLE_TOOLS]": 6, "[TOOL_RESULTS]": 7, "[/TOOL_RESULTS]": 8, "[TOOL_CALLS]": 9,
        "[IMG]": 10, "<pad>": 11, "[IMG_BREAK]": 12, "[IMG_END]": 13, "[PREFIX]": 14,
        "[MIDDLE]": 15,
        "[SUFFIX]": 16, "[SYSTEM_PROMPT]": 17, "[/SYSTEM_PROMPT]": 18, "[TOOL_CONTENT]": 19,
      ], unknownToken: "<unk>", startToken: "<s>", endToken: "</s>")
    let tokenizerGemma3 = SentencePieceTokenizer(
      data: BinaryResources.gemma3_spiece_model, startToken: 2, endToken: nil, tokenShift: 0)

    let generator = LocalImageGenerator(
      queue: queue, configurations: configurations, workspace: workspace, tokenizerV1: tokenizerV1,
      tokenizerV2: tokenizerV2, tokenizerXL: tokenizerXL, tokenizerKandinsky: tokenizerKandinsky,
      tokenizerT5: tokenizerT5, tokenizerPileT5: tokenizerPileT5,
      tokenizerChatGLM3: tokenizerChatGLM3, tokenizerLlama3: tokenizerLlama3,
      tokenizerUMT5: tokenizerUMT5, tokenizerQwen25: tokenizerQwen25,
      tokenizerQwen3: tokenizerQwen3, tokenizerQwen3MinimaxH3: tokenizerQwen3MinimaxH3,
      tokenizerMistral3: tokenizerMistral3,
      tokenizerGemma3: tokenizerGemma3
    )

        return generator
    }
}

/// Only the pinned official engine's local API is used. No catalog fetch or remote fallback.
enum DrawThingsPhoneEngine {
    static func generate(_ request:ReferenceImageRequest,jpeg:Data,progress:@escaping @Sendable (ReferenceRemoteStatus) async -> Void) async throws -> Data {
        let cancellation=PhoneEngineCancellation()
        let events=AsyncStream<ReferenceRemoteStatus>.makeStream()
        let consumer=Task { for await status in events.stream { await progress(status) } }
        do {
            let data:Data=try await withTaskCancellationHandler {
                try Task.checkCancellation()
                return try await withCheckedThrowingContinuation { continuation in
                    let queue=DispatchQueue(label:"com.melody.phone-reference",qos:.userInitiated)
                    queue.async {
                        let cache=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                        defer { cancellation.clear(); try? FileManager.default.removeItem(at:cache) }
                        do {
                            try FileManager.default.createDirectory(at:cache,withIntermediateDirectories:true)
                            ModelZoo.externalUrls=[PhoneReferenceProvider.directory]
                            DeviceCapability.cacheUri=cache
                            DeviceCapability.maxTotalWeightsCacheSize=0
                            let generator=PhoneDrawThingsFactory.make(queue:queue,directory:cache)
                            let resolution=request.resolution ?? .square512
                            var config=GenerationConfigurationBuilder(from:.default)
                            config.model=PhoneReferenceProvider.model
                            config.startWidth=UInt16(resolution.width/64)
                            config.startHeight=UInt16(resolution.height/64)
                            config.steps=4; config.guidanceScale=1; config.strength=1
                            config.seed=UInt32.random(in:0...UInt32.max)
                            config.sampler = .uniPCTrailing
                            config.shift=3; config.resolutionDependentShift=false
                            config.loras=[.init(file:PhoneReferenceProvider.lightning,weight:1,mode:.all)]
                            config.batchSize=1; config.hiresFix=false; config.tiledDecoding=false; config.teaCache=false
                            guard let cg=ImageConverter.cgImage(from:jpeg),
                                  let bitmap=ImageConverter.resize(from:cg,imageWidth:resolution.width,imageHeight:resolution.height),
                                  let input=ImageConverter.tensor(from:bitmap).0 else { throw ReferenceFailure.invalidResponse }
                            if cancellation.isCancelled { throw CancellationError() }
                            DiagnosticLog.shared.record(.debug, .reference, "Qwen 开始本地推理", detail: "seed=\(config.seed) · steps=4 · cfg=1 · strength=1 · shift=3 · sampler=uniPCTrailing · Lightning LoRA=1 · \(resolution.width) × \(resolution.height)", operationID: request.id)
                            let output=try generator.generate(
                                trace:ImageGeneratorTrace(fromBridge:true),image:input,scaleFactor:1,mask:nil,hints:[],
                                text:request.prompt,negativeText:"",configuration:config.build(),fileMapping:[:],keywords:[],
                                cancellation:{ cancellation.register($0) },
                                feedback:{ signpost,_,_ in
                                    let message:String; var fraction:Double?
                                    switch signpost {
                                    case .textEncoded: message="手机正在理解原照片"
                                    case .imageEncoded, .controlsGenerated: message="手机正在准备采样"
                                    case .sampling(let step):
                                        let completed=min(max(step+1,1),4)
                                        message="手机采样 \(completed)/4"; fraction=Double(completed)/4
                                    case .imageDecoded: message="手机正在保存参考图"
                                    default: message="手机正在处理参考图"
                                    }
                                    events.continuation.yield(.init(id:request.id,state:.running,progress:fraction,stage:message))
                                    return !cancellation.isCancelled
                                })
                            if cancellation.isCancelled { throw CancellationError() }
                            guard let tensor=output.0?.first,let encoded=ImageConverter.image(from:tensor,scaleFactor:1).pngData() else { throw ReferenceFailure.failed }
                            continuation.resume(returning:encoded)
                        } catch { continuation.resume(throwing:error) }
                    }
                }
            } onCancel: { cancellation.cancel() }
            events.continuation.finish(); await consumer.value
            return data
        } catch {
            events.continuation.finish(); await consumer.value
            throw error
        }
    }
}
private final class PhoneEngineCancellation: @unchecked Sendable {
    private let lock=NSLock()
    private var cancelled=false
    private var callback:(()->Void)?
    var isCancelled:Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    func register(_ callback:@escaping ()->Void) {
        lock.lock(); let cancelNow=cancelled; self.callback=callback; lock.unlock()
        if cancelNow { callback() }
    }
    func cancel() { lock.lock(); cancelled=true; let action=callback; lock.unlock(); action?() }
    func clear() { lock.lock(); callback=nil; lock.unlock() }
}
#endif
