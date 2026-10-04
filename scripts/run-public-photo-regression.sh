#!/bin/zsh
# 在已启动的指定模拟器安装 Debug 包并跑公开照片流程。不会操作真机或读取真实模型 Key。
set -euo pipefail
cd "$(dirname "$0")/.."
if (( $# != 4 )); then
  print -u2 '用法：scripts/run-public-photo-regression.sh <模拟器 UUID> <Debug .app 路径> <输出目录> <grant|revoke>'
  exit 2
fi
simulator_id="$1"
app_bundle="$2"
result_directory="${3:A}"
permission="$4"
[[ "$permission" == grant || "$permission" == revoke ]] || exit 2
[[ -d "$app_bundle" ]] || { print -u2 '未找到 Debug 应用包，请先构建。'; exit 2; }
[[ ! -e "$result_directory/results" ]] || { print -u2 '该目录已有结果，请使用新的输出目录，避免误读旧证据。'; exit 2; }
mkdir -p "$result_directory"
python3 scripts/prepare-public-photo-fixtures.py "$result_directory/photos"
xcrun simctl install "$simulator_id" "$app_bundle"
container_path="$(xcrun simctl get_app_container "$simulator_id" com.melody.camera data)"
mkdir -p "$container_path/Documents/PublicPhotoFixtures"
cp "$result_directory/photos/"* "$container_path/Documents/PublicPhotoFixtures/"
xcrun simctl privacy "$simulator_id" "$permission" photos-add com.melody.camera
xcrun simctl terminate "$simulator_id" com.melody.camera >/dev/null 2>&1 || true
# 每次使用独立的结果目录，旧证据移入当前输出目录，不删除项目。
if [[ -d "$container_path/Documents/PublicPhotoResults" ]]; then
  mv "$container_path/Documents/PublicPhotoResults" "$result_directory/previous-$(date +%s)"
fi
xcrun simctl launch "$simulator_id" com.melody.camera --melody-check-public-photos
for attempt in {1..180}; do
  if python3 - "$container_path/Documents/PublicPhotoResults/result.json" <<'PY'
import json,sys
try:
 r=json.load(open(sys.argv[1])); sys.exit(0 if r.get('completed') or r.get('error') else 1)
except (OSError,ValueError): sys.exit(1)
PY
  then
    cp -R "$container_path/Documents/PublicPhotoResults" "$result_directory/results"
    python3 - "$result_directory/results/result.json" <<'PY'
import json,sys
r=json.load(open(sys.argv[1])); print(r['mode'])
for s in r['samples']:
 print(s['file'], '通过' if s.get('error') is None and all(s['checks'].values()) else '失败', '轮廓数', s['outlines'], s.get('error',''), [k for k,v in s['checks'].items() if not v])
print('已完成:',r['completed'],'全部通过:',r['passed'])
sys.exit(0 if r['passed'] else 1)
PY
    exit $?
  fi
  sleep 2
done
print -u2 '模拟器检查超时；保留容器现场，不写为通过。'
exit 1
