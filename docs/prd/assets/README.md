# 评审稿图片来源

采集日期：2026-10-04。用于页面与流程讨论，不作为相机硬件、真实模型质量或完整交互验收的证据。

## 模拟器截图

`p*.png` 为 iPhone 17 Pro Max / iOS 26.5 模拟器中的实际界面，使用 `xcrun simctl io booted screenshot --type=png` 保存。PNG 保留原始尺寸与内容；`previews/*.jpg` 是等比例缩小的显示副本。页面详情和放大窗口使用原始 PNG，流程节点使用预览副本。

项目界面使用已有公开照片回归的咖啡测试项目。界面中的分析、模板和推荐批次是明确标注的固定测试数据，不是本轮真实模型输出；本轮没有生成新的分析或参考图。历史列表限定为隔离的公开样图测试目录。系统照片选择器可见的是已有公开测试照片与模拟器预置图片。日志详情只展示模拟器相机不可用错误，不收录私人模型正文或凭据。

P03–P08、P12 多数是同一工作区中的不同区域。为采集长页面，临时源码副本只添加启动参数控制的滚动定位与既有分区选择，原业务源码未加入这些入口；具体构建与操作边界见 [验证记录](../../验证记录.md)。设置总览与在线配置共用同一张实际截图。

共 15 张模拟器原始截图，对应 16 个页面单元；P15/P16 共用设置总览图。P05 分析进行中、P09 参考图查看、P10 新轮廓核对保留“状态示意 · 未采集截图”标记，不补造生成结果或进度。原始 PNG 尺寸和 SHA-256 见 [图片清单](manifest.json)。

## 拍照与跟拍替代照片

P01 / P11 使用 `camera-photo.png`，对应已有公开样图清单中的 coffee，不表示实际取景或本轮拍摄结果。图片未添加相机控件、轮廓或模型结果。

- 作者：Rachel Michetti。
- 许可：CC0，来源记录见仓库 [公开样图清单](../../../scripts/public-photo-fixtures.json)。
- 项目来源：[scikit-image coffee](https://scikit-image.org/docs/0.25.x/api/skimage.data.html#skimage.data.coffee)。
- 原始文件：[scikit-image v0.25.2 coffee.png](https://raw.githubusercontent.com/scikit-image/scikit-image/v0.25.2/skimage/data/coffee.png)。
- SHA-256：`cc02f8ca188b167c775a7101b5d767d1e71792cf762c33d6fa15a4599b5a8de7`。

## 后续替换

重新采集对应页面后替换 PNG、生成预览副本，并更新 `review-data.json` 的 `media` 信息、日期与来源说明，再执行 `python3 docs/prd/build-review.py`。页面编号和意见存储键保持稳定，便于沿用讨论。
