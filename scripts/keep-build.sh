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

# 只认 Enclave-<版本号>（大小写都算）开头的条目，只按「-」后面的版本号排序（不看大小写，
# 否则 Enclave-0.80 会排在 enclave-0.44 前面被当成更旧的删掉），删掉最旧的。
# macOS 的 head 不支持负数，用 awk 去掉最后 KEEP 行。
old=$(ls -1 "$DEST" | grep -iE '^Enclave-[0-9]+\.[0-9]+' | sort -t- -k2,2V -k3 | awk -v keep=$KEEP '{ line[NR] = $0 } END { for (i = 1; i <= NR - keep; i++) print line[i] }' || true)
for name in $old; do
    rm -rf "${DEST:?}/$name"
    echo "已删除旧版本：$name"
done
