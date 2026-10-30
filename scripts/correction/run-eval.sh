#!/usr/bin/env bash
# 在模拟器或手机上跑纠错测试：把 Tests/Correction/eval_inputs.json 放进 App 的 Documents，带 -rimeEval 启动，
# 等 App 把每个输入喂给引擎、写出前 5 个候选，再取回到 Tests/Correction/results/<名字>.json。
# App 要是 Debug 版，并且已经装好、打开过一次（词库部署好）。
# 用法：
#   bash scripts/correction/run-eval.sh sim  <名字> [bundle id]           # 当前启动的模拟器
#   bash scripts/correction/run-eval.sh device <名字> <设备 id> [bundle id] # 连着的手机（xcrun devicectl list devices 看 id）
# 然后：python3 scripts/correction/score.py Tests/Correction/results/<名字>.json [--base 另一个结果]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MODE="${1:?sim 或 device}"
NAME="${2:?结果名字}"
PREFIX="$( (sed -n 's/^BUNDLE_ID_PREFIX *= *//p' "$ROOT/Configs/Local.xcconfig" 2>/dev/null || true) | tail -1)"
INPUTS="$ROOT/Tests/Correction/eval_inputs.json"
OUT_DIR="$ROOT/Tests/Correction/results"
mkdir -p "$OUT_DIR"
[[ -f "$INPUTS" ]] || python3 "$ROOT/scripts/correction/make_inputs.py"

if [[ "$MODE" == sim ]]; then
  BUNDLE="${3:-${PREFIX:-com.example}.enclave}"
  DATA="$(xcrun simctl get_app_container booted "$BUNDLE" data)"
  mkdir -p "$DATA/Documents"
  rm -f "$DATA/Documents/rime-eval.json" "$DATA/Documents/rime-eval.done"
  cp "$INPUTS" "$DATA/Documents/rime-eval-inputs.json"
  xcrun simctl launch --terminate-running-process booted "$BUNDLE" -rimeEval >/dev/null
  for _ in $(seq 1 1200); do
    [[ -f "$DATA/Documents/rime-eval.done" ]] && break
    sleep 1
  done
  [[ -f "$DATA/Documents/rime-eval.json" ]] || { echo "没有拿到结果：$(cat "$DATA/Documents/rime-eval.done" 2>/dev/null || echo 超时)" >&2; exit 1; }
  cp "$DATA/Documents/rime-eval.json" "$OUT_DIR/$NAME.json"
else
  DEVICE="${3:?设备 id}"
  BUNDLE="${4:-${PREFIX:-com.example}.enclave}"
  TMP="$(mktemp -d)"
  xcrun devicectl device copy to --device "$DEVICE" --domain-type appDataContainer --domain-identifier "$BUNDLE" \
    --source "$INPUTS" --destination Documents/rime-eval-inputs.json >/dev/null
  xcrun devicectl device process launch --device "$DEVICE" --terminate-existing "$BUNDLE" -rimeEval >/dev/null
  for _ in $(seq 1 240); do
    sleep 5
    if xcrun devicectl device copy from --device "$DEVICE" --domain-type appDataContainer --domain-identifier "$BUNDLE" \
         --source Documents/rime-eval.done --destination "$TMP/done" >/dev/null 2>&1; then
      break
    fi
  done
  xcrun devicectl device copy from --device "$DEVICE" --domain-type appDataContainer --domain-identifier "$BUNDLE" \
    --source Documents/rime-eval.json --destination "$OUT_DIR/$NAME.json" >/dev/null
  rm -rf "$TMP"
fi
echo "结果：$OUT_DIR/$NAME.json"
python3 "$ROOT/scripts/correction/score.py" "$OUT_DIR/$NAME.json"
