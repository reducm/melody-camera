# Melody App 图标

2026-10-04 用户选定粉红色卡通相机。按外观确认对应此前生成的 `design/app-icons/2026-10-03/03-soft-3d.png`（文件编号与聊天展示顺序不同），保留原图设计，仅缩放至 iOS AppIcon 所需的 1024 × 1024 PNG，无透明通道，不预裁系统圆角。

正式资源：`ios/Assets.xcassets/AppIcon.appiconset/AppIcon.png`。来源原图 SHA-256：`d399156946f9fc67144b0575a65d4697790a8625c1c23ee72c6e6e6b95aa3562`。已选资源随源码保存，重新构建不依赖未跟踪的候选 design 目录。

`project.yml` 将资源目录纳入 iOS target，并指定 `ASSETCATALOG_COMPILER_APPICON_NAME=AppIcon`；工程由 XcodeGen 同步。单张 universal iOS 1024 图由 actool 生成应用所需图标。
