#!/usr/bin/env python3
"""英文补全里的专有名词：景点、机场、地标、餐厅的英文名（T106，用户 11-27：「这些都需要中英文的」）。

用法：python3 scripts/build-english-names.py <Wikidata 输出目录> --blocklist-en <英文屏蔽词表> [--people]
  只更新网红打卡的英文名时，目录给一个空目录就行。
  英文屏蔽词表在项目文件 compliance/blocklist/英文屏蔽词表.txt（不进仓库），整词匹配，命中的整条名字不收，
  删掉的写进输出目录的 en-names-blocked.txt、en-osm-blocked.txt 交 05。
  <Wikidata 输出目录> 是 scripts/update-wikidata-dicts.sh 写出的目录，读里面的 en-lvyou.tsv（和 --people 时的 en-renwu.tsv）。
  人名（--people）等 05 看完人物待审文件再加。

写出 Keyboard/English/ 里的两个文件，随键盘打包，EnglishPredictor 和 en_words.tsv、en_next.tsv 合在一起用：
- en_names.tsv：「去掉撇号的小写拼写 \\t 写法 \\t 词频」，和 en_words.tsv 一样的格式。只收 en_words.tsv 里没有的词
  （Changi、Sagrada），写法照名字里的大小写，词频按热度（sitelinks）折算，排在常用词后面。
- en_names_next.tsv：「词 \\t 后面跟的词」：名字里前一个词是上面新收的词时，记下后一个词（Changi → Airport）。
来源：Wikidata 的英文标签和别名，CC0 1.0；许可页「扩展词库」里 Wikidata 那一条已经写了。
同一目录里有 en-osm.tsv（scripts/fetch-osm-names.py）时，另写 en_osm.tsv、en_osm_next.tsv：海外餐厅的英文名，
来自 OpenStreetMap，按 ODbL 1.0 单独发布（05 第四节），许可页单列一条。
"""
import collections
import re
import sys
from pathlib import Path

OUT = Path(__file__).resolve().parent.parent / "Keyboard" / "English"
TOKEN = re.compile(r"[A-Za-z][A-Za-z']*")
# 热度 → 词频：en_words.tsv 的中位数是 59，Singapore 725、Tokyo 831。热度 90 的樟宜机场折成 720。
PER_SITELINK = 8
MAX_WEIGHT = 3000
LIMIT = 40_000
DAKA = Path(__file__).resolve().parent / "ext-dicts" / "daka-en.txt"
DAKA_POPULARITY = 100
OSM_HEADER = "# 来源：OpenStreetMap，© OpenStreetMap contributors，ODbL 1.0（本文件也按 ODbL 1.0 发布）；由 scripts/build-english-names.py 生成，不要手改。\n"
HEADER = "# 来源：Wikidata（wikidata.org）英文标签和别名，CC0 1.0；网红打卡的英文名由飞地输入法整理（scripts/ext-dicts/daka-en.txt）；由 scripts/build-english-names.py 生成，不要手改。\n"


def read(path):
    rows = []
    for line in path.read_text(encoding="utf-8").splitlines():
        parts = line.split("\t")
        if len(parts) == 2 and parts[1].isdigit() and not line.startswith("#"):
            rows.append((parts[0], int(parts[1])))
    return rows


def write(names, known, stem, header, blocklist, blocked_path):
    """names：[(英文名, 热度)] → Keyboard/English/<stem>.tsv 和 <stem>_next.tsv。
    名字里有一个词在英文屏蔽词表里（整词，不分大小写），整条不收，写进 blocked_path 交 05。"""
    weights, spellings = {}, {}
    pairs = collections.defaultdict(collections.Counter)
    blocked = []
    for name, popularity in names:
        tokens = TOKEN.findall(name)
        if any(token.lower() in blocklist or token.lower().replace("'", "") in blocklist for token in tokens):
            blocked.append(name)
            continue
        for index, token in enumerate(tokens):
            key = token.lower().replace("'", "")
            if len(key) < 3 or key in known:
                continue
            weight = min(popularity * PER_SITELINK, MAX_WEIGHT)
            if weight > weights.get(key, 0):
                weights[key] = weight
                spellings[key] = token
            if index + 1 < len(tokens):
                pairs[key][tokens[index + 1]] += popularity
    keep = sorted(weights, key=lambda k: (-weights[k], k))[:LIMIT]
    kept = set(keep)
    with open(OUT / f"{stem}.tsv", "w", encoding="utf-8") as f:
        f.write(header)
        for key in sorted(keep):
            f.write(f"{key}\t{spellings[key]}\t{weights[key]}\n")
    with open(OUT / f"{stem}_next.tsv", "w", encoding="utf-8") as f:
        f.write(header)
        for key in sorted(k for k in pairs if k in kept):
            f.write(f"{key}\t{' '.join(word for word, _ in pairs[key].most_common(6))}\n")
    blocked_path.write_text("".join(name + "\n" for name in sorted(set(blocked))), encoding="utf-8")
    print(f"{stem}.tsv：{len(keep)} 个词；{stem}_next.tsv：{sum(1 for k in pairs if k in kept)} 条；屏蔽 {len(set(blocked))} 个名字（{blocked_path.name}）")
    return kept


def main():
    args = sys.argv[1:]
    people = "--people" in args
    args = [a for a in args if a != "--people"]
    blocklist = set()
    if "--blocklist-en" in args:
        i = args.index("--blocklist-en")
        blocklist = {line.strip().lower() for line in Path(args[i + 1]).read_text(encoding="utf-8").splitlines()
                     if line.strip() and not line.startswith("#")}
        del args[i:i + 2]
    else:
        print("提醒：没给 --blocklist-en，英文名没过屏蔽词表，只能用于开发测试。")
    if len(args) != 1:
        sys.exit(__doc__)
    source = Path(args[0])
    known = {line.split("\t", 1)[0] for line in (OUT / "en_words.tsv").read_text(encoding="utf-8").splitlines()}
    # 网红打卡短表的英文名（自己整理、05 审过）也放进 en_names，热度按 DAKA_POPULARITY 算。
    daka = [(line, DAKA_POPULARITY) for line in DAKA.read_text(encoding="utf-8").splitlines() if line and not line.startswith("#")]
    names = daka
    if (source / "en-lvyou.tsv").exists():
        names += read(source / "en-lvyou.tsv") + (read(source / "en-renwu.tsv") if people else [])
    known |= write(names, known, "en_names", HEADER, blocklist, source / "en-names-blocked.txt")
    if (source / "en-osm.tsv").exists():
        # OSM 来的单独一个文件，按 ODbL 发布（05 第四节）；热度是同名店的家数，折算方式一样。
        write(read(source / "en-osm.tsv"), known, "en_osm", OSM_HEADER, blocklist, source / "en-osm-blocked.txt")


if __name__ == "__main__":
    main()
