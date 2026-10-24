#!/usr/bin/env bash
# 下载拼音引擎 librime（iOS 预编译静态库）和万象拼音词库，放到 Vendor/ 下。
# 生成工程前运行一次：bash scripts/fetch-rime.sh && xcodegen generate
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR="$ROOT/Vendor"

# librime 1.16 + librime-lua，构建脚本见 https://github.com/thomfang/LibrimeKit-iOS
FRAMEWORKS_URL="https://github.com/thomfang/LibrimeKit-iOS/releases/download/v0.2.2/Frameworks.tgz"
FRAMEWORKS_SHA256="43a0921538827fedb2679e5d26bb389dec3759d44ccdcfd439e8ec21a7f93223"

# 词库数据来自万象拼音 https://github.com/amzxyz/rime_wanxiang （CC BY 4.0，可商用，需署名）。
# 只用它的词库，方案文件是自己写的，在 Configs/Rime/。
WANXIANG_COMMIT="f9e2d6cf4d63bf2637ab5662e6a94fc0c13bac9f"
CONFIG="$ROOT/Configs/Rime"

# 键盘自带的编译好的词库由 scripts/prebuild-rime.sh 生成；没生成时放个空目录，工程照样能编。
mkdir -p "$VENDOR/RimeBuild"

STAMP="$VENDOR/.stamp"
# 方案文件或整理脚本改了也要重新生成。
inputs_hash() {
  (cd "$ROOT" && find scripts/fetch-rime.sh scripts/build-dict.py Configs/Rime -type f | LC_ALL=C sort | xargs shasum -a 256) \
    | shasum -a 256 | cut -d' ' -f1
}
WANT="$FRAMEWORKS_SHA256 $WANXIANG_COMMIT $(inputs_hash)"
if [[ -f "$STAMP" && "$(cat "$STAMP")" == "$WANT" ]]; then
  echo "Vendor/ 已是最新"
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "下载 librime…"
curl -fsSL --retry 3 -o "$TMP/Frameworks.tgz" "$FRAMEWORKS_URL"
echo "$FRAMEWORKS_SHA256  $TMP/Frameworks.tgz" | shasum -a 256 -c -
rm -rf "$VENDOR/Frameworks"
mkdir -p "$VENDOR/Frameworks"
tar -xzf "$TMP/Frameworks.tgz" -C "$VENDOR/Frameworks"

echo "下载万象词库…"
git init -q "$TMP/wanxiang"
git -C "$TMP/wanxiang" fetch -q --depth 1 https://github.com/amzxyz/rime_wanxiang.git "$WANXIANG_COMMIT"
git -C "$TMP/wanxiang" -c advice.detachedHead=false checkout -q FETCH_HEAD

DATA="$VENDOR/RimeData"
rm -rf "$DATA"
mkdir -p "$DATA"
cp -R "$CONFIG"/. "$DATA/"
echo "整理词库…"
python3 -I "$ROOT/scripts/build-dict.py" "$TMP/wanxiang" "$DATA"
cp "$TMP/wanxiang/LICENSE" "$DATA/LICENSE-wanxiang"

# App 用它判断词库要不要重新部署。
echo "$WANXIANG_COMMIT-$(inputs_hash | cut -c1-8)" > "$DATA/data_version.txt"

echo "$WANT" > "$STAMP"
echo "完成：$(du -sh "$VENDOR/Frameworks" | cut -f1) 引擎，$(du -sh "$DATA" | cut -f1) 词库"
