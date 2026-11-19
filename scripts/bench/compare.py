#!/usr/bin/env python3
"""打字性能基准的结果：合并几次、和基线比。

  compare.py --merge run1.json run2.json ...   几次结果每项取中位数，输出一份（JSON 到标准输出）
  compare.py baseline.json result.json         和基线比：没超门槛 0；按键变慢、内存变大超过门槛 1；没有基线或缺字段 2

门槛（模拟器上同一台机器前后比；模拟器的绝对数和手机不一样，只看变化）：
  按键耗时中位数  比基线多 20% 且多 0.5 ms 以上
  按键耗时 P95    比基线多 30% 且多 2 ms 以上
  内存峰值        比基线多 10 MB 以上
首选变了（firstCandidates）只提示、不算失败：改词库、改排序时本来就会变。
"""
import json
import statistics
import sys

# (字段, 名字, 单位, 比例门槛, 绝对门槛)
CHECKS = [
    ("keyMedianMs", "按键耗时中位数", "ms", 0.20, 0.5),
    ("keyP95Ms", "按键耗时 P95", "ms", 0.30, 2.0),
    ("memPeakMB", "内存峰值", "MB", None, 10.0),
]
INFO = [
    ("engineMedianMs", "引擎耗时中位数", "ms"),
    ("engineP95Ms", "引擎耗时 P95", "ms"),
    ("keyMaxMs", "最慢一个键", "ms"),
    ("coldSentenceMs", "冷启动第一句", "ms"),
    ("memStartMB", "开始时内存", "MB"),
    ("memEndMB", "打完内存", "MB"),
]


def load(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def merge(paths):
    runs = [load(p) for p in paths]
    merged = dict(runs[0])
    for key, value in runs[0].items():
        if isinstance(value, (int, float)) and not isinstance(value, bool):
            values = [r[key] for r in runs if isinstance(r.get(key), (int, float))]
            merged[key] = round(statistics.median(values), 2)
    merged["runs"] = len(runs)
    merged["keyMedianMsRuns"] = [r.get("keyMedianMs") for r in runs]
    merged["memPeakMBRuns"] = [r.get("memPeakMB") for r in runs]
    json.dump(merged, sys.stdout, ensure_ascii=False, indent=2, sort_keys=True)
    print()


def compare(baseline_path, result_path):
    result = load(result_path)
    try:
        base = load(baseline_path)
    except FileNotFoundError:
        print(f"还没有基线（{baseline_path}）。这次的数：")
        for key, name, unit, *_ in CHECKS:
            print(f"  {name}：{result.get(key)} {unit}")
        print("没有基线，什么都没比（以 2 退出）。确认没问题后用 run-bench.sh --save-baseline 存一份。")
        return 2
    print(f"基线 {base.get('version')}（{base.get('build')}，{base.get('date', '')[:10]}，{base.get('device')}）"
          f" → 这次 {result.get('version')}（{result.get('build')}，{result.get('device')}）")
    if base.get("device") != result.get("device"):
        print("  注意：模拟器和基线不是同一台，数字只能大概参考。")
    missing = [name for key, name, *_ in CHECKS if not isinstance(base.get(key), (int, float))
               or not isinstance(result.get(key), (int, float))]
    if missing:
        print("基线或这次结果缺这几项，没法比（以 2 退出）：" + "、".join(missing))
        return 2
    failed = []
    for key, name, unit, ratio, absolute in CHECKS:
        old, new = base[key], result[key]
        diff = new - old
        bad = diff > absolute and (ratio is None or diff > old * ratio)
        pct = f"{diff / old * 100:+.0f}%" if old else ""
        print(f"  {'✗' if bad else '✓'} {name}：{old} → {new} {unit}（{diff:+.2f} {unit} {pct}）")
        if bad:
            failed.append(name)
    for key, name, unit in INFO:
        if key in base and key in result:
            print(f"    {name}：{base[key]} → {result[key]} {unit}")
    changed = [(a, b) for a, b in zip(base.get("firstCandidates", []), result.get("firstCandidates", [])) if a != b]
    if changed:
        print(f"  提示：{len(changed)} 句的首选变了（改词库、排序时正常）：" + "；".join(f"{a} → {b}" for a, b in changed[:5]))
    if failed:
        print("变慢或变大：" + "、".join(failed) + "。先再跑一次排除偶然；还在就别装机，报给 01 查。")
        return 1
    print("没有变慢。")
    return 0


def main(argv):
    if len(argv) >= 2 and argv[0] == "--merge":
        merge(argv[1:])
        return 0
    if len(argv) == 2:
        return compare(argv[0], argv[1])
    print(__doc__)
    return 64


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
