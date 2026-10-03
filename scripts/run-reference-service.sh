#!/bin/zsh
set -eu
# 调用者显式传入本机局域网 IP；默认只监听本机。
cd "${0:A:h:h}"
exec python3 scripts/reference-service/server.py \
  --binary artifacts/drawthings/cli-proxy \
  --models artifacts/drawthings/models \
  --root "$HOME/Library/Application Support/MelodyReferenceService" \
  --host "${MELODY_REFERENCE_HOST:-127.0.0.1}" "$@"
