# 第三方源码、运行时与素材

Melody 项目源码自首个公开预览起采用 **GPL-3.0-only**，完整条款见 [LICENSE](LICENSE)。第三方代码与素材仍保留各自的版权、许可证和 NOTICE；本声明不改变它们的许可。模型权重不随仓库或 Release 分发。

## 核心依赖

| 组件 | 来源/版本 | 许可与用途 |
|---|---|---|
| Draw Things / `_MediaGenerationKit` | [固定源码](https://github.com/drawthingsai/draw-things-community/tree/b5e9fb925ca5394b747e0e98a8c293bbab5091ca) | GPL-3.0；iPhone 参考图引擎。项目中适配的 Qwen tokenizer 保留来源说明 |
| LiteRT-LM | [0.16.0](https://github.com/google-ai-edge/LiteRT-LM/tree/924e79c91542761242244e4f1651851f822e4cbb) | Apache-2.0；本机 Gemma 适配器及官方 CLiteRTLM 二进制 |
| ccv / s4nnc / dflat 等传递依赖 | Xcode 的 `Package.resolved` 固定全部 revision | 各自许可；构建时从对应源码收集原始 LICENSE/COPYING/NOTICE |
| Apple 系统框架 | 随目标系统及开发工具提供 | 不纳入项目 GPL 授权范围 |

完整固定依赖以 [Package.resolved](MelodyCamera.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved) 为准。打包脚本检查 checkout 的 revision 与锁文件一致，保留所有已跟踪的 LICENSE、COPYING、NOTICE、COPYRIGHT 文件，并生成 `Legal/dependencies.json`，包含每个依赖的上游仓库、精确 revision 和源码归档地址。该目录同时保存在应用包和 Release 的 `ThirdPartyNotices.zip` 中。清单可能含上游仓库中未链接的组件，不能据此推断 App 使用其全部能力。

Release 的 `*-source.tar.gz` 提供本项目对应提交、构建脚本与锁文件；依赖源码按 `dependencies.json` 中的固定地址获取，构建命令见 [Release 构建说明](docs/Release构建.md)。iOS 官方预编译框架由 SwiftPM 按上游 Package.swift 的固定 URL 和 SHA-256 获取；源码归档不包含模型、私钥或这些大型二进制。

## 素材和模型

- 文档截图使用公开测试照片与固定测试数据，出处见 [PRD 素材说明](docs/prd/assets/README.md) 和 [README 展示素材](docs/images/README.md)。第三方照片不因项目采用 GPL 而重新授权。
- 图标候选、原始提示词、所选版本和校验信息保存在 `design/app-icons/2026-10-03/`。
- Gemma、Qwen、Lightning 等权重须另行获取并遵循各自的模型许可。来源与当前安装边界见 README 和 `docs/DrawThings本地参考图.md`。
