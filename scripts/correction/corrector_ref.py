#!/usr/bin/env python3
"""纠错层的参考实现（Python），和 Shared/Correction/*.swift 一一对应，用来对拍。

只做不用引擎的那部分：判断可不可疑、生成改法、用 KeyLM 打分、挑出最好的改法和该放的位置。
改法挑出来后，App 再去问引擎这个串的首选是什么、和原样的首选比，这一步在 Swift 里。
  python3 scripts/correction/corrector_ref.py golden [表目录]   → 写 Tests/Correction/golden.json（Swift 单元测试对照）
  python3 scripts/correction/corrector_ref.py <输入> [qw|t9]      → 打印一个输入的判断
参数来自 0.94 纠错交接（correction-094/HANDOFF.md）。
"""
import json, math, os, struct, sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..')

# ---------- 音节（Shared/Correction/PinyinTable.swift 的表）----------
import re
_src = open(os.path.join(ROOT, 'Shared', 'Correction', 'PinyinTable.swift'), encoding='utf-8').read()
_table = dict(re.findall(r'"(\w*)": "([a-z ]+)"', _src))
SYL = set(i + f for i, fs in _table.items() for f in fs.split())
T9 = {'2': 'abc', '3': 'def', '4': 'ghi', '5': 'jkl', '6': 'mno', '7': 'pqrs', '8': 'tuv', '9': 'wxyz'}
L2D = {c: d for d, cs in T9.items() for c in cs}
DSYL = set(''.join(L2D[c] for c in s) for s in SYL)


def prefixes(sy):
    return set(s[:k] for s in sy for k in range(1, len(s) + 1))


PRE, DPRE = prefixes(SYL), prefixes(DSYL)


def strict_prefix(s, digits=False):
    """能拼成「整音节 + 最后一个没打完的音节」的最长前缀；词中间不认零声母音节（全键盘）。"""
    sy, pre = (DSYL, DPRE) if digits else (SYL, PRE)
    n = len(s); ok = [False] * (n + 1); ok[0] = True; best = 0
    for i in range(n):
        if not ok[i]: continue
        for L in range(1, 7):
            if i + L > n: break
            p = s[i:i + L]
            if not digits and i > 0 and p[0] in 'aoe': continue
            if p in sy: ok[i + L] = True
            if p in pre: best = max(best, i + L)
    return max(best, max(i for i in range(n + 1) if ok[i]))


def all_initials(s):
    return all(c not in 'aeiouv' for c in s)


# ---------- 邻键 ----------
ROWS = ["qwertyuiop", "asdfghjkl", "zxcvbnm"]
KEYPOS = {c: (i + [0, 0.5, 1.5][r], r) for r, row in enumerate(ROWS) for i, c in enumerate(row)}
T9GRID = {'2': (1, 0), '3': (2, 0), '4': (0, 1), '5': (1, 1), '6': (2, 1), '7': (0, 2), '8': (1, 2), '9': (2, 2)}


def neighbors(c, digits):
    if digits:
        x, y = T9GRID[c]
        return [k for k, (a, b) in sorted(T9GRID.items()) if abs(a - x) + abs(b - y) == 1]
    x, y = KEYPOS[c]
    return [d for d, (x2, y2) in sorted(KEYPOS.items()) if d != c and abs(y2 - y) <= 1 and abs(x2 - x) <= 1.0]


PEN = {False: {'swap': 1.5, 'del': 2.5, 'sub': 1.5, 'ins': 1.5}, True: {'swap': 1.0, 'del': 2.0, 'sub': 1.0, 'ins': 1.0}}
MARGIN = 6.0
SECOND_EDIT = 1.0
WINDOW = 5


def edits1(s, lo, hi, digits):
    """改一处：按反、删一个（多打了）、换成邻键、补一个（漏打了）。只改 [lo, hi) 这一段。"""
    alphabet = '23456789' if digits else 'abcdefghijklmnopqrstuvwxyz'
    out = {}
    for i in range(max(0, lo), min(len(s), hi)):
        if i + 1 < len(s) and s[i] != s[i + 1]: out.setdefault(s[:i] + s[i + 1] + s[i] + s[i + 2:], 'swap')
        out.setdefault(s[:i] + s[i + 1:], 'del')
        for c in neighbors(s[i], digits): out.setdefault(s[:i] + c + s[i + 1:], 'sub')
    for i in range(max(0, lo), min(len(s), hi) + 1):
        for c in alphabet: out.setdefault(s[:i] + c + s[i:], 'ins')
    out.pop(s, None)
    return out


# ---------- KeyLM 表 ----------
class KeyLM:
    def __init__(self, path):
        self.b = open(path, 'rb').read()
        assert self.b[:4] == b'EKL1'
        self.count, self.block, self.nblocks = struct.unpack_from('<III', self.b, 4)
        self.offsets = struct.unpack_from(f'<{self.nblocks}I', self.b, 16)
        self.data = 16 + 4 * self.nblocks
        self.memo = {}

    def _first(self, block):
        o = self.data + self.offsets[block]
        n = self.b[o + 1]
        return self.b[o + 2:o + 2 + n]

    def lookup(self, key):
        """(本身的 cost, 前缀 cost)，没有时为 None。"""
        if key in self.memo: return self.memo[key]
        k = key.encode()
        lo, hi = 0, self.nblocks - 1
        while lo < hi:
            mid = (lo + hi + 1) // 2
            if self._first(mid) <= k: lo = mid
            else: hi = mid - 1
        o = self.data + self.offsets[lo]; prev = b''; res = (None, None)
        for _ in range(self.block):
            if lo * self.block + _ >= self.count: break
            shared, n = self.b[o], self.b[o + 1]
            cur = prev[:shared] + self.b[o + 2:o + 2 + n]
            e, p = self.b[o + 2 + n], self.b[o + 3 + n]
            o += 4 + n
            if cur == k:
                res = (None if e == 255 else 2.0 + e * 0.05, None if p == 255 else 2.0 + p * 0.05); break
            if cur > k: break
            prev = cur
        self.memo[key] = res
        return res

    def score(self, s, partial=True):
        """整串拆成词的最小 cost（词级 Viterbi）；最后一个词没打完时用前缀 cost（最多 8 个键）。拼不出时为 inf。"""
        n = len(s); best = [0.0] + [math.inf] * n
        for i in range(n):
            if best[i] == math.inf: continue
            for j in range(i + 1, n + 1):
                exact, pre = self.lookup(s[i:j])
                if pre is None: break
                if exact is not None and best[i] + exact < best[j]: best[j] = best[i] + exact
        res = best[n]
        if partial:
            for i in range(max(0, n - 8), n):
                if best[i] < math.inf:
                    pre = self.lookup(s[i:])[1]
                    if pre is not None and best[i] + pre < res: res = best[i] + pre
        return res


def decide(s, lm, digits):
    """返回 None（不纠）或 (改过的串, 放第几位：1 首选 / 2 第二位, 原样分, 改后分)。"""
    if not s or "'" in s: return None
    if not digits and all_initials(s): return None
    pen = PEN[digits]
    f = strict_prefix(s, digits)
    so = lm.score(s)
    best = None
    if f < len(s):
        # 拼不成：只改拼不下去的那一段附近，改一处不够再试两处。
        v1 = edits1(s, f - WINDOW, f + 1, digits)
        found = {v: pen[t] for v, t in v1.items() if strict_prefix(v, digits) == len(v)}
        if not found:
            for v, t in v1.items():
                f2 = strict_prefix(v, digits)
                for v2, t2 in edits1(v, f2 - WINDOW, f2 + 1, digits).items():
                    if strict_prefix(v2, digits) == len(v2):
                        c = pen[t] + pen[t2] + SECOND_EDIT
                        if v2 not in found or found[v2] > c: found[v2] = c
        place = 1
    else:
        # 拼得成：整串各处都试改一处，改后得像话得多才放第二位。
        found = {v: pen[t] for v, t in edits1(s, 0, len(s), digits).items() if strict_prefix(v, digits) == len(v)}
        place = 2
    for v in sorted(found):
        sv = lm.score(v) + found[v]
        if best is None or sv < best[1]: best = (v, sv)
    if best is None or not (best[1] < so - MARGIN): return None
    return best[0], place, so, best[1]


def golden(table_dir):
    inputs = json.load(open(os.path.join(ROOT, 'Tests', 'Correction', 'eval_inputs.json'), encoding='utf-8'))
    out = {}
    for layout, digits in [('qw', False), ('t9', True)]:
        lm = KeyLM(os.path.join(table_dir, f'{layout}.eklm'))
        spec = inputs[layout]
        rows = {}
        for s in sorted(set(c[2] for c in spec['cases']) | set(spec['prefixes'])):
            d = decide(s, lm, digits)
            rows[s] = None if d is None else [d[0], d[1]]
        out[layout] = rows
        print(layout, len(rows), 'inputs,', sum(1 for v in rows.values() if v), 'corrected', flush=True)
    json.dump(out, open(os.path.join(ROOT, 'Tests', 'Correction', 'golden.json'), 'w', encoding='utf-8'), ensure_ascii=False, sort_keys=True)


if __name__ == '__main__':
    if len(sys.argv) > 1 and sys.argv[1] == 'golden':
        golden(sys.argv[2] if len(sys.argv) > 2 else os.path.join(ROOT, 'Vendor', 'KeyLM'))
    else:
        s = sys.argv[1]; layout = sys.argv[2] if len(sys.argv) > 2 else 'qw'
        lm = KeyLM(os.path.join(ROOT, 'Vendor', 'KeyLM', f'{layout}.eklm'))
        print(decide(s, lm, layout == 't9'))
