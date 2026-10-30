#!/usr/bin/env python3
"""给纠错测试结果打分（结果由 scripts/correction/run-eval.sh 取回）。

每种手误：首选就是想要的字的比例、想要的字在前两位的比例（%）。
带 --base 时再和另一份结果比：正常输入首选掉了多少，打到一半的中间状态首选、第二位改了几个（回归门槛：首选掉不超过 0.5 个百分点，中间状态首选改动为 0）。
用法：python3 scripts/correction/score.py 结果.json [--base 基线结果.json]
"""
import argparse, json, os

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..')
KINDS = ['clean', 'swap', 'miss', 'double', 'neighbor', 'two']
NAMES = {'clean': '正常', 'swap': '按反', 'miss': '漏打', 'double': '多打', 'neighbor': '按到邻键', 'two': '错两处'}


def rates(cases, res):
    t1 = dict.fromkeys(KINDS, 0); t2 = dict.fromkeys(KINDS, 0); n = dict.fromkeys(KINDS, 0)
    for kind, want, typed in cases:
        cands = res.get(typed, [])
        n[kind] += 1
        t1[kind] += bool(cands) and cands[0] == want
        t2[kind] += want in cands[:2]
    return {k: (100 * t1[k] / n[k], 100 * t2[k] / n[k], n[k]) for k in KINDS if n[k]}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('result')
    ap.add_argument('--base')
    ap.add_argument('--inputs', default=os.path.join(ROOT, 'Tests', 'Correction', 'eval_inputs.json'))
    a = ap.parse_args()
    inputs = json.load(open(a.inputs, encoding='utf-8'))
    cur = json.load(open(a.result, encoding='utf-8'))
    base = json.load(open(a.base, encoding='utf-8')) if a.base else None
    print(f"词库 {cur.get('deployedVersion')} · 整句模型 {'有' if cur.get('grammar') else '无'} · 构建 {cur.get('app')} · 用时 {cur.get('seconds', 0):.0f} 秒")
    for layout, spec in inputs.items():
        res = cur['results'].get(layout, {})
        r = rates(spec['cases'], res)
        rb = rates(spec['cases'], base['results'].get(layout, {})) if base else None
        print(f"\n{layout}（{spec['schema']}）  首选 / 前两位")
        for k, (top1, top2, n) in r.items():
            line = f"  {NAMES[k]:<6}{top1:5.1f} / {top2:5.1f}   ({n})"
            if rb and k in rb:
                line += f"   基线 {rb[k][0]:5.1f} / {rb[k][1]:5.1f}   变化 {top1 - rb[k][0]:+5.1f} / {top2 - rb[k][1]:+5.1f}"
            print(line)
        if base:
            bres = base['results'].get(layout, {})
            first = sum(1 for p in spec['prefixes'] if res.get(p, [])[:1] != bres.get(p, [])[:1])
            second = sum(1 for p in spec['prefixes'] if res.get(p, [])[1:2] != bres.get(p, [])[1:2])
            print(f"  打到一半的 {len(spec['prefixes'])} 个中间状态：首选改动 {first}，第二位改动 {second}")


if __name__ == '__main__':
    main()
