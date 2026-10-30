#!/usr/bin/env python3
"""生成纠错测试要喂给引擎的输入：Tests/Correction/chunks.json（266 段日常句子）→ Tests/Correction/eval_inputs.json。

每段按原样打一次，再按五种手误（按反、漏打、多打、按到邻键、错两处）各随机造一次，全键盘、九宫格各一份；
另外列出每段打到一半的所有中间状态（第 2 个键起），专门看纠错会不会干扰正常打字。
造手误的规则和随机种子与 0.94 纠错原型（correction-094/prototype/typos.py）相同，数字可以直接对照。
用法：python3 scripts/correction/make_inputs.py
"""
import json, os, random

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..')
DIR = os.path.join(ROOT, 'Tests', 'Correction')

T9 = {'2': 'abc', '3': 'def', '4': 'ghi', '5': 'jkl', '6': 'mno', '7': 'pqrs', '8': 'tuv', '9': 'wxyz'}
L2D = {c: d for d, cs in T9.items() for c in cs}

# 全键盘按 iPhone 的错位排：键宽为单位，第二、三排右移半个、一个半键。
ROWS = ["qwertyuiop", "asdfghjkl", "zxcvbnm"]
KEYPOS = {c: (i + [0, 0.5, 1.5][r], r) for r, row in enumerate(ROWS) for i, c in enumerate(row)}
T9GRID = {'2': (1, 0), '3': (2, 0), '4': (0, 1), '5': (1, 1), '6': (2, 1), '7': (0, 2), '8': (1, 2), '9': (2, 2)}


def qneigh(c):
    x, y = KEYPOS[c]
    return [d for d, (x2, y2) in KEYPOS.items() if d != c and abs(y2 - y) <= 1 and abs(x2 - x) <= 1.0]


def t9neigh(d):
    x, y = T9GRID[d]
    return [k for k, (a, b) in T9GRID.items() if (abs(a - x) + abs(b - y)) == 1]


def make(s, kind, rnd, layout):
    neigh = qneigh if layout == 'qw' else t9neigh
    n = len(s)
    if kind == 'swap':
        cand = [i for i in range(n - 1) if s[i] != s[i + 1]]
        if not cand: return None
        i = rnd.choice(cand); return s[:i] + s[i + 1] + s[i] + s[i + 2:]
    if kind == 'miss':
        if n < 3: return None
        i = rnd.randrange(1, n); return s[:i] + s[i + 1:]
    if kind == 'double':
        i = rnd.randrange(n); return s[:i + 1] + s[i] + s[i + 1:]
    if kind == 'neighbor':
        i = rnd.randrange(n); return s[:i] + rnd.choice(neigh(s[i])) + s[i + 1:]
    if kind == 'two':
        k1, k2 = rnd.sample(['swap', 'miss', 'double', 'neighbor'], 2)
        a = make(s, k1, rnd, layout)
        return make(a, k2, rnd, layout) if a else None


KINDS = ['clean', 'swap', 'miss', 'double', 'neighbor', 'two']


def cases(chunks, layout, seed=1):
    rnd = random.Random(seed); out = []
    for c in chunks:
        s = c[layout]
        for k in KINDS:
            t = s if k == 'clean' else make(s, k, rnd, layout)
            if t and (k == 'clean' or t != s): out.append([k, c['text'], t])
    return out


def main():
    chunks = json.load(open(os.path.join(DIR, 'chunks.json'), encoding='utf-8'))
    out = {}
    for layout, schema in [('qw', 'enclave'), ('t9', 'enclave_t9')]:
        out[layout] = {
            'schema': schema,
            'cases': cases(chunks, layout),
            'prefixes': sorted({c[layout][:i] for c in chunks for i in range(2, len(c[layout]))}),
        }
    path = os.path.join(DIR, 'eval_inputs.json')
    json.dump(out, open(path, 'w', encoding='utf-8'), ensure_ascii=False, indent=0)
    for layout, v in out.items():
        print(layout, len(v['cases']), 'cases,', len(v['prefixes']), 'prefixes')


if __name__ == '__main__':
    main()
