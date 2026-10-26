#!/bin/bash
# 把一次出版本的产物（导出的 Enclave-0.xx 文件夹或文件）放进项目里的 builds/，只留最近 5 个版本。
# 用法：scripts/keep-build.sh <产物路径> [...]    不带参数时只按规则清理 builds/。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/builds"
KEEP=5
mkdir -p "$DEST"

for item in "$@"; do
    name="$(basename "$item")"
    if [ -e "$DEST/$name" ]; then rm -rf "$DEST/$name"; fi
    mv "$item" "$DEST/"
    echo "已放进 builds/：$name"
done

# 只认 Enclave-<版本号> 开头的条目，按版本号排序，删掉最旧的。
old=$(ls -1 "$DEST" | grep -E '^Enclave-[0-9]+\.[0-9]+' | sort -V | head -n -$KEEP || true)
for name in $old; do
    rm -rf "${DEST:?}/$name"
    echo "已删除旧版本：$name"
done
