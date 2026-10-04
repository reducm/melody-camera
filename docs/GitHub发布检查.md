# GitHub 发布检查

更新：2026-10-04。本文用于源码提交和推送前检查。用户已单独授权首次合并与推送，`main` 已同步至 [reducm/melody-camera](https://github.com/reducm/melody-camera)；本文本身不构成未来推送或发布安装包的授权。

## Key 当前在哪里

手机设置页的掩码 Key 从系统钥匙串读取，服务为 `com.melody.camera.provider`、账户为 `personal-key`；源码入口为 [KeyStore](../Sources/MelodyApp/KeyStore.swift)。它不属于 Git 工作树或 App 包资源。接口根地址和模型 ID 是普通配置；别人安装时需要填自己的 Key。

早期开发通过设备 Documents 内一次性 `melody-provider-once.json` 导入，代码消费后删除。此前验收已经确认手机文件和电脑临时配置删除，历史证据见 [验证记录](验证记录.md)。后续临时配置放 `private/` 或 `artifacts/`，不粘贴到源码、文档、Issue、提交消息或截图。

## 忽略规则

[.gitignore](../.gitignore) 排除环境文件、两个一次性设备配置、个人 `*.local.json` / `*.local.xcconfig`、`Config/Local.xcconfig`、私钥/钥匙串/签名材料、模型权重、设备运行数据、日志、构建产物、扫描报告与迁移备份。`.env.example`、无真实值的配置示例、工程、锁文件、源码、测试、许可证与公开截图仍可提交。

`.gitignore` 不移除已经跟踪或已经提交的文件，也无法识别任意文件名下的私人内容。每次提交仍要审查实际文件，避免使用未经检查的 `git add .`。

## 可重复的本机密钥扫描

先安装 [Gitleaks](https://github.com/gitleaks/gitleaks)（本轮验证版本 8.30.1）；使用 Homebrew 时可运行 `brew install gitleaks`，也可下载官方对应架构 release 并核对 SHA-256，无需把二进制提交到仓库。

```sh
python3 scripts/check-secrets.py
# 或使用自己保存的可执行文件
python3 scripts/check-secrets.py --gitleaks /path/to/gitleaks
```

脚本只在本机执行，不发起网络请求，不读取钥匙串。四个范围分别扫描：

1. `git log --all --full-history` 覆盖全部本地分支和标签的补丁历史。
2. `git rev-list --objects --all` 对可达历史中的 blob 与提交元数据再扫全文，不只检查当前文件。
3. Git 暂存区的完整文件快照，防止暂存后又修改工作区造成漏检。
4. 当前已跟踪文件与未忽略的新文件，即可能进入下一次提交的内容；忽略目录中的私人文件与构建缓存不参与此项。

使用 Gitleaks 默认规则并增加模型 `sk-` Key 规则，支持两层解码，不接受行内 `gitleaks:allow` 或指纹文件静默跳过；输出只有文件、行、规则和提交/对象位置，报告脱敏后保存在临时目录并清理。发现命中、已跟踪但应忽略的文件或无法自动核对的符号链接时退出非零。

扫描是风险检查，不是零泄漏保证：图片像素需单独目视复核，模型正文或私人照片描述不一定是凭据；仓库外文件、设备钥匙串与不可达的本地 Git 对象不在拟推送历史范围。若发现真实已泄漏凭据，先撤销或轮换，再评估清理历史；不要仅修改忽略规则。[GitHub 官方处理说明](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/removing-sensitive-data-from-a-repository)

本轮命中数、扫描范围、临时假密钥反向验证与忽略规则检查结果见 [验证记录](验证记录.md)，不保存真实 Key、Key 哈希或命中正文。

## 提交前人工检查

```sh
git status --short
git diff --check
git diff --cached --stat
git diff --cached
git ls-files -ci --exclude-standard
python3 scripts/check-secrets.py
```

`git diff --cached` 在本机人工审阅即可，不把可能含敏感信息的输出粘贴到公共讨论。检查公开截图、素材许可、模型结果来源标记，以及所有拟推送分支的 Git 作者邮箱；作者邮箱不属于 API Key，但公开历史会保留它。

## 仍待完成的发布准备

- 个人 Team 仍在共享工程中；本机签名覆盖配置尚待拆分，`project.yml` 与生成工程需同步。
- 根项目许可证与完整第三方声明尚待决定；Draw Things 引擎及适配代码涉及 GPL-3.0，模型/素材许可另行记录。
- Gemma 已有固定下载与导入；Qwen 目前仍是开发容器安装，需要可复现安装工具，普通用户下载管理尚未实现。
- 完成全新克隆依赖解析、Swift / iOS 构建与无 Key/无模型状态检查；首次 GitHub Actions 已触发，结果见 [Actions](https://github.com/reducm/melody-camera/actions)，runner/Xcode/arm64/LFS/缓存仍需按实际结果核对。

README 与忽略规则的本轮完善不代表以上事项已经完成。首次推送保留原历史，仅快进合并开发分支并设置 `main` 上游；未使用强制推送，未上传模型权重、私人配置或构建产物。
