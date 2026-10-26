#!/usr/bin/env python3
"""英文单词补全和下一个词联想的数据，生成后提交在 Keyboard/English/ 里，随键盘打包。

用法：scripts/build-english.py <万象 en.dict.yaml> [<Tatoeba eng_sentences.tsv>]

- en_words.tsv：「去掉撇号的小写拼写 \\t 显示的写法 \\t 词频」，按拼写排序（同一拼写词频高的在前，
  比如 its / it's），键盘按前缀二分查找。来自万象拼音的英文词库（CC BY 4.0）；大小写几种写法合成一条，
  有全小写的留小写，没有就留词频最高的那种（专有名词、I）。缩写和「a」的词频按 Tatoeba 例句补。
- en_next.tsv：「词 \\t 后面常跟的词（空格分隔，最多 6 个）」。
  来自 Tatoeba 英文例句（CC BY 2.0 FR）里相邻两个词的统计，只留补全词表里有的词。
"""
import collections
import re
import sys
from pathlib import Path

OUT = Path(__file__).resolve().parent.parent / "Keyboard" / "English"
MIN_WEIGHT = 5
# 聊天里常用、但书面语词频偏低的词：补全时至少排到这个词频（「Hel」先出 Hello）。
CHAT_WORDS = ["hello", "hi", "hey", "thanks", "thank", "okay", "ok", "yes", "yeah", "sure", "please", "sorry",
              "bye", "lol", "btw", "omg", "awesome", "cool", "nice", "great", "tomorrow", "tonight", "today",
              "morning", "night", "love", "miss", "happy", "birthday", "congrats", "congratulations", "weekend"]
CHAT_WEIGHT = 120000
WORD = re.compile(r"^[A-Za-z][A-Za-z']*$")


def words(path):
    """小写写法 → (显示的写法, 词频)。大小写不同的几种写法合成一条。"""
    best = {}
    for line in Path(path).read_text(encoding="utf-8").splitlines():
        parts = line.split("\t")
        if len(parts) < 3 or not parts[2].isdigit() or not WORD.match(parts[0]):
            continue
        text, weight = parts[0], int(parts[2])
        lower = text.lower()
        old = best.get(lower)
        # 全小写优先；都不是小写时留词频高的；「I」和「I'm」这类永远大写。
        rank = (text.startswith("I") and lower[:1] == "i" and (len(text) == 1 or text[1] == "'"), text == lower, weight)
        if old is None or rank > old[0]:
            best[lower] = (rank, text, max(weight, old[2] if old else 0))
    return {lower: (text, weight) for lower, (_, text, weight) in best.items()}


def boost_from_sentences(table, sentences):
    """万象的英文词频来自书面语，缩写（don't、I'm）和「a」几乎是 0。用例句里的次数按「the」的比例换算补上。"""
    counts = collections.Counter()
    # 句中（不在句首）出现的次数和其中大写开头的次数：大多数时候大写的是人名地名（Tom、Mary's）。
    middle, capital = collections.Counter(), collections.Counter()
    with open(sentences, encoding="utf-8") as f:
        for line in f:
            for index, token in enumerate(TOKEN.findall(line.rstrip("\n").split("\t")[-1])):
                lower = token.lower()
                counts[lower] += 1
                if index > 0:
                    middle[lower] += 1
                    if token[0].isupper():
                        capital[lower] += 1
    names = {lower for lower, n in middle.items()
             if n >= 20 and capital[lower] > n / 2 and lower != "i" and not lower.startswith("i'")}
    scale = table["the"][1] / max(counts["the"], 1)
    for lower, count in counts.items():
        if not WORD.match(lower):
            continue
        # 普通小写词：例句里的次数比书面语高时取高的（口语词）；人名（Tom、Mary）不动。
        if lower in names:
            continue
        if "'" not in lower and lower not in ("a", "i"):
            text, old = table.get(lower, (None, 0))
            if text == lower:
                table[lower] = (text, max(old, int(count * scale * 0.5)))
            continue
        weight = int(count * scale)
        text, old = table.get(lower, (None, 0))
        if text is None:
            if count < 20:
                continue
            text = "I" + lower[1:] if lower == "i" or lower.startswith("i'") else lower
        table[lower] = (text, max(old, weight))
    return names


def write_words(table):
    rows = []
    for lower, (text, weight) in table.items():
        key = lower.replace("'", "")
        if weight < MIN_WEIGHT or (len(key) < 2 and lower not in ("a", "i")):
            continue
        rows.append((key, -weight, text))
    rows.sort()
    with open(OUT / "en_words.tsv", "w", encoding="utf-8") as f:
        for key, weight, text in rows:
            f.write(f"{key}\t{text}\t{-weight}\n")
    print(f"en_words: {len(rows)} 个词")


TOKEN = re.compile(r"[A-Za-z]+(?:'[A-Za-z]+)?|[^\sA-Za-z']")


def write_next(table, sentences, names):
    # 人名不做联想的词头，也不推荐。
    known = {lower: text for lower, (text, weight) in table.items() if weight >= MIN_WEIGHT and lower not in names}
    pairs = collections.defaultdict(collections.Counter)
    heads = collections.Counter()
    with open(sentences, encoding="utf-8") as f:
        for line in f:
            text = line.rstrip("\n").split("\t")[-1]
            tokens = TOKEN.findall(text)
            for a, b in zip(tokens, tokens[1:]):
                la, lb = a.lower(), b.lower()
                # 只算两个都是词表里的词、中间没有标点的。
                if la in known and lb in known:
                    pairs[la][lb] += 1
                    heads[la] += 1
    rows = 0
    with open(OUT / "en_next.tsv", "w", encoding="utf-8") as f:
        for head in sorted(pairs):
            if heads[head] < 20:
                continue
            # 后面跟的人名（Tom、Mary 在例句里特别多）不推荐；I、I'm 这类照留。
            top = [(w, n) for w, n in pairs[head].most_common(12)
                   if n >= 3 and (known[w] == known[w].lower() or known[w].startswith("I"))][:6]
            if not top:
                continue
            # 「I」等专有写法照词表；其余小写，键盘按句首再改大写。
            f.write(head + "\t" + " ".join(known[w] if known[w] == "I" else w for w, _ in top) + "\n")
            rows += 1
    print(f"en_next: {rows} 个词")


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    table = words(sys.argv[1])
    names = set()
    if len(sys.argv) > 2:
        names = boost_from_sentences(table, sys.argv[2])
        print(f"人名（不提权、不联想）: {len(names)} 个，比如 {', '.join(sorted(names)[:12])}")
    for word in CHAT_WORDS:
        text, old = table.get(word, (word, 0))
        table[word] = (text, max(old, CHAT_WEIGHT))
    write_words(table)
    if len(sys.argv) > 2:
        write_next(table, sys.argv[2], names)


if __name__ == "__main__":
    main()
