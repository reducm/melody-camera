#!/usr/bin/env python3
"""移除固定 Draw Things 中本产品不用的公开 gRPC 服务器私钥资源。"""
import argparse
import json
from pathlib import Path
import stat
import subprocess

REVISION = 'b5e9fb925ca5394b747e0e98a8c293bbab5091ca'
RESOURCE = 'Libraries/BinaryResources/GeneratedC/server_key_generated.c'
PATCH_ID = 'drawthings-empty-unused-grpc-server-key-v1'
REPLACEMENT = b'''/* Melody downstream change (GPL-3.0): the in-process iPhone engine
 * does not start the upstream gRPC server. Do not embed its public test key.
 * Keep the resource ABI and a non-null pointer for the Swift Data wrapper. */
#include <stddef.h>
static unsigned char melody_empty_server_key = 0;
const size_t server_key_key_size = 0;
void *server_key_key(void) { return &melody_empty_server_key; }
'''


def apply_patch(checkout):
    revision = subprocess.check_output(['git', '-C', str(checkout), 'rev-parse', 'HEAD'], text=True).strip()
    if revision != REVISION:
        raise ValueError('Draw Things revision 已变化，须重新审查资源补丁')
    original = subprocess.check_output(['git', '-C', str(checkout), 'show', f'{REVISION}:{RESOURCE}'])
    target = checkout / RESOURCE
    current = target.read_bytes()
    if current not in (original, REPLACEMENT):
        raise ValueError('上游资源已有其他改动，拒绝覆盖')
    # SwiftPM checkout 默认只读；只在写入已核对的文件时临时启用用户写权限。
    mode = target.stat().st_mode
    try:
        target.chmod(mode | stat.S_IWUSR)
        target.write_bytes(REPLACEMENT)
    finally:
        target.chmod(mode)
    print(json.dumps({'runtime_patch': PATCH_ID, 'revision': REVISION}, ensure_ascii=False))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--packages', type=Path, required=True)
    args = parser.parse_args()
    apply_patch(args.packages / 'checkouts/draw-things-community')
