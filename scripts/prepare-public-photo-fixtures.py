#!/usr/bin/env python3
"""下载有来源记录的公开测试照片。只写指定目录，不读取凭据或用户相册。"""
import argparse
import hashlib
import json
from pathlib import Path
import urllib.request

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('output', type=Path)
args = parser.parse_args()
manifest = json.loads(Path(__file__).with_name('public-photo-fixtures.json').read_text())
args.output.mkdir(parents=True, exist_ok=True)
for sample in manifest:
    path = args.output / sample['file']
    if not path.exists() or hashlib.sha256(path.read_bytes()).hexdigest() != sample['sha256']:
        request = urllib.request.Request(sample['url'], headers={'User-Agent': 'MelodyCamera-LocalRegression/1.0'})
        with urllib.request.urlopen(request, timeout=60) as response:
            data = response.read(8_000_001)
        if len(data) > 8_000_000 or hashlib.sha256(data).hexdigest() != sample['sha256']:
            raise SystemExit(f"公开样图校验失败：{sample['file']}，请核对来源版本。")
        path.write_bytes(data)
    print(f"已校验：{sample['file']}")
(args.output / 'scenarios.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2))
