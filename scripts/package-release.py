#!/usr/bin/env python3
"""核对 Release 应用、收集上游许可并生成 IPA/模拟器包；不读取钥匙串。"""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent
LOCK = Path('MelodyCamera.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved')


def command(*args):
    return subprocess.check_output(args, text=True).strip()


def check_app(app, sdk):
    with (app / 'Info.plist').open('rb') as stream:
        info = plistlib.load(stream)
    expected = 'iPhoneOS' if sdk == 'iphoneos' else 'iPhoneSimulator'
    if info.get('CFBundleSupportedPlatforms') != [expected]:
        raise ValueError('应用平台与产物名称不一致')
    if info.get('CFBundleIdentifier') != 'com.melody.camera':
        raise ValueError('应用包含非公共 Bundle ID')
    executable = app / info['CFBundleExecutable']
    if command('lipo', '-archs', str(executable)) != 'arm64':
        raise ValueError('产物必须是 arm64')
    forbidden = {'.mobileprovision', '.p12', '.pfx', '.key', '.pem', '.p8',
                 '.litertlm', '.gguf', '.ckpt', '.safetensors', '.log'}
    secrets = re.compile(rb'\bsk-[A-Za-z0-9_-]{20,}\b|-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----')
    for item in app.rglob('*'):
        if item.is_symlink() and not item.resolve().is_relative_to(app):
            raise ValueError('应用包含指向包外的符号链接')
        if not item.is_file():
            continue
        if (item.suffix.lower() in forbidden or item.name.startswith('.env')
                or item.name in {'melody-provider-once.json', 'melody-reference-once.json',
                                 'credentials.json', 'secrets.json'}):
            raise ValueError('应用包含不应分发的配置、签名、模型或日志文件')
        # 分块扫描并保留交界内容，避免将大型 SDK 整体读入内存。
        with item.open('rb') as stream:
            previous = b''
            while block := stream.read(1024 * 1024):
                data = previous + block
                if secrets.search(data):
                    raise ValueError('应用内容命中凭据格式；停止打包，不输出匹配正文')
                previous = data[-256:]
    return info


def collect_licenses(packages, destination):
    """保留锁定源码中所有跟踪的许可证/NOTICE，同时记录精确源码入口。"""
    checkouts = {p.name.lower(): p for p in (packages / 'checkouts').iterdir() if p.is_dir()}
    pins = json.loads((ROOT / LOCK).read_text())['pins']
    dependencies = []
    for pin in pins:
        identity, revision = pin['identity'], pin['state']['revision']
        checkout = checkouts[identity]
        if command('git', '-C', str(checkout), 'rev-parse', 'HEAD') != revision:
            raise ValueError(f'依赖版本与锁文件不符：{identity}')
        paths = command('git', '-C', str(checkout), 'ls-files', '-z').split('\0')
        copied = []
        for name in paths:
            path = Path(name)
            if not re.match(r'^(licen[cs]e|copying|notice|copyright)([._-]|$)', path.name, re.I):
                continue
            source = checkout / path
            if source.is_symlink() or not source.is_file():
                continue
            target = destination / identity / path
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, target)
            copied.append(name)
        if not copied:
            raise ValueError(f'依赖没有找到许可证：{identity}')
        url = pin['location'].removesuffix('.git')
        dependencies.append({'name': identity, 'revision': revision, 'repository': url,
                             'source_archive': f'{url}/archive/{revision}.tar.gz',
                             'license_files': copied})
    destination.mkdir(parents=True, exist_ok=True)
    (destination / 'dependencies.json').write_text(json.dumps(dependencies, ensure_ascii=False, indent=2) + '\n')
    for name in ('LICENSE', 'THIRD_PARTY_NOTICES.md'):
        if (ROOT / name).is_file():
            shutil.copyfile(ROOT / name, destination / name)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=Path, required=True)
    parser.add_argument('--sdk', choices=['iphoneos', 'iphonesimulator'], required=True)
    parser.add_argument('--packages', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    app = args.app.resolve()
    info = check_app(app, args.sdk)
    version, build = info['CFBundleShortVersionString'], info['CFBundleVersion']
    if not re.fullmatch(r'\d+\.\d+\.\d+', version) or not re.fullmatch(r'\d+', build):
        raise ValueError('版本号或构建号格式不合法')
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    kind = 'ios-arm64-unsigned' if args.sdk == 'iphoneos' else 'simulator-arm64'
    stem = f'MelodyCamera-{version}-{build}-{kind}'
    extension = '.ipa' if args.sdk == 'iphoneos' else '.zip'
    archive = output / (stem + extension)
    if archive.exists():
        raise ValueError('目标产物已存在，请使用新的输出目录')
    with tempfile.TemporaryDirectory(prefix='melody-release-') as directory:
        stage = Path(directory)
        parent = stage / 'Payload' if args.sdk == 'iphoneos' else stage
        parent.mkdir(exist_ok=True)
        copied_app = parent / app.name
        shutil.copytree(app, copied_app, symlinks=True)
        collect_licenses(args.packages.resolve(), copied_app / 'Legal')
        # 应用是 CODE_SIGNING_ALLOWED=NO 的构建，禁止附带个人 provisioning。
        check_app(copied_app, args.sdk)
        source = parent if args.sdk == 'iphoneos' else copied_app
        subprocess.run(['ditto', '-c', '-k', '--norsrc', '--keepParent', str(source), str(archive)], check=True)
        if args.sdk == 'iphoneos':
            subprocess.run(['ditto', '-c', '-k', '--norsrc', '--keepParent',
                            str(copied_app / 'Legal'), str(output / 'ThirdPartyNotices.zip')], check=True)
    with archive.open('rb') as stream:
        digest = hashlib.file_digest(stream, 'sha256').hexdigest()
    metadata = {
        'file': archive.name, 'sha256': digest, 'bytes': archive.stat().st_size,
        'commit': command('git', '-C', str(ROOT), 'rev-parse', 'HEAD'),
        'version': version, 'build': build, 'configuration': 'Release',
        'sdk': args.sdk, 'architecture': 'arm64', 'minimum_os': info.get('MinimumOSVersion'),
        'signing': 'unsigned; iPhone 安装前需自行签名' if args.sdk == 'iphoneos' else '模拟器专用，无个人分发签名',
        'xcode': command('xcodebuild', '-version'),
        'source_dirty': bool(command('git', '-C', str(ROOT), 'status', '--porcelain')),
        'models_included': False, 'api_key_included': False,
    }
    (output / (stem + '.json')).write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps(metadata, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
