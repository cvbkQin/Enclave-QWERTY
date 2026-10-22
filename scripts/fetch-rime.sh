#!/usr/bin/env bash
# 下载拼音引擎 librime（iOS 预编译静态库）和雾凇拼音词库，放到 Vendor/ 下。
# 生成工程前运行一次：bash scripts/fetch-rime.sh && xcodegen generate
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR="$ROOT/Vendor"

# librime 1.16 + librime-lua，构建脚本见 https://github.com/thomfang/LibrimeKit-iOS
FRAMEWORKS_URL="https://github.com/thomfang/LibrimeKit-iOS/releases/download/v0.2.2/Frameworks.tgz"
FRAMEWORKS_SHA256="43a0921538827fedb2679e5d26bb389dec3759d44ccdcfd439e8ec21a7f93223"

# 雾凇拼音 https://github.com/iDvel/rime-ice （GPL-3.0）
RIME_ICE_COMMIT="da1fbe602e38f26db846fa10120ee64c2b0324c0"

STAMP="$VENDOR/.stamp"
WANT="$FRAMEWORKS_SHA256 $RIME_ICE_COMMIT $(shasum -a 256 "$0" | cut -d' ' -f1)"
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

echo "下载雾凇拼音…"
git init -q "$TMP/rime-ice"
git -C "$TMP/rime-ice" fetch -q --depth 1 https://github.com/iDvel/rime-ice.git "$RIME_ICE_COMMIT"
git -C "$TMP/rime-ice" -c advice.detachedHead=false checkout -q FETCH_HEAD

DATA="$VENDOR/RimeData"
rm -rf "$DATA"
mkdir -p "$DATA/cn_dicts"
SRC="$TMP/rime-ice"
cp "$SRC"/default.yaml "$SRC"/rime_ice.schema.yaml "$SRC"/rime_ice.dict.yaml "$SRC"/t9.schema.yaml \
   "$SRC"/melt_eng.schema.yaml "$SRC"/melt_eng.dict.yaml \
   "$SRC"/radical_pinyin.schema.yaml "$SRC"/radical_pinyin.dict.yaml \
   "$SRC"/symbols_v.yaml "$SRC"/symbols_caps_v.yaml "$SRC"/custom_phrase.txt "$DATA/"
cp -R "$SRC"/en_dicts "$SRC"/lua "$SRC"/opencc "$DATA/"
# 腾讯词库很大，手机上部署要好几分钟，先不带。
for dict in 8105 base ext others; do
  cp "$SRC/cn_dicts/$dict.dict.yaml" "$DATA/cn_dicts/"
done
sed -i.bak -E 's|^([[:space:]]*)- cn_dicts/tencent|\1# - cn_dicts/tencent|' "$DATA/rime_ice.dict.yaml"
rm -f "$DATA/rime_ice.dict.yaml.bak"
cp "$SRC/LICENSE" "$DATA/LICENSE-rime-ice"

# 只部署需要的方案。
cat > "$DATA/default.custom.yaml" <<'YAML'
patch:
  schema_list:
    - schema: rime_ice
    - schema: t9
YAML

# 九宫格：拼写栏显示拼音而不是数字。
cat > "$DATA/t9.custom.yaml" <<'YAML'
patch:
  engine/filters/@before 0: lua_filter@*t9_preedit
YAML
touch "$DATA/custom_phrase_t9.txt"

# App 用它判断词库要不要重新部署。
echo "$RIME_ICE_COMMIT-$(shasum -a 256 "$0" | cut -c1-8)" > "$DATA/data_version.txt"

echo "$WANT" > "$STAMP"
echo "完成：$(du -sh "$VENDOR/Frameworks" | cut -f1) 引擎，$(du -sh "$DATA" | cut -f1) 词库"
