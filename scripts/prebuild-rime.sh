#!/usr/bin/env bash
# 生成键盘自带的编译好的词库 Vendor/RimeBuild：不开完全访问时键盘读不到 App 部署的词库，就用这一份。
# 做法：在已启动的模拟器里装好 App、打开一次让它部署完词库（「拼音词库」页显示已就绪），
# 再运行本脚本，把模拟器共享目录里的方案和编译结果拷出来。编译结果和设备上同一版 librime 通用。
# 用法：bash scripts/prebuild-rime.sh [App 的 bundle id]，默认读 Configs/Local.xcconfig 的前缀。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# 没有 Local.xcconfig 时（参数给了 bundle id）也要能跑：sed 读不到文件不算失败。
PREFIX="$( (sed -n 's/^BUNDLE_ID_PREFIX *= *//p' "$ROOT/Configs/Local.xcconfig" 2>/dev/null || true) | tail -1)"
BUNDLE="${1:-${PREFIX:-com.example}.enclave}"
GROUP_ID="group.${BUNDLE}"

GROUP="$(xcrun simctl get_app_container booted "$BUNDLE" groups | awk -v id="$GROUP_ID" '$1 == id { print $2 }')"
if [[ -z "$GROUP" || ! -d "$GROUP/Rime/user/build" ]]; then
  echo "模拟器里没找到部署好的词库（$GROUP_ID）。先在模拟器里打开 App 等词库部署完。" >&2
  exit 1
fi

OUT="$ROOT/Vendor/RimeBuild"
rm -rf "$OUT"
mkdir -p "$OUT"
# 方案和配置（不要词典源文件，编译结果里已经有了）。
rsync -a --exclude '*.dict.yaml' --exclude 'cn_dicts/' --exclude 'en_dicts/' "$GROUP/Rime/shared/" "$OUT/"
rsync -a "$GROUP/Rime/user/build/" "$OUT/build/"
echo "完成：$(du -sh "$OUT" | cut -f1)，版本 $(cat "$OUT/data_version.txt" 2>/dev/null || echo 未知)"
