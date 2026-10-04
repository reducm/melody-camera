# GitHub Release 构建与安装

更新：2026-10-04。用户已授权配置并发布首个开发预览，选择同时提供 iPhone IPA 与模拟器包，并授权采用开放许可。项目采用 GPL-3.0-only，第三方权利与来源见 [声明](../THIRD_PARTY_NOTICES.md)。实际运行结果以 [验证记录](验证记录.md) 为准。

## 产物

| 文件 | 用途 |
|---|---|
| `MelodyCamera-<版本>-<构建号>-ios-arm64-unsigned.ipa` | iPhone arm64 未签名应用；安装前须自行签名，不是可以直接下载安装的分发 IPA |
| `MelodyCamera-<版本>-<构建号>-simulator-arm64.zip` | Apple Silicon Mac 的 iOS 模拟器应用；不能装到 iPhone 或 Intel 模拟器 |
| 两份同名 `.json` | 源码提交、平台、Xcode、最低系统、版本、大小和 SHA-256 |
| `ThirdPartyNotices.zip` | 原始 LICENSE/COPYING/NOTICE、固定 revision 与依赖源码下载地址；App 的 `Legal/` 中也保留 |
| `MelodyCamera-<标签>-source.tar.gz` | 同一提交的项目源码、锁文件和构建脚本 |
| `SHA256SUMS.txt` | 所有上述文件的 SHA-256 |

产物不含 API Key、模型权重、照片或用户日志。在线模型用自己的 Key；Gemma/Qwen 安装边界见 README。项目最低目标 iOS 17 不代表所有手机都能运行大型模型，模型仍需独立验收。

## 使用已有产物

下载到同一目录后运行 `shasum -a 256 -c SHA256SUMS.txt`。模拟器包解压后，先在 Xcode/Simulator 启动一个兼容的 iPhone 模拟器，再运行：

```sh
xcrun simctl install booted MelodyCamera.app
xcrun simctl launch booted com.melody.camera
```

iPhone IPA 在本流程中关闭代码签名，没有开发者证书或 provisioning profile。请使用自己的签名与设备安装流程；无需将证书、Apple 登录信息或模型 Key 上传到此仓库。已有开发者环境也可直接从源码通过 Xcode 安装。重签名工具/账号的可用设备、能力与有效期由其实际配置决定，本项目没有完成第三方重签名工具验收。

## 本机构建

需要 Apple Silicon、完整 Xcode 26.6、iOS SDK 26.5、Git LFS、Python 3.11+；这是当前验证组合，未承诺其他 Xcode 版本均可用。先从仓库干净检出，再执行：

```sh
swift test
swift build
bash scripts/build-release.sh iphoneos
bash scripts/build-release.sh iphonesimulator
python3 scripts/prepare-release.py v0.1.0-preview.1
```

默认输出在忽略的 `artifacts/release/`，中间产物在 `build/` 与 `.build/xcode-packages/`。已有文件不会自动覆盖，重复构建请选择新的 `MELODY_RELEASE_OUTPUT` 目录或自行归档旧产物。打包器允许生成本机未提交版本以排错，但发布核对器拒绝 `source_dirty: true`。`prepare-release.py` 用于上述默认输出目录。

可用 `MELODY_DERIVED_DATA`、`MELODY_PACKAGES_DIR` 指定本机缓存，`MELODY_BUILD_JOBS` 控制并发数（默认 3）；同一 DerivedData 的不同平台构建须顺序进行。脚本使用 Release 配置、arm64、公共 Bundle ID、锁定依赖，并显式关闭签名，个人 Team 不会进入产物。

`GIT_LFS_SKIP_SMUDGE=1` 避免 LiteRT-LM 源码检出时下载非 iOS 的预编译文件和测试权重；iOS 所需官方 XCFramework 仍由 SwiftPM 根据 Package.swift 的 URL 和 SHA-256 获取。这修复了首次 CI 因 Android LFS 缺失对象而失败的问题。

## GitHub Actions

- 普通 `main`/`codex/**` 推送和 PR 运行 `verify.yml`：Swift 测试、Mac 构建、无签名 arm64 iOS 模拟器 Debug 构建。
- 在 Actions 中选择 **构建 GitHub Release** → Run workflow，选择要发布的提交所在分支，输入与 `MARKETING_VERSION` 一致的标签，例如 `v0.1.0-preview.1`；默认保留草稿，也可显式取消草稿。
- 工作流先测试，再在两个独立 runner 上并行构建设备/模拟器 Release。两者成功且来源、摘要和许可检查通过后，使用仓库自带 `GITHUB_TOKEN` 创建预发布；只有发布 job 获得 `contents: write`。
- 已存在的 Release 不覆盖，使用新的预发布编号。此流程不创建付费 runner、不上传商店、不使用个人签名 Secrets。
- 使用标准 `macos-26` arm64 runner 和 `/Applications/Xcode_26.6.app`；缓存仅 SwiftPM 下载目录，按锁文件与 Xcode 分键。构建产物临时保留 7 天，Release 附件持续保留。

参考：[GitHub runner 环境](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md)、[GitHub CLI Release](https://cli.github.com/manual/gh_release_create)。远程环境会更新，缺少指定 Xcode 时应明确失败并重新验证配置，不静默换版本。

## 个人签名配置

复制 `Config/Local.example.xcconfig` 为 `Config/Local.xcconfig` 并填写 Team 与自己的 Bundle ID；后者已被忽略。Debug 与 Release 共用 `Config/Build.xcconfig`，其 `#include?` 可选读取本机覆盖；共享工程与 `project.yml` 都不写个人值。XcodeGen 重生成后继续生效。模型 Key 仍只存系统钥匙串，不能写进任何 xcconfig。
