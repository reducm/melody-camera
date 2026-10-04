#!/usr/bin/env python3
"""发布前核对两个平台的产物、源码提交和摘要，生成说明与源码归档。"""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import zipfile


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def validate_assets(output, expected_commit, version):
    manifests = sorted(output.glob('MelodyCamera-*.json'))
    if len(manifests) != 2:
        raise ValueError('必须同时提供 iPhone 与模拟器构建清单')
    platforms, builds = set(), set()
    for path in manifests:
        data = json.loads(path.read_text())
        name = data['file']
        if Path(name).name != name:
            raise ValueError('产物名称不能包含路径')
        archive = output / name
        if (data['commit'] != expected_commit or data['source_dirty']
                or data['version'] != version or data['configuration'] != 'Release'
                or data['architecture'] != 'arm64'):
            raise ValueError('构建来源、版本、配置或架构不一致')
        if data['models_included'] or data['api_key_included']:
            raise ValueError('不允许分发内含模型或 Key 的产物')
        if archive.stat().st_size != data['bytes'] or digest(archive) != data['sha256']:
            raise ValueError('产物大小或 SHA-256 不匹配')
        platforms.add(data['sdk'])
        builds.add(data['build'])
        prefix = 'Payload/MelodyCamera.app/' if data['sdk'] == 'iphoneos' else 'MelodyCamera.app/'
        with zipfile.ZipFile(archive) as package:
            if package.testzip() is not None:
                raise ValueError('ZIP 内容校验失败')
            if not {prefix + 'Info.plist', prefix + 'MelodyCamera', prefix + 'Legal/dependencies.json'}.issubset(package.namelist()):
                raise ValueError('包缺少应用或依赖说明')
    if platforms != {'iphoneos', 'iphonesimulator'} or len(builds) != 1:
        raise ValueError('两个平台的构建不成对')
    return next(iter(builds))


def main():
    tag = sys.argv[1]
    match = re.fullmatch(r'v(\d+\.\d+\.\d+)-(preview|alpha|beta|rc)\.[1-9][0-9]*', tag)
    if not match:
        raise ValueError('无效的预发布标签')
    output = Path('artifacts/release')
    commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip()
    if os.environ.get('GITHUB_SHA', commit) != commit:
        raise ValueError('发布工作区与触发提交不一致')
    build = validate_assets(output, commit, match[1])
    source = output / f'MelodyCamera-{tag}-source.tar.gz'
    subprocess.run(['git', 'archive', '--format=tar.gz', f'--prefix=MelodyCamera-{tag}/',
                    '-o', str(source), commit], check=True)
    if not (output / 'ThirdPartyNotices.zip').is_file():
        raise ValueError('缺少第三方许可证归档')
    # 白名单上传；不会把中间构建目录或日志带进 Release。
    assets = sorted(output.iterdir())
    if len(assets) != 6 or any(p.suffix not in {'.ipa', '.zip', '.json', '.gz'} for p in assets):
        raise ValueError('发布目录包含额外文件或缺少产物')
    (output / 'SHA256SUMS.txt').write_text(''.join(f'{digest(p)}  {p.name}\n' for p in assets))
    notes = f'''# Melody 相机 {tag}

开发预览，App 版本 {match[1]}，构建 {build}。源码提交：`{commit}`。

## 下载哪个文件

- `*-ios-arm64-unsigned.ipa`：iPhone arm64 **未签名包**，需要使用自己的 Apple 签名与安装工具重新签名；不能下载后直接安装，也不是 TestFlight/App Store 分发包。
- `*-simulator-arm64.zip`：Apple Silicon Mac 的 iOS 模拟器应用。解压后启动兼容的 iPhone 模拟器，运行 `xcrun simctl install booted MelodyCamera.app`，再运行 `xcrun simctl launch booted com.melody.camera`。不支持 Intel 模拟器或真机安装。
- `*-source.tar.gz`：对应本次构建的项目源码、锁文件与构建脚本。
- `ThirdPartyNotices.zip`：依赖许可证、NOTICE、精确 revision 与上游源码下载地址；应用内也保留同一份 Legal 目录。
- 两份 JSON 记录 SDK、Xcode、架构、版本与产物 SHA-256；`SHA256SUMS.txt` 可用 `shasum -a 256 -c SHA256SUMS.txt` 核对。

## 功能和使用条件

拍照/选图进入持久项目，支持摄影知识模板、轮廓跟拍、调色副本和历史恢复。项目采用 GPL-3.0，第三方组件保留各自许可。

包内**没有 API Key、模型权重、私人照片或历史日志**。在线分析需填写自己的 Key；Gemma 需另行下载导入，Qwen 目前仍需开发设备容器安装。模型缺失不会自动上传照片，安装步骤和功能边界见 README。

## 验证范围

此 Release 工作流先运行 Swift 测试和 Mac 构建，再从锁定依赖分别构建 Release 配置的 iOS 设备与 arm64 模拟器应用；真实模型请求默认跳过。打包检查平台、架构、凭据格式与不应分发的文件，发布前再核对产物摘要和源码提交。

这是开发预览，Release 编译不等同于真机签名安装、模型质量、所有手势或高负载验收。尚未提供普通用户 Qwen 下载器、完整进度和实时跟拍评分；其他已验与待验项见 docs/验证记录.md。
'''
    Path('artifacts/release-notes.md').write_text(notes)
    print(f'两个平台产物校验通过，准备发布 {tag}，源码 {commit}')


if __name__ == '__main__':
    main()
