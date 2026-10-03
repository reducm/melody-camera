# ADR 005：iPhone 内嵌 Draw Things 生成参考图

日期：2026-10-03。状态：采用；真机性能与可用性以验证记录为准。替代 ADR 004 的 Mac 中转选型，保留其异步卡片和供应商接口。

## 目标与纠正

用户要在手机拍照后由手机本地生成构图参照。Mac 端测试不能代替产品实现，也不能把同一 Wi-Fi 当作产品前提。独立 Draw Things App 的 URL 或远程接口不能当作 Melody 内嵌离线推理。

采用官方仓库 `drawthingsai/draw-things-community` 的 `_MediaGenerationKit` SwiftPM 产品，固定 revision `b5e9fb925ca5394b747e0e98a8c293bbab5091ca`。该包明确声明支持 iOS 16 起。App 从同一产品链接官方公开的 `LocalImageGenerator`，通过本地 workspace 强制 `JITWeightsLoading.alwaysFully` 按需读取权重，无 Mac/云端回退。MelodyCore 保持模型无关。

初版高级 Pipeline 在真机文件映射时崩溃。扩展虚拟地址权限又被 Personal Team 拒绝，最终改用同仓库公开底层本地 API，显式按需加载权重，并直接采用内置模型元数据；不调用 fromPretrained 的远程目录解析。照片不传出手机，飞行模式实测仍单列待验。

## 模型与内存

使用 Qwen Image Edit 2511 6-bit、Qwen 2.5 VL 文本/视觉编码器、Qwen VAE 及对应 4-step Lightning LoRA。不是 Qwen Image 1.0 文生图；不是 Gemma 生图。当前文件约 28 GB，置于 App 的 Application Support/DrawThingsModels，排除备份。模型大文件与拆分的 `-tensordata` 必须完整成对。

4 步、CFG 1、UniPC Trailing、shift 3，单张单批。Gemma 与 Qwen 共用手机模型槽，显式串行并支持取消；Actor 在 await 处可重入，不能仅依靠 Actor 声明防止两个大模型同时加载。强制按需加载，权重常驻缓存设为 0，生成结束释放 generator 与临时 workspace。真机内存/耗时需要实测；官方 App 性能不代表集成版本性能。

模型通过开发设备容器安装属于当前个人开发流程，模型不会作为 28 GB App 资源随每次编译重新安装。面向普通用户的断点下载、空间校验和后台恢复后续实现，不把开发复制命令描述为已完成的通用下载器。

## 全局分辨率

默认 512 × 512。设置列表：512 × 512、512 × 768、768 × 512、768 × 768。更高分辨率增加开销，只用于之后的新任务。请求保存提交时的值，避免排队过程中改全局设置导致结果尺寸变化；旧记录没有字段时按 512 × 512 解读。

生成图作为推荐附件，标注“AI 生成参考 · 非实拍”；不得替换原片。用户可先选模板跟拍，图片随后出现。进度百分比来自实际采样步数；加载、编码、解码没有可靠总量时说明阶段，不伪造进度。模型传输百分比由文件实际字节数计算。

## 迁移与验证

旧 Mac 配置不读取、不自动上传；旧 Mac 成图留在磁盘，但不在手机本地任务查询中混用。必须验证：业务回归、iOS 编译、完整模型、真机真实生成、持久化恢复、相机继续可用和取消。模拟器只能验证界面和流程，不能验证 iPhone GPU 模型性能。

`DrawThingsPhoneEngine.swift` 的 tokenizer 工厂适配自固定版本官方源码，保留来源和许可证标注；完整许可证位于 `docs/licenses/DrawThings-GPL-3.0.txt`。官方引擎仓库为 GPL-3.0；当前仅用户个人开发使用。将来若准备分发，应按源码与权重各自许可设计分发方式，本轮不发布。

## 官方依据

- [Qwen Image 支持说明](https://releases.drawthings.ai/p/introducing-qwen-image-support)：2025-08-15，覆盖 iPhone，展示 512 × 512 到 2048 × 2048；低内存设备卸载部分权重。文中 iPhone 16 Pro 的 768 方图两步耗时属于其文生图基准，不能套用为 Melody / Edit 的速度。
- [官方开源推理库](https://github.com/drawthingsai/draw-things-community)：SwiftPM 平台声明、模型配置及 MediaGenerationKit 源码。

## 首次真机结果

免费 Personal Team、无扩展内存/地址空间 entitlement、未附加 LLDB，Mac 服务关闭。512 × 512 / 4 步实际手机任务完成，约 118.03 秒，图片回存原推荐，模板仍可用。这只代表该照片、尺寸和设备的实测，不承诺全部尺寸稳定或耗时相同。

重复生成检查另发现 SDK 会拆分 VAE 存储；完整性检测现支持下载版与优化后的元数据/tensor 文件组合。最终包第二次真机出图约 102.23 秒，证明优化后模型可重复使用。69 项测试及真机/模拟器编译通过。
