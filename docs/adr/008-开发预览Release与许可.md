# ADR 008：开发预览 Release、个人签名与项目许可

日期：2026-10-04。状态：已采纳；构建/发布实测独立记录。

用户授权继续配置 GitHub Release，明确选择 iPhone IPA 与模拟器包，要求尽量开放并委托决定许可证、修改和推送。

采用 GPL-3.0-only，保留已链接 Draw Things GPL 源码及所有第三方许可；不擅自把第三方组件改为项目许可证。Root LICENSE、第三方声明、App Legal 目录与 Release 许可归档共同保留条款与来源，权重不随包分发。

首轮使用标准 GitHub arm64 macOS runner、Xcode 26.6 和锁定依赖构建 Release 配置，生成无个人签名的 iPhone IPA 与模拟器 ZIP。没有证书/描述文件 Secrets，不以已编译 IPA 冒充可直接安装或 App Store 分发。默认允许先建草稿；公开产物为预发布，附源码、依赖源码入口、平台清单和 SHA-256。

个人 Team 与 Bundle ID 从共享工程移至忽略的 `Config/Local.xcconfig`，XcodeGen 只引用公共配置；CI 显式禁用签名。API Key 继续使用设备钥匙串。

结果：可重复生成两类开发产物，避免把个人签名或模型打进公共包。代价：iPhone 用户需自行签名；通用安装、模型下载器、签名分发和真机压力验收仍是独立工作。详见 [构建说明](../Release构建.md) 和 [验证记录](../验证记录.md)。
