#!/usr/bin/env python3
"""把万象词库整理成键盘用的词库：去掉声调，按词频裁剪，只留常用汉字。

用法：python3 scripts/build-dict.py <万象仓库目录> <输出目录>
由 scripts/fetch-rime.sh 调用。
"""
import re
import sys
import unicodedata
from pathlib import Path

# 要带的中文词库，以及每个词库保留的最低词频（0 表示全留）。
# 万象基础词库有 149 万条，按词频裁到和原来雾凇差不多的规模，手机上部署更快。
CN_DICTS = {
    "zi": 0,
    "jichu": 60,
    "duoyin": 0,
    "diming": 0,
    "mingren": 0,
    "yiren": 0,
}
# 单字表里词频很低的生僻字（多是扩展区汉字，不少字体显示不出来）不要。
MIN_RARE_CHAR_WEIGHT = 10

# 万象单字表里有些同音字的词频几乎一样（「在」4510k、「再」4444k），去掉声调后谁排第一全看学到了什么：
# 选过一次「再」以后，zai 就一直先出「再」。按常见语料把明显该在前面的字拉开：
# 排错的那个字降到正确首字的六成左右，同音的其他字顺序不变。
# 口语里两个都常用的（把/吧、带/代、改/该、拉/啦、数/书、次/此、原/元）不动。
WEIGHT_OVERRIDES = {
    ("zi", "再", "zai"): 900000,
    ("zi", "载", "zai"): 500000,
    ("zi", "灾", "zai"): 300000,
    ("zi", "以", "yi"): 366000,
    ("zi", "打", "da"): 204000,
    ("zi", "搞", "gao"): 121000,
    ("zi", "加", "jia"): 62000,
    ("zi", "挺", "ting"): 75000,
    ("zi", "按", "an"): 90000,
}

TONES = str.maketrans({
    "ü": "v", "ǖ": "v", "ǘ": "v", "ǚ": "v", "ǜ": "v",
})


def strip_tones(code: str) -> str:
    code = code.translate(TONES)
    # ā → a + 组合声调符号，丢掉符号即可。
    decomposed = unicodedata.normalize("NFD", code)
    return "".join(c for c in decomposed if not unicodedata.combining(c)).lower()


def is_basic_cjk(text: str) -> bool:
    return all(0x4E00 <= ord(c) <= 0x9FFF or 0x3007 == ord(c) for c in text)


def entries(path: Path):
    body = False
    for line in path.read_text(encoding="utf-8").splitlines():
        if not body:
            body = line == "..."
            continue
        if not line or line.startswith("#"):
            continue
        fields = line.split("\t")
        if len(fields) < 2:
            continue
        # 个别词频带了多余字符（如 "45N"），只取开头的数字。
        digits = re.match(r"\d+", fields[2]) if len(fields) > 2 else None
        weight = int(digits.group()) if digits else 0
        yield fields[0], fields[1], weight


def write_dict(path: Path, name: str, rows):
    with path.open("w", encoding="utf-8") as out:
        out.write("# Rime dictionary\n# encoding: utf-8\n")
        out.write("# 数据来自万象拼音 https://github.com/amzxyz/rime_wanxiang （CC BY 4.0），已去掉声调并按词频裁剪。\n")
        out.write(f"---\nname: {name}\nversion: \"1\"\nsort: by_weight\n...\n")
        for text, code, weight in rows:
            out.write(f"{text}\t{code}\t{weight}\n")


# 联想（上屏后接着出下一个词）：从万象基础词库的长词里拆出「前一个词 → 后一个词」。
# 比如「今天早上」拆成「今天 → 早上」，长词的词频加到这一对上。每个词留最常见的几个。
PREDICT_MIN_WORD = 200
PREDICT_MIN_TOTAL = 1000
PREDICT_KEEP = 6


def write_predict(path: Path, out: Path):
    words = {}
    for text, _, weight in entries(path):
        if is_basic_cjk(text):
            words[text] = max(words.get(text, 0), weight)
    pairs = {}
    for text, weight in words.items():
        n = len(text)
        if n < 4 or n > 8:
            continue
        # 左边取最长的词（「我想起了」是「我想起|了」，不拆成「我想|起了」），右边至少两个字。
        left = next((i for i in range(n - 1, 1, -1) if words.get(text[:i], 0) >= PREDICT_MIN_WORD), None)
        if not left or n - left < 2:
            continue
        head, tail = text[:left], text[left:]
        if tail == head or words.get(tail, 0) < PREDICT_MIN_WORD:
            continue
        nexts = pairs.setdefault(head, {})
        nexts[tail] = nexts.get(tail, 0) + weight
    count = 0
    with out.open("w", encoding="utf-8") as f:
        for head in sorted(pairs):
            top = sorted(pairs[head].items(), key=lambda kv: -kv[1])[:PREDICT_KEEP]
            if sum(w for _, w in top) < PREDICT_MIN_TOTAL:
                continue
            f.write(head + "\t" + " ".join(t for t, _ in top) + "\n")
            count += 1
    print(f"  联想: {count} 个词")


def main():
    source, output = Path(sys.argv[1]), Path(sys.argv[2])
    cn = output / "cn_dicts"
    cn.mkdir(parents=True, exist_ok=True)
    total = 0
    for name, min_weight in CN_DICTS.items():
        rows, seen = [], set()
        found = sorted(entries(source / "dicts" / f"{name}.dict.yaml"), key=lambda row: -row[2])
        for text, code, weight in found:
            if weight < min_weight:
                continue
            if name == "zi" and weight <= MIN_RARE_CHAR_WEIGHT and not is_basic_cjk(text):
                continue
            code = strip_tones(code)
            if not all("a" <= c <= "z" or c == " " for c in code):
                continue
            # 声调不同的读音去掉声调后会重复，留词频高的那条。
            if (text, code) in seen:
                continue
            seen.add((text, code))
            rows.append((text, code, WEIGHT_OVERRIDES.get((name, text, code), weight)))
        write_dict(cn / f"{name}.dict.yaml", name, rows)
        print(f"  {name}: {len(rows)} 条")
        total += len(rows)

    write_predict(source / "dicts" / "jichu.dict.yaml", output / "predict.tsv")

    # 英文单词：编码统一成小写字母，打 hello 能出 Hello。
    rows, seen = [], set()
    for text, _, weight in entries(source / "dicts" / "en.dict.yaml"):
        code = "".join(c for c in text.lower() if "a" <= c <= "z")
        if len(code) < 2 or (text, code) in seen:
            continue
        seen.add((text, code))
        rows.append((text, code, weight))
    write_dict(output / "enclave_en.dict.yaml", "enclave_en", rows)
    print(f"  en: {len(rows)} 条")
    print(f"中文共 {total} 条")


if __name__ == "__main__":
    main()
