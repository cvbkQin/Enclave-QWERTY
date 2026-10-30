#!/usr/bin/env python3
"""生成纠错用的「按键串 → 可能性」表：Vendor/RimeData/cn_dicts → Vendor/KeyLM/{qw,t9}.eklm。

取词库里最常用的 30 万词，按拼音连写（全键盘）或九宫格数字（九宫格）做键；
cost = ln(总词频) − ln(词频)，同一个键取最小的。每个键的所有前缀也记下来（前缀下面最常用的词的 cost），
纠错时用来给「最后一个词还没打完」打分，也用来在逐段查表时提前停下。

文件格式（小端）：
  "EKL1"、u32 条数、u32 每块条数、u32 块数、u32 块偏移[块数]，后面是数据区。
  每条：u8 和上一条相同的前缀长度（块的第一条为 0）、u8 后缀长度、后缀字节、u8 本身的 cost、u8 前缀 cost。
  cost 存成 round((cost − 2) / 0.05)，255 表示没有（这个串不是完整的键）。
条目按字节排序，先在块的第一条上二分，再在块里顺序找。整份文件只读映射，不常驻内存。
用法：python3 scripts/correction/build_keylm.py [词库目录] [输出目录]
"""
import math, os, struct, sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..')
DICTS = ['zi', 'jichu', 'duoyin', 'diming', 'mingren', 'yiren']
TOP = 300000
BLOCK = 16
BASE, STEP, NONE = 2.0, 0.05, 255
T9 = {'2': 'abc', '3': 'def', '4': 'ghi', '5': 'jkl', '6': 'mno', '7': 'pqrs', '8': 'tuv', '9': 'wxyz'}
L2D = {c: d for d, cs in T9.items() for c in cs}


def load(dict_dir):
    best = {}
    for name in DICTS:
        path = os.path.join(dict_dir, f'{name}.dict.yaml')
        for line in open(path, encoding='utf-8'):
            p = line.rstrip('\n').split('\t')
            if len(p) >= 3 and p[2].isdigit():
                w, py, wt = p[0], p[1], int(p[2])
                if w not in best or best[w][1] < wt:
                    best[w] = (py, wt)
    return best


def table(best, digits):
    items = sorted(((wt, w, py) for w, (py, wt) in best.items() if wt > 0), reverse=True)[:TOP]
    lt = math.log(sum(wt for wt, _, _ in items))
    cost = {}
    for wt, _, py in items:
        k = py.replace(' ', '')
        if digits:
            k = ''.join(L2D.get(c, '') for c in k)
        if not k or not k.isascii():
            continue
        c = lt - math.log(wt)
        if k not in cost or c < cost[k]:
            cost[k] = c
    pre = {}
    for k, c in cost.items():
        for n in range(1, len(k) + 1):
            p = k[:n]
            if p not in pre or c < pre[p]:
                pre[p] = c
    return cost, pre


def q(c):
    return NONE if c is None else max(0, min(NONE - 1, round((c - BASE) / STEP)))


def write(path, cost, pre):
    keys = sorted(pre, key=lambda k: k.encode())
    data = bytearray(); offsets = []; prev = b''
    for i, key in enumerate(keys):
        k = key.encode()
        if i % BLOCK == 0:
            offsets.append(len(data)); shared = 0
        else:
            shared = 0
            while shared < min(len(k), len(prev), 255) and k[shared] == prev[shared]:
                shared += 1
        suffix = k[shared:]
        data += bytes([shared, len(suffix)]) + suffix + bytes([q(cost.get(key)), q(pre[key])])
        prev = k
    head = b'EKL1' + struct.pack('<III', len(keys), BLOCK, len(offsets)) + struct.pack(f'<{len(offsets)}I', *offsets)
    with open(path, 'wb') as f:
        f.write(head + bytes(data))
    return len(keys), len(head) + len(data)


def main():
    dict_dir = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, 'Vendor', 'RimeData', 'cn_dicts')
    out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(ROOT, 'Vendor', 'KeyLM')
    os.makedirs(out, exist_ok=True)
    best = load(dict_dir)
    for name, digits in [('qw', False), ('t9', True)]:
        cost, pre = table(best, digits)
        n, size = write(os.path.join(out, f'{name}.eklm'), cost, pre)
        print(f'  {name}: {len(cost)} 个键，{n} 条，{size / 1e6:.1f} MB')


if __name__ == '__main__':
    main()
