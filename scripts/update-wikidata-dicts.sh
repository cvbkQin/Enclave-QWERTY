#!/bin/bash
# T106：在 Mac 上一条命令拉 Wikidata 的景点、机场、地标、人物中文名，标好拼音，写到仓库外面的目录。
#   bash scripts/update-wikidata-dicts.sh [输出目录，默认 ~/Enclave-QWERTY/wikidata]
# 要能上外网（wikidata.org、github.com）；云端会话连不上 wikidata.org，所以在 Mac 上跑。
# 跑完把输出目录里的 lvyou.tsv、renwu.tsv、review-*.tsv、excluded.tsv 交给 01 生成词库（build-ext-dicts.py --wikidata），
# 待审文件交 05。这些文件都不进仓库（仓库是公开的，待审文件里是要人工看的敏感人名）。
# 中途断了再跑一次就行：下好的原始数据不重下。
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$HOME/Enclave-QWERTY/wikidata}"
RAW="$OUT/raw"
# 和 scripts/fetch-rime.sh 用同一版万象（拼音按它标）。
WANXIANG_COMMIT="$(sed -n 's/^WANXIANG_COMMIT="\(.*\)"$/\1/p' "$ROOT/scripts/fetch-rime.sh")"
WANXIANG="$OUT/wanxiang-$WANXIANG_COMMIT"
case "$OUT" in "$ROOT"/*) echo "输出目录不要放在仓库里：$OUT" >&2; exit 1;; esac
mkdir -p "$RAW"
if [ ! -d "$WANXIANG/dicts" ]; then
  echo "下载万象拼音词库（标拼音用）…"
  rm -rf "$WANXIANG.tmp"
  git init -q "$WANXIANG.tmp"
  git -C "$WANXIANG.tmp" fetch -q --depth 1 https://github.com/amzxyz/rime_wanxiang.git "$WANXIANG_COMMIT"
  git -C "$WANXIANG.tmp" -c advice.detachedHead=false checkout -q FETCH_HEAD
  mv "$WANXIANG.tmp" "$WANXIANG"
fi
echo "从 Wikidata 下载（几分钟到半小时）…"
python3 "$ROOT/scripts/fetch-wikidata-names.py" fetch "$RAW"
echo "整理、标拼音…"
python3 "$ROOT/scripts/fetch-wikidata-names.py" parse "$RAW" "$WANXIANG/dicts" "$OUT"
echo
echo "好了，结果在 $OUT："
ls -lh "$OUT"/*.tsv
