#!/usr/bin/env python3
"""生成 App/DoublePinyinPracticeData.swift：双拼练习（双拼调研 P3-11）的基础字、词组、短句。

用法：python3 scripts/practice/gen_practice.py ESSAY CORPUS OUT
  ESSAY  Rime 八股文 essay.txt（rime-essay，繁体，脚本里转简体）
  CORPUS 纠错语料 corpus.txt（每行一段中文，按标点切短句）
  OUT    输出的 Swift 文件
要 pip 装 pypinyin、opencc-python-reimplemented。音节表读 Shared/Correction/PinyinTable.swift。
"""
import re, sys, collections, pathlib
from pypinyin import lazy_pinyin
from opencc import OpenCC

ROOT = pathlib.Path(__file__).resolve().parents[2]
table = (ROOT / "Shared/Correction/PinyinTable.swift").read_text(encoding="utf-8")
SYL = set()
for initial, finals in re.findall(r'"([a-z]*)": "([a-z ]+)"', table):
    SYL.update(initial + f for f in finals.split())
t2s = OpenCC("t2s")
freq = collections.Counter()
for line in open(sys.argv[1], encoding="utf-8"):
    w, f = line.rstrip("\n").split("\t")[:2]; freq[t2s.convert(w)] += int(f)
def py(word):
    r = lazy_pinyin(word, errors="ignore")
    return r if len(r) == len(word) and all(s in SYL for s in r) else None
# 基础：每个音节一个最常用的字（单字频率），再补到 600 个常用字
chars = sorted((w for w in freq if len(w) == 1 and '一' <= w <= '鿿'), key=lambda w: -freq[w])
best = {}
for c in chars[:6000]:
    p = py(c)
    if not p: continue
    s = p[0]
    if s not in best: best[s] = c
basic = [(best[s], s) for s in sorted(best, key=lambda s: -freq[best[s]])]
seen = {c for c,_ in basic}
for c in chars[:800]:
    if c in seen: continue
    p = py(c)
    if p: basic.append((c, p[0])); seen.add(c)
# 词组：常用两三字词
words = sorted((w for w in freq if 2 <= len(w) <= 3 and all('一' <= ch <= '鿿' for ch in w)), key=lambda w: -freq[w])
wl = []
for w in words:
    p = py(w)
    if p: wl.append((w, " ".join(p)))
    if len(wl) >= 400: break
# 短句：项目自己的语料按标点切成 4–12 字的短句
sent = []
for line in open(sys.argv[2], encoding="utf-8"):
    for piece in re.split(r"[，。！？；、：“”（）,.!?]", line.strip()):
        piece = piece.strip()
        if 4 <= len(piece) <= 12 and all('一' <= ch <= '鿿' for ch in piece):
            p = py(piece)
            if p and piece not in [s for s,_ in sent]: sent.append((piece, " ".join(p)))
print(len(SYL), len(best), len(basic), len(wl), len(sent), file=sys.stderr)
def block(items): return "\n".join(f"{a}\t{b}" for a,b in items)
out = '''import Foundation

// 由 scripts/practice/gen_practice.py 生成（双拼调研 P3-11），别手改。
// 基础：每个音节一个最常用的字（频率来自 Rime 八股文 essay，转成简体），再补到常用字；词组：常用两三字词；短句：纠错语料按标点切的短句。
// 拼音用 pypinyin 标（ü 写 v，j q x y 后写 u），只留音节表里有的。每行「字词<TAB>空格分开的全拼」。
enum DoublePinyinPracticeData {
    static let basic = """
%s
"""

    static let words = """
%s
"""

    static let sentences = """
%s
"""
}
''' % (block(basic), block(wl), block(sent))
open(sys.argv[3], "w", encoding="utf-8").write(out)
