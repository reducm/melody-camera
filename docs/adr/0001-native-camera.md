# 使用 SwiftUI + 原生相机，模型接入独立

我们优先服务 iPhone 上的连续取景、变焦观察与轻量构图引导，因此采用 SwiftUI、AVFoundation 和独立的 Swift 领域模块。Flet 当前已支持 iOS 相机、变焦与画面流，并非做不到基础拍照；但深度相机控制、Vision、端侧模型集成仍可能需要 Flutter/原生扩展，让 Python 易读的收益被跨语言维护成本抵消。此选择增加了 Swift 学习成本，换来相机调试路径直接、模块可独立验证。

首版没有后端。在线视觉使用独立 OpenAI Chat Completions 兼容适配器；将来需要共享密钥、费用控制或 Python 图像研究时，再加 Python 网关。Vercel AI SDK 面向 TypeScript，可用于未来网关，但并不能让不支持视觉的模型获得视觉能力，也不值得现在引入第二套运行时。

同一套界面提供 Mac 演示入口以适应当前无 Xcode 的环境。Mac 演示不等于 iOS 模拟器，也不作为相机真机验收依据。
