#!/bin/bash
# 键盘扩展的 Run Script：内测包（INTERNAL_BUILD=YES）把整句模型拷进扩展包里；别的包确保包里没有它。
# 模型先用 scripts/fetch-grammar.sh 下载到 Vendor/Grammar/，没有就停编。
set -euo pipefail

NAME="wanxiang-lts-zh-hans.gram"
SRC="$SRCROOT/Vendor/Grammar/$NAME"
DST="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/$NAME"

if [ "${INTERNAL_BUILD:-NO}" != "YES" ]; then
    rm -f "$DST"
    exit 0
fi
if [ ! -f "$SRC" ] || [ "$(head -c 14 "$SRC")" != "Rime::Grammar/" ]; then
    echo "error: 内测包要自带整句模型，但 Vendor/Grammar/$NAME 不存在或不对。先运行 scripts/fetch-grammar.sh。" >&2
    exit 1
fi
if [ "$(stat -f%z "$SRC")" -lt 300000000 ]; then
    echo "error: Vendor/Grammar/$NAME 太小，像是没下完。再运行一次 scripts/fetch-grammar.sh。" >&2
    exit 1
fi
mkdir -p "$(dirname "$DST")"
# 一样就不再拷 380MB。
if [ ! -f "$DST" ] || ! cmp -s "$SRC" "$DST"; then
    cp "$SRC" "$DST"
fi
echo "整句模型已放进键盘扩展：$(($(stat -f%z "$DST") / 1000000)) MB"
