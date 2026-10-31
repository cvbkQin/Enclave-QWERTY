#!/usr/bin/env python3
"""把 OpenCC 的简转繁词表整理成键盘用的两个文件（繁体输出 B5）。

用法：python3 scripts/build-s2t.py <OpenCC 的 data/dictionary 目录>
输入：STCharacters.txt、STPhrases.txt（OpenCC ver.1.1.9，Apache-2.0）
输出：Shared/Traditional/s2t-chars.tsv、s2t-phrases.tsv
- 每行「简体<TAB>繁体」，一个简体对应多个繁体时只取 OpenCC 排在第一的（和 OpenCC s2t 的默认结果一样）
- 词表按简体的 UTF-8 字节排序，键盘里直接二分查找，不用整张表读进内存
"""
import sys
from pathlib import Path

def load(path):
    table = {}
    for line in Path(path).read_text(encoding="utf-8").splitlines():
        if not line or line.startswith("#"):
            continue
        simp, _, trad = line.partition("\t")
        options = trad.split()
        if simp and options and simp not in table:
            table[simp] = options[0]
    return table

def write(table, path, drop_same=True):
    rows = sorted(((k, v) for k, v in table.items() if not (drop_same and k == v)), key=lambda kv: kv[0].encode("utf-8"))
    Path(path).write_text("".join(f"{k}\t{v}\n" for k, v in rows), encoding="utf-8")
    return len(rows)

src = Path(sys.argv[1])
out = Path(__file__).resolve().parent.parent / "Shared" / "Traditional"
out.mkdir(parents=True, exist_ok=True)
chars = load(src / "STCharacters.txt")
phrases = load(src / "STPhrases.txt")
# 词组表里简繁一样的也要留着：它们挡住更短的错配（例如「干净」整词匹配后不会把「干」单字转错）。
print("chars", write(chars, out / "s2t-chars.tsv"))
print("phrases", write(phrases, out / "s2t-phrases.tsv", drop_same=False))
