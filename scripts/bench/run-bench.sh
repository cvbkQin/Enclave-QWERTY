#!/usr/bin/env bash
# 打字性能基准（04 每次装机前在 Mac 上跑）：在模拟器上编开发版、装上，打开打字板弹出键盘，
# 键盘自己把 10 句拼音一个字母一个字母地打 3 遍（第 1 遍热身），记按键耗时中位数、P95 和内存峰值，
# 跑几次取中位数，存到 bench/results/，再和 bench/baseline.json 比，变慢或变大就以 1 退出。
#
# 用法：
#   scripts/bench/run-bench.sh                         # 默认模拟器「iPhone SE 0911b」，跑 3 次
#   scripts/bench/run-bench.sh --sim "iPhone 16" --runs 5
#   scripts/bench/run-bench.sh --no-build              # 不重新编，用上次编好的
#   scripts/bench/run-bench.sh --save-baseline         # 把这次结果存成新基线（定版后由 04 决定要不要提交）
#
# 前提：模拟器里已经添加飞地键盘（设置 › 通用 › 键盘），并关掉「连接硬件键盘」（I/O › Keyboard），
# 否则软键盘不弹，等 3 分钟后报「没拿到结果」。
# 只编开发版（INTERNAL_BUILD、PUBLIC_BUILD 都是 NO，Key 不会编进去）。Bundle ID 跟着 Base.xcconfig：有 Configs/Local.xcconfig 时
# 用里面的前缀（装到模拟器上的就是平时那个开发版），没有时是 com.example。脚本自己不读 Local.xcconfig。
# 键盘不是全键盘时基准自己切过去、跑完切回；跑完（包括中途出错）都会把调试选项清掉。
# 测的是 Debug 编译（bench 选项只在 Debug 里有，-Onone），绝对数比手机上的正式包大，只拿来和基线前后比。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SIM="iPhone SE 0911b"
RUNS=3
BUILD=1
SAVE_BASELINE=0
BASELINE="$ROOT/bench/baseline.json"
DERIVED="$ROOT/build/bench"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --sim) SIM="$2"; shift 2 ;;
    --runs) RUNS="$2"; shift 2 ;;
    --no-build) BUILD=0; shift ;;
    --baseline) BASELINE="$2"; shift 2 ;;
    --save-baseline) SAVE_BASELINE=1; shift ;;
    *) echo "不认识的参数：$1" >&2; exit 64 ;;
  esac
done

UDID="$(xcrun simctl list devices -j | python3 -c '
import json, sys
name = sys.argv[1]
for runtime, devices in json.load(sys.stdin)["devices"].items():
    for device in devices:
        if device["name"] == name and device.get("isAvailable", True):
            print(device["udid"]); sys.exit()
' "$SIM")"
[[ -n "$UDID" ]] || { echo "找不到模拟器「$SIM」" >&2; exit 1; }
echo "模拟器：$SIM（$UDID）"
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null

APP="$DERIVED/Build/Products/Debug-iphonesimulator/Enclave.app"
mkdir -p "$DERIVED"
if [[ $BUILD -eq 1 ]]; then
  echo "编译开发版（Debug，模拟器）……"
  (cd "$ROOT" && xcodegen generate --quiet)
  xcodebuild build -project "$ROOT/Enclave.xcodeproj" -scheme Enclave -configuration Debug \
    -destination "id=$UDID" -derivedDataPath "$DERIVED" \
    CODE_SIGN_IDENTITY="-" INTERNAL_BUILD=NO PUBLIC_BUILD=NO DEV_BUILD=NO \
    > "$DERIVED.log" 2>&1 || { grep -n "error:" "$DERIVED.log" | head -n 40; echo "编译失败，日志：$DERIVED.log" >&2; exit 1; }
fi
[[ -d "$APP" ]] || { echo "没有编好的 App：$APP" >&2; exit 1; }
BUNDLE="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist")"
GROUP="$(/usr/libexec/PlistBuddy -c 'Print :EnclaveAppGroup' "$APP/Info.plist" 2>/dev/null || true)"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Info.plist")"
BUILDNO="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Info.plist")"

# 不管中途怎么结束（报错、Ctrl-C），都不带 -keyboardDebug 再启动一次 App（启动时会删掉上次写进去的调试选项），再关掉，
# 模拟器上留下的是一个普通开发版。
cleanup() {
  [[ -n "${STREAM:-}" ]] && kill "$STREAM" 2>/dev/null || true
  xcrun simctl launch --terminate-running-process "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
  sleep 2
  xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
}
trap cleanup EXIT

OUT="$ROOT/bench/results"
mkdir -p "$OUT"
STAMP="$(date +%Y%m%d-%H%M%S)"
RUN_FILES=()
for i in $(seq 1 "$RUNS"); do
  echo "第 $i/$RUNS 次……"
  # 每次重装：系统会结束旧的键盘进程，基准每个键盘进程只跑一次，重装后从冷启动开始。
  xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
  xcrun simctl install "$UDID" "$APP"
  if [[ -n "$GROUP" ]]; then
    GROUP_DIR="$(xcrun simctl get_app_container "$UDID" "$BUNDLE" "$GROUP" 2>/dev/null || true)"
    [[ -n "$GROUP_DIR" ]] && rm -f "$GROUP_DIR/Library/Diagnostics/bench.json"
  fi
  LOG="$OUT/.stream-$STAMP-$i.log"
  xcrun simctl spawn "$UDID" log stream --style compact \
    --predicate 'subsystem == "app.enclave.keyboard" AND category == "Bench"' > "$LOG" 2>&1 &
  STREAM=$!
  sleep 2
  xcrun simctl launch --terminate-running-process "$UDID" "$BUNDLE" -keyboardDebug bench -playground >/dev/null
  LINE=""
  for _ in $(seq 1 180); do
    LINE="$(grep -o 'ENCLAVE_BENCH_RESULT .*' "$LOG" | head -n 1 || true)"
    [[ -n "$LINE" ]] && break
    sleep 1
  done
  kill "$STREAM" 2>/dev/null || true
  wait "$STREAM" 2>/dev/null || true
  STREAM=""
  rm -f "$LOG"
  FILE="$OUT/$VERSION-$BUILDNO-$STAMP-run$i.json"
  if [[ -n "$LINE" ]]; then
    printf '%s\n' "${LINE#ENCLAVE_BENCH_RESULT }" > "$FILE"
  elif [[ -n "${GROUP_DIR:-}" && -f "$GROUP_DIR/Library/Diagnostics/bench.json" ]]; then
    cp "$GROUP_DIR/Library/Diagnostics/bench.json" "$FILE"
  else
    echo "第 $i 次没拿到结果：键盘没弹出来？看看模拟器里是否添加了飞地键盘、是否关了硬件键盘。" >&2
    continue
  fi
  if ! python3 -c 'import json,sys; r=json.load(open(sys.argv[1])); sys.exit("  键盘报错：" + r["error"]) if "error" in r else print("  按键中位数 %.2f ms，P95 %.2f ms，内存峰值 %.1f MB" % (r["keyMedianMs"], r["keyP95Ms"], r["memPeakMB"]))' "$FILE"; then
    mv "$FILE" "$FILE.error"
    continue
  fi
  RUN_FILES+=("$FILE")
done

[[ ${#RUN_FILES[@]} -gt 0 ]] || { echo "一次结果都没拿到" >&2; exit 1; }
RESULT="$OUT/$VERSION-$BUILDNO-$STAMP.json"
python3 "$ROOT/scripts/bench/compare.py" --merge "${RUN_FILES[@]}" > "$RESULT"
echo "结果：$RESULT"
if [[ $SAVE_BASELINE -eq 1 ]]; then
  cp "$RESULT" "$BASELINE"
  echo "已存为基线：$BASELINE"
  exit 0
fi
python3 "$ROOT/scripts/bench/compare.py" "$BASELINE" "$RESULT"
