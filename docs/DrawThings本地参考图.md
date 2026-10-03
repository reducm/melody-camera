# Draw Things 手机本地参考图

更新：2026-10-03。当前 App 在 **此 iPhone 内**运行 Qwen Image Edit 2511；Mac 中转方案已撤销。手机首次与重复生成、恢复均通过，具体边界见 [ADR 005](adr/005-iPhone端侧参考图.md)、[验证记录](验证记录.md)。

## 当前使用方式

1. 打开“设置 → 推荐参考图”，确认手机模型已安装；当前个人开发设备约 28 GB 模型已就绪。普通用户模型下载管理尚未实现，不要把文件就绪百分比当成下载器。
2. 开启“生成推荐时同时生成参考图”，选择全局分辨率。默认 512 × 512，可选 512 × 768、768 × 512、768 × 768；只影响之后提交的任务。
3. 拍摄/选图后生成推荐。文字与模板先显示，各项参考图逐个排队；已有推荐可点击“生成这张参考图”，失败可重试，完成后可重新生成。
4. 随时可选模板跟拍，不必等图。卡片显示真实采样百分比及阶段；可取消或放大结果。合成图不替换原片，也不会算成新的实拍照片。
5. 在“设置 → 诊断日志”查看该次 Qwen 提示词、参数、进度、输出和关联生成图。模型调用正文仅存在手机，可关闭记录或清理。

生成过程没有 Mac 地址/配对开关，不需要运行 Mac 服务；没有自动云端回退。开发时 Mac 编译和无线安装与手机内生成是不同链路。Gemma 负责本机分析，不负责生图。

## 模型与资源

- 官方 `_MediaGenerationKit` 固定源码版本，实际使用公开 `LocalImageGenerator` 和按需加载权重；不申请 Personal Team 不支持的扩展虚拟地址权限。
- Qwen Edit 2511 6-bit、Qwen 2.5 VL 编码器、VAE 和匹配 Lightning 4 步 LoRA；4 步、CFG 1、shift 3、UniPC Trailing，单张单批。
- 模型独立放 `Application Support/DrawThingsModels`，不进 Git 和 App 资源；Gemma/Qwen 共用串行模型槽，排除备份。
- SDK 优化后的 ckpt 元数据和 `-tensordata` 成对保存，不能只复制变小的元数据。当前完整性检查支持原下载 VAE 和首次运行后的拆分形式。
- GPL 来源与许可证保留在源码和 [许可证文件](licenses/DrawThings-GPL-3.0.txt)；当前仅个人开发，未做商店发布。

## 实际结果与限制

同一手机 512 方图先后约 118.03、102.23、100.79 秒完成，图片回存对应推荐、重启恢复通过。这些是单次实际任务，不承诺冷/热启动统一速度。仅日志轮次最后一次约 100.79 秒；全部命令与版本边界见验证记录。

更高三个尺寸、飞行模式、连续批量、温升/内存、生成中取消与拍照压力仍待验。当前后台会取消活动任务；没有可靠总量的阶段不显示伪造百分比。提示词与目标框是软约束，可能改变细节、标志、背景或不可见表面；自动主体/机位审核、生成图设计轮廓提取和相册自动保存尚未实现。

## 历史 Mac 实验资料（已撤销，不作为当前操作步骤）

以下保留用于理解早期实验和复现，当前手机 App 已无服务地址/连接密钥入口，也不再包含该路线所需的局域网配置。旧实验网络曾超时、后来完整复验通过；原因未证实，不能归因于用户 Wi-Fi。随后按用户目标切换为手机端侧。不要因读取本附录而重新启动服务。

### 旧 Mac 服务使用方式（当前 App 已无这些设置）

1. Mac 安装官方独立 CLI 和对应模型。当前固定 CLI 版本为 `v26.0928.0`，使用 Qwen Edit 2511 的 6-bit 模型；不是安装第三方改包。
2. 同一可信局域网下，在项目目录运行 `MELODY_REFERENCE_HOST=<Mac局域网IP> ./scripts/run-reference-service.sh`。默认不指定 IP 时只允许本机访问。
3. 手机“模型设置 → 推荐参考图”：服务地址优先填 `http://<Mac的LocalHostName>.local:7861`（`scutil --get LocalHostName` 可查）；连接密钥取自 Mac 的 `~/Library/Application Support/MelodyReferenceService/connection-token`，不要提交仓库、贴日志或分享截图。
4. 打开开关并保存。对已有推荐点击“生成这张参考图”；新一轮推荐完成后自动为各推荐项排队生成。可以直接跟拍，无须等图。
5. Mac 保持开机并运行服务。关闭终端 / 服务或手机切后台可能中断当前作业，回到推荐卡片重试即可。服务不会自动启用云服务。

### 历史下载与复现

官方来源：[Draw Things 社区仓库](https://github.com/drawthingsai/draw-things-community)、[固定 CLI 发布](https://github.com/drawthingsai/draw-things-community/releases/tag/v26.0928.0)、[Qwen 2511 模型卡](https://huggingface.co/Qwen/Qwen-Image-Edit-2511)。

CLI 放在忽略目录 `artifacts/drawthings/cli-proxy`。SHA-256：`0a29070442f3b5e52100499dd5f33d6b8338a50b7e88ba833cfb95c9a43f6e81`。下载后先核对官方 release digest，再赋予可执行权限。

```sh
artifacts/drawthings/cli-proxy models ensure \
  --models-dir artifacts/drawthings/models \
  --model qwen_image_edit_2511_q6p.ckpt
```

此命令下载底模及 3 项依赖：Qwen 2.5 VL 7B 量化编码器、视觉编码器、VAE。底模文件约 17.63 GB，仅降低生成分辨率不能免除权重存储。遇网络问题按本机约定在当前 shell 使用 `proxy_on`，不修改系统代理配置。

加速权重：`qwen_image_edit_2511_lightning_4_step_v1.0_lora_f16.ckpt`，约 807 MiB，官方 SHA-256：`f8a3d906c4c493acbef7c4e504f653042e9091bbfedd16e01ac1bf740c95135d`。下载源按官方 CLI 的规则使用 `https://static.libnnc.org/` 加文件名；必须放在同一 models 目录。配置取自 [官方推荐配置目录](https://models.drawthings.ai/configs.json)，LoRA 元数据与哈希来自 [官方 LoRA 目录](https://models.drawthings.ai/loras.json) 与 [哈希目录](https://models.drawthings.ai/loras_sha256.json)。

当前固定 4 步、CFG 1、shift 3、sampler 17、LoRA 权重 1。模型加载和照片编码仍然耗时，4 步不意味着瞬时生成。CLI 首次执行可能把 ckpt 的张量外置到同名 `-tensordata` 文件，原下载哈希因此仅用于初始下载校验；运行时必须完整保留这两个文件。

地址说明：iOS 17+ 对数字 IP 的 ATS 例外有额外要求，本项目声明 `NSAllowsLocalNetworking` 并优先使用 `.local` 主机名，不关闭全局 ATS。[Apple 官方说明](https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsallowslocalnetworking)。

### 当时的限制

- 这是独立 Mac 服务适配器，不是 iPhone 内置 Qwen；CLI 源码许可证 GPL-v3，模型及其他组件分别核查许可。
- 服务当前固定竖幅 384×512，CLI 会调整输入画幅；横图构图可能被裁切。后续按原图比例选择对齐尺寸，并提供横竖幅预览。
- 服务默认采用官方匹配的 Edit 2511 Lightning 4 步配置；用 `--profile baseline` 可跑普通底模 20 步对照。两者实际结果见验证记录。
- 文案和归一化框是软提示，不能保证几何精确；模型可能改变品牌字样、物体细节或补造背面。
- 当前只能查看合成参考图，尚不自动提取设计轮廓、不自动存相册、不写回实拍照片。
- 单机私有原型不提供公网、多用户隔离或服务端持久恢复；未来云改图适配器保持同一任务协议。

实现决策见 [ADR 004](adr/004-异步参考图与本地生成服务.md)，实测状态以 [验证记录](验证记录.md) 为准。

### Mac 当时的首次结果（2026-10-03）

已有鼠标照片实测：普通版约 16 分 55 秒；Lightning 完整约束提示词约 2 分 32 秒。首次简化提示词的 Lightning 结果误画出了摄影者与线缆，未作为可用推荐；当前 Core 明确这些词是画面外操作，不是新增对象。单张成功不能保证后续照片质量或一致耗时。当前合成图只供参考，需要用户检查主体细节。

2026-10-03 后续真机复验已通过：手机访问 Mac 的 `.local` 与局域网 IP 均返回 HTTP 200；随后手机发起真实生成任务，Mac 处理完成后由 App 自动下载、保存，手机与服务端作业 ID 一致且状态 ready。此轮没有通过开发容器导入生成图。之前超时原因未确定，不能归因为用户 Wi-Fi 配置；当前同一网络可直接使用。Mac 服务仍需运行。
