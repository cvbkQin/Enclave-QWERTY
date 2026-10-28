#!/bin/bash
# 下载整句模型（万象语法模型 wanxiang-lts-zh-hans.gram，约 380MB，CC BY 4.0）到 Vendor/Grammar/，打内测包前跑一次。
# Vendor/ 不进 Git。断了再跑会接着下。大陆网络慢可以换地址：GRAMMAR_URL=<镜像地址> scripts/fetch-grammar.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/Vendor/Grammar"
FILE="$DEST/wanxiang-lts-zh-hans.gram"
URL="${GRAMMAR_URL:-https://github.com/amzxyz/rime-wanxiang-data/releases/download/LTS/wanxiang-lts-zh-hans.gram}"
mkdir -p "$DEST"

if [ -f "$FILE" ] && [ "$(head -c 14 "$FILE")" = "Rime::Grammar/" ]; then
    echo "已经有了：$FILE（$(($(stat -f%z "$FILE") / 1000000)) MB）"
    exit 0
fi

curl -L --fail --retry 5 --retry-delay 4 -C - -o "$FILE.part" "$URL"
if [ "$(head -c 14 "$FILE.part")" != "Rime::Grammar/" ]; then
    echo "下载的文件不是整句模型（文件头不对），删掉了。" >&2
    rm -f "$FILE.part"
    exit 1
fi
size=$(stat -f%z "$FILE.part")
if [ "$size" -lt 300000000 ]; then
    echo "文件只有 $((size / 1000000)) MB，像是没下完，再跑一次接着下。" >&2
    exit 1
fi
mv "$FILE.part" "$FILE"
echo "下好了：$FILE（$((size / 1000000)) MB）"
