#!/usr/bin/env python3
"""把扩展词包整理成 Rime 词库（带拼音）：内置的放 Configs/ExtDicts/，在线的放服务器目录。

用法：
  python3 scripts/build-ext-dicts.py <万象 dicts 目录> <THUOCL data 目录> [--online server/dicts] [--blocklist <敏感词表>]
                                    [--baike <zhwiki-*.dict.yaml> [--baike-blocklist <百科补充屏蔽表>]]
                                    [--grammar <wanxiang-lts-zh-hans.gram>]
  python3 scripts/build-ext-dicts.py --catalog-only --online server/dicts [--grammar <…gram>]
      只按目录里现有的词库文件重写 catalog.json（不重新生成词库）。
  python3 scripts/build-ext-dicts.py --only lvyou,renwu --wikidata <目录> --online server/dicts --blocklist <敏感词表>
      只重新生成列出的词库，别的词库文件不动（builtin.json、catalog.json 里它们的条目按现有文件重算）。
      只有 Wikidata 词库时不用给万象、THUOCL 目录（拼音已经在 tsv 里）。

景点机场地标（lvyou，内置）、人物（renwu，在线）来自 Wikidata（CC0，T106）：scripts/fetch-wikidata-names.py
在 Mac 上拉数据、标好拼音，写出 lvyou.tsv、renwu.tsv（词、拼音、热度），--wikidata 指到那个目录。
这两份 tsv 不进仓库（同目录还有交 05 的人名待审文件）；没给 --wikidata 就沿用现有的词库文件。

在线词库和清单 catalog.json 写到 --online 目录，用 server/publish-dicts.sh 发到 enclavekb.cn/dicts/（见 server/README.md）。

版本号（第 99 条）：词库内容没变就沿用文件里原来的 version，文件一字不改（sha256 不变，App 不会误报「有更新」）；
变了才写当天日期，同一天第二次改写成「2026-11-26.2」。App 按 sha256 判断有没有更新，version 只用来显示「X 月 X 日版」。
清单 schema 2：url 带「?v=sha256 前 8 位」（缓存不会拿旧文件配新清单）；加 updated、grammar（整句模型）、
builtinUpdates（内置词库的服务器版，放在 builtin/ 下；不能放进 dicts，老版本 App 会把它当成可以下载的词库）。

拼音：整词在万象词库里有就用万象的读音（多音字词读得对），没有就逐字取单字表里最常用的读音。
有字查不到读音（英文、数字、生僻字）的词跳过。
词频压得很低（1–9），排在基础词库后面，不抢常用词的首选。
"""
import bisect
import hashlib
import json
import math
import re
import shutil
import sys
import unicodedata
from datetime import date, datetime, timedelta, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "scripts" / "ext-dicts"
OUT = ROOT / "Configs" / "ExtDicts"

# 内置：随 App 带。顺序就是 App 里「我的词库」的顺序。
BUILTIN = [
    ("lol", "self", "lol.txt"),
    ("wzry", "self", "wzry.txt"),
    ("genshin", "self", "genshin.txt"),
    ("dota2", "self", "dota2.txt"),
    ("hpjy", "self", "hpjy.txt"),
    ("meme", "self", "meme.txt"),
    ("chengyu", "thuocl", "THUOCL_chengyu.txt"),
    ("diming", "thuocl", "THUOCL_diming.txt"),
    ("it", "thuocl", "THUOCL_IT.txt"),
    ("caijing", "thuocl", "THUOCL_caijing.txt"),
    ("lvyou", "wikidata", "lvyou.tsv"),
]
# 在线：放 enclavekb.cn/dicts/，在 App 里点「下载」才下。
ONLINE = [
    ("medical", "thuocl", "THUOCL_medical.txt"),
    ("law", "thuocl", "THUOCL_law.txt"),
    ("poem", "thuocl", "THUOCL_poem.txt"),
    ("lishimingren", "thuocl", "THUOCL_lishimingren.txt"),
    ("renwu", "wikidata", "renwu.tsv"),
]
ONLINE_NAMES = {
    "medical": {"zh": "医学", "en": "Medicine", "ja": "医学"},
    "law": {"zh": "法律", "en": "Law", "ja": "法律"},
    "poem": {"zh": "诗词", "en": "Poetry", "ja": "詩詞"},
    "lishimingren": {"zh": "历史名人", "en": "Historical figures", "ja": "歴史上の人物"},
    "renwu": {"zh": "名人", "en": "Famous people", "ja": "著名人"},
}
# 05（compliance/词库-Wikidata/许可和审核要求.md）定的来源写法：词库文件头、许可页、服务器 README 一致。
WIKIDATA_SOURCE = "Wikidata（wikidata.org），词条名称按 CC0 1.0 公有领域贡献使用；拼音标注、筛选和整理由飞地输入法完成"
# 百科词库：中文维基百科条目标题（fcitx5-pinyin-zhwiki 的 release，已转成简体），过敏感词表、精简到 20 万条。
# 没给 --baike 时沿用 --online 目录里上次生成的；一次都没生成过，清单里 url 写 null，App 显示「准备中」。
BAIKE_LIMIT = 200_000
BAIKE = {
    "id": "baike", "name": {"zh": "百科词库", "en": "Wikipedia", "ja": "ウィキペディア辞書"},
    "summary": {"zh": "人名、地名、作品、游戏角色", "en": "People, places, works and game characters", "ja": "人名、地名、作品、ゲームキャラクター"},
    "license": "wiki", "entries": 200000, "size": 5470000, "version": "", "sha256": None, "url": None,
}

# 整句模型（万象 LTS 11-18 版）：两条线路的地址、大小、sha256。给 --grammar 时按那个文件重算大小和 sha256。
GRAMMAR = {
    "version": "2026-11-18",
    "size": 390786092,
    "sha256": "e9ddd501b7d536bc5ea1346f8f900ae49a719a05be349e0a17cb27e717143ca5",
    "urls": {
        "cn": "https://enclavekb.cn/grammar/wanxiang-lts-zh-hans.gram",
        "global": "https://github.com/amzxyz/rime-wanxiang-data/releases/download/LTS/wanxiang-lts-zh-hans.gram",
    },
}

TONES = str.maketrans({"ü": "v", "ǖ": "v", "ǘ": "v", "ǚ": "v", "ǜ": "v"})


def strip_tones(code):
    decomposed = unicodedata.normalize("NFD", code.translate(TONES))
    return "".join(c for c in decomposed if not unicodedata.combining(c)).lower()


def rime_entries(path):
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
        digits = re.match(r"\d+", fields[2]) if len(fields) > 2 else None
        yield fields[0], strip_tones(fields[1]), int(digits.group()) if digits else 0


def load_readings(wanxiang):
    """整词读音（取词频最高的）、单字最常用读音和单字词频。"""
    words, chars = {}, {}
    for name in ["jichu", "duoyin", "diming", "mingren", "yiren"]:
        path = wanxiang / f"{name}.dict.yaml"
        if not path.exists():
            continue
        for text, code, weight in rime_entries(path):
            if len(text) > 1 and (text not in words or weight > words[text][1]):
                words[text] = (code, weight)
    for text, code, weight in rime_entries(wanxiang / "zi.dict.yaml"):
        if len(text) == 1 and (text not in chars or weight > chars[text][1]):
            chars[text] = (code, weight)
    return {k: v[0] for k, v in words.items()}, {k: v[0] for k, v in chars.items()}, {k: v[1] for k, v in chars.items()}


def pinyin(word, words, chars):
    """整词有就用整词的；没有就切成万象里有的词，切的段数最少、单字最少（「长沙火车站」= 长沙 + 火车站，长读 chang），
    切不出的字用单字最常用的读音。"""
    if word in words:
        return words[word]
    n = len(word)
    best = [None] * (n + 1)  # best[i]：前 i 个字的 (段数, 单字数, 拼音列表)
    best[0] = (0, 0, [])
    for i in range(n):
        if best[i] is None:
            continue
        for j in range(i + 1, min(n, i + 8) + 1):
            piece = word[i:j]
            code = words.get(piece) if j - i > 1 else chars.get(piece)
            if not code:
                continue
            candidate = (best[i][0] + 1, best[i][1] + (j - i == 1), best[i][2] + [code])
            if best[j] is None or candidate[:2] < best[j][:2]:
                best[j] = candidate
    return " ".join(best[n][2]) if best[n] else None


def read_words(kind, path):
    """(词, 词频)。自整理的没有词频，按在表里的先后给。Wikidata 的 tsv 是（词, 热度），拼音另外读（read_readings）。"""
    text = path.read_text(encoding="utf-8")
    if kind == "wikidata":
        return [(fields[0], int(fields[2])) for fields in (line.split("\t") for line in text.splitlines())
                if len(fields) >= 3 and not fields[0].startswith("#")]
    rows = []
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split()
        freq = int(parts[1]) if len(parts) > 1 and parts[1].isdigit() else 0
        rows.append((parts[0], freq))
    if kind == "self":
        rows = [(w, len(rows) - i) for i, (w, _) in enumerate(rows)]
    return rows


def read_readings(path):
    """Wikidata 的 tsv 里 fetch-wikidata-names.py 按万象标好的拼音。"""
    return {fields[0]: fields[1] for fields in (line.split("\t") for line in path.read_text(encoding="utf-8").splitlines())
            if len(fields) >= 3 and not fields[0].startswith("#")}


def weight(freq, top):
    """压到 1–9：按对数词频，最高的 9。"""
    if top <= 1:
        return 5
    return max(1, min(9, round(1 + 8 * math.log(freq + 1) / math.log(top + 1))))


def build(pack, kind, path, words, chars, blocklist, out):
    rows = read_words(kind, path)
    given = read_readings(path) if kind == "wikidata" else {}
    top = max((f for _, f in rows), default=1)
    seen, kept, skipped, blocked = set(), [], 0, []
    for word, freq in rows:
        if word in seen:
            continue
        seen.add(word)
        if word in blocklist:
            blocked.append(word)
            continue
        code = given.get(word) or (pinyin(word, words, chars) if words else None)
        if not code or not re.fullmatch(r"[a-z]+( [a-z]+)*", code):
            skipped += 1
            continue
        kept.append((word, code, weight(freq, top)))
    source = {"thuocl": "THUOCL 清华大学开放中文词库（github.com/thunlp/THUOCL），MIT 许可，Copyright (c) 2018 THUNLP",
              "wikidata": WIKIDATA_SOURCE}.get(kind, "飞地输入法整理")
    target = out / f"ext_{pack}.dict.yaml"
    header = f"# 飞地输入法扩展词库 · 来源：{source}\n# 由 scripts/build-ext-dicts.py 生成，拼音按万象拼音词库标注。\n"
    version = write_dict(target, header, f"ext_{pack}", "".join(f"{word}\t{code}\t{w}\n" for word, code, w in kept))
    # Wikidata 的过滤结果可能很长、有敏感人名，只写文件不打印。
    shown = '：' + '、'.join(blocked) if blocked and kind != "wikidata" else ''
    print(f"  {pack}: {len(kept)} 条，版本 {version}（查不到读音 {skipped}，过滤 {len(blocked)}{shown}）")
    if kind == "wikidata":
        # 过表删掉的词交 05 看（05 第三节），和待审文件放一起，不进仓库。
        (path.parent / f"{pack}-blocked.txt").write_text("".join(w + "\n" for w in blocked), encoding="utf-8")
    return manifest_entry(pack, target)


def manifest_entry(pack, target):
    """builtin.json 里的一条：按词库文件算。"""
    return {"id": pack, "entries": count_entries(target), "version": dict_version(target), "size": target.stat().st_size,
            "sha256": sha256_file(target)}


# 标题里有这些字（代词、语气词），多半是歌名、书名一类的短句，不收。
PRONOUNS = set("的了吗呢吧啊呀哦嘛我你他她它们谁咱俺")
# 切词后有一段全是虚词（「和」「就是」「在这」），也按短句算，不收。
FUNCTION_CHARS = PRONOUNS | set("着过么这那和与及或在是就都也还又再很太最被把让给对从向得地其说要会有没不个")


def segment(word, words):
    """切成万象里有的词，段数最少；切不出的字单独一段。"""
    n = len(word)
    best = [None] * (n + 1)
    best[0] = []
    for i in range(n):
        if best[i] is None:
            continue
        for j in range(i + 1, min(n, i + 8) + 1):
            piece = word[i:j]
            if j - i > 1 and piece not in words:
                continue
            if best[j] is None or len(best[i]) + 1 < len(best[j]):
                best[j] = best[i] + [piece]
    return best[n]


# 音译常用字。两个字都是这些字的标题多半是音译词的半截。
TRANSLIT = set("阿埃艾安奥巴拜班邦贝本比彼波伯博布查达丹德迪蒂丁杜多厄恩法菲费芬丰弗福伏盖冈戈格贡古圭哈海汉豪赫亨胡华霍基吉加贾杰金卡凯坎康柯科克库夸奎昆拉莱兰朗劳勒雷里利莉列林琳卢鲁伦罗洛马玛迈曼梅门蒙米敏莫默穆纳娜奈南内尼涅宁纽努诺欧帕潘佩彭皮珀普奇乔切琼萨塞桑瑟森沙尚舍施什史斯松苏索塔泰坦汤唐特滕提托瓦旺威韦维温沃乌伍西希锡谢辛休雅亚扬耶伊因英尤约泽扎詹兹")


def starts_with_word(rest, words):
    """rest 开头两到四个字是万象里的词。"""
    return any(rest[:k] in words for k in (2, 3, 4) if len(rest) >= k)


WIKIDATA_LICENSE = """景点、机场、地标和名人词库（ext_lvyou.dict.yaml、ext_renwu.dict.yaml）来源说明

景点、机场、地标和名人词库：词条名称来自 Wikidata（wikidata.org），按 CC0 1.0 公有领域贡献使用。拼音标注、筛选和整理由飞地输入法完成。
Places, airports, landmarks and people dictionaries: entry names from Wikidata (wikidata.org), used under CC0 1.0. Pinyin, filtering and curation by Enclave.
観光地・空港・ランドマーク・人名辞書：項目名は Wikidata（wikidata.org）から CC0 1.0 のもとで使用しています。ピンインの付与、選別、整理は Enclave が行っています。

CC0 1.0：https://creativecommons.org/publicdomain/zero/1.0/
只用了 Wikidata 的中文标签和别名，没有用维基百科的条目正文、摘要或描述。
"""


BAIKE_LICENSE = """百科词库（ext_baike.dict.yaml）许可说明

来源：中文维基百科条目标题（zh.wikipedia.org），词条由维基百科各位贡献者（Wikipedia contributors）撰写。
标题表取自 fcitx5-pinyin-zhwiki 项目（https://github.com/felixonmars/fcitx5-pinyin-zhwiki，{source}）。
飞地输入法转换为 Rime 格式：重新标注拼音，并按敏感词表过滤、精简到 20 万条。

许可：CC BY-SA 4.0（知识共享 署名-相同方式共享 4.0 国际）
https://creativecommons.org/licenses/by-sa/4.0/
维基媒体的许可说明：https://dumps.wikimedia.org/legal.html

本词库按同一许可分发：可以自由使用、修改和再分发，但需要署名，修改后的版本也要用 CC BY-SA 4.0 发布。
"""


def next_version(old, today):
    """同一天第二次改：2026-11-26 → 2026-11-26.2 → 2026-11-26.3；别的日子写当天。"""
    if old and old.split(".")[0] == today:
        parts = old.split(".", 1)
        n = int(parts[1]) if len(parts) > 1 and parts[1].isdigit() else 1
        return f"{today}.{n + 1}"
    return today


def render_dict(header, name, version, body):
    return f"{header}---\nname: {name}\nversion: \"{version}\"\nsort: by_weight\n...\n{body}"


def write_dict(target, header, name, body):
    """写词库文件，返回版本号。内容（版本号以外）和原来的一样就沿用原版本号，不改文件。"""
    today = date.today().isoformat()
    old_version = None
    if target.exists():
        old = target.read_text(encoding="utf-8")
        m = re.search(r'^version: "([^"]*)"$', old, re.M)
        if m:
            old_version = m.group(1)
            if old == render_dict(header, name, old_version, body):
                return old_version
    version = next_version(old_version, today)
    target.write_text(render_dict(header, name, version, body), encoding="utf-8")
    return version


def sha256_file(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def versioned_url(name, sha):
    """「ext_medical.dict.yaml?v=153c8ba4」：nginx 忽略问号后面，缓存把它当新地址。"""
    return f"{name}?v={sha[:8]}"


def dict_version(path):
    m = re.search(r'^version: "([^"]*)"$', path.read_text(encoding="utf-8"), re.M)
    return m.group(1) if m else ""


def count_entries(path):
    return sum(1 for _ in rime_entries(path))


def read_blocklist(path):
    """一行一个词，# 开头是注释，空行跳过。"""
    return {l.strip() for l in Path(path).read_text(encoding="utf-8").splitlines()
            if l.strip() and not l.strip().startswith("#")}


def build_baike(path, words, chars, char_freq, blocklist, extra_block, out):
    """维基标题没有词频，按「被别的条目引用得多不多、字常不常用、长度合不合适」打分，取前 20 万条。

    敏感词表按包含匹配（标题里有表里的词就删），其他词包是整词匹配；百科补充屏蔽表（05 审核加的）整词匹配。
    跳过：万象里已经有的词（基础词库能打出来）、不是 2–8 个汉字的、有生僻字（万象单字表里没有）的、
    像歌名或短句的（有代词、语气词，或者切出来有一段全是虚词；派生条目多的照收）。
    分数主要看有多少条别的标题是「它 + 一个词」（「周杰伦」有「周杰伦音乐作品列表」……），这比字频更能分出常被提到的东西；
    再加一点字频（常用字多的排前），4 字以上每多一个字扣一点。"""
    rows, blocked, skipped = [], [], 0
    # 百科标题是整句名字（「六四学潮」「西藏独立」），整词匹配漏得多，这里按包含匹配：误删几个也不缺，词多的是。
    contains = re.compile("|".join(sorted(map(re.escape, (b for b in blocklist if len(b) >= 2)), key=len, reverse=True))) \
        if blocklist else None
    entries = list(rime_entries(path))
    title_set = {text for text, _, _ in entries}
    titles = sorted(title_set)
    seen = set()
    for text, code, _ in entries:
        if text in words or text in seen or not re.fullmatch(r"[\u4e00-\u9fff]{2,8}", text):
            continue
        if text in blocklist or text in extra_block or (contains and contains.search(text)):
            blocked.append(text)
            continue
        if any(c not in char_freq for c in text):
            skipped += 1
            continue
        if len(text) == 2 and all(c in TRANSLIT for c in text):
            continue  # 「斯坦」「阿斯」「卡斯」：音译词的半截，单独打出来没用
        reading = pinyin(text, words, chars)
        if not reading or not re.fullmatch(r"[a-z]+( [a-z]+)*", reading) or len(reading.split()) != len(text):
            reading = code if re.fullmatch(r"[a-z]+( [a-z]+)*", code or "") and len(code.split()) == len(text) else None
        if not reading:
            skipped += 1
            continue
        # 有多少条别的标题是「它 + 一个词」（「延安」→「延安大学」「延安战役」……）：越多越像常被提到的东西。
        # 后面接的必须是万象里的词，「罗伯」→「罗伯特」这种音译词的半截不算。最多数 300 条。
        start = bisect.bisect_right(titles, text)
        end = min(bisect.bisect_left(titles, text + "\U0010ffff", lo=start), start + 300)
        # 「加拿」→「加拿大航空」也不算：「加拿大」本身是标题，这条归它。
        n = len(text)
        derived = sum(1 for t in titles[start:end]
                      if starts_with_word(t[n:], words)
                      and not any(len(t) > n + k and t[:n + k] in title_set for k in (1, 2)))
        # 「我的少年」「和那谁的」这类歌名、句子式标题：常用字多，按字频会排到最前面，又不是词。
        # 有两条以上派生条目的（「进击的巨人」有角色列表、集数列表）照收。
        if derived < 2 and (any(c in PRONOUNS for c in text)
                            or any(all(c in FUNCTION_CHARS for c in p) for p in segment(text, words))):
            continue
        common = sum(min(math.log(char_freq[c] + 1), 12) for c in text) / len(text) / 12
        score = 3 * math.log(1 + derived) + common - 0.4 * max(0, len(text) - 4)
        seen.add(text)
        rows.append((score, text, reading))
    rows.sort(key=lambda r: -r[0])
    kept = rows[:BAIKE_LIMIT]
    target = out / "ext_baike.dict.yaml"
    header = ("# 飞地输入法扩展词库 · 来源：中文维基百科条目标题（zh.wikipedia.org），CC BY-SA 4.0；"
              f"标题表取自 fcitx5-pinyin-zhwiki（github.com/felixonmars/fcitx5-pinyin-zhwiki，{path.name}）\n"
              "# 由 scripts/build-ext-dicts.py 生成，拼音按万象拼音词库标注，按 CC BY-SA 4.0 分发。\n")
    n = len(kept)
    body = "".join(f"{text}\t{reading}\t{max(1, 5 - (5 * i) // max(n, 1))}\n" for i, (_, text, reading) in enumerate(kept))
    version = write_dict(target, header, "ext_baike", body)
    (out / "LICENSE-baike.txt").write_text(BAIKE_LICENSE.format(source=path.name), encoding="utf-8")
    print(f"  baike: {len(kept)} 条，版本 {version}（候选 {len(rows)}，生僻字或查不到读音 {skipped}，"
          f"过滤 {len(blocked)}{'：' + '、'.join(blocked[:30]) + ('…' if len(blocked) > 30 else '') if blocked else ''}）")
    sha = sha256_file(target)
    return {**BAIKE, "entries": len(kept), "size": target.stat().st_size, "version": version,
            "sha256": sha, "url": versioned_url(target.name, sha)}


def previous_baike(out):
    """没给 --baike：目录里上次生成的百科词库还在就沿用（大小、sha256 按文件重算）。"""
    target = out / "ext_baike.dict.yaml"
    if not target.exists():
        return BAIKE
    sha = sha256_file(target)
    return {**BAIKE, "entries": count_entries(target), "size": target.stat().st_size, "version": dict_version(target),
            "sha256": sha, "url": versioned_url(target.name, sha)}


def online_entry(out, pack, kind):
    path = out / f"ext_{pack}.dict.yaml"
    sha = sha256_file(path)
    return {"id": pack, "name": ONLINE_NAMES[pack], "license": kind, "entries": count_entries(path),
            "size": path.stat().st_size, "version": dict_version(path), "sha256": sha, "url": versioned_url(path.name, sha)}


def grammar_entry(out, gram_path):
    """整句模型：给了 --grammar 就按文件重算大小和 sha256（内容变了版本写当天）；没给沿用上次清单里的，再没有用 GRAMMAR。"""
    previous = GRAMMAR
    try:
        previous = json.loads((out / "catalog.json").read_text(encoding="utf-8")).get("grammar") or GRAMMAR
    except (OSError, ValueError):
        pass
    if not gram_path:
        return previous
    path = Path(gram_path)
    sha = sha256_file(path)
    version = previous["version"] if sha == previous.get("sha256") else date.today().isoformat()
    return {**previous, "version": version, "size": path.stat().st_size, "sha256": sha}


def builtin_updates(out):
    """内置词库的服务器版：把 Configs/ExtDicts 里的拷到 builtin/，App 里自带的比它旧时下载这份。"""
    folder = out / "builtin"
    folder.mkdir(parents=True, exist_ok=True)
    updates = []
    for pack, _, _ in BUILTIN:
        src = OUT / f"ext_{pack}.dict.yaml"
        if not src.exists():
            continue
        dst = folder / src.name
        if not dst.exists() or dst.read_bytes() != src.read_bytes():
            shutil.copyfile(src, dst)
        sha = sha256_file(dst)
        updates.append({"id": pack, "entries": count_entries(dst), "size": dst.stat().st_size, "version": dict_version(dst),
                        "sha256": sha, "url": versioned_url(f"builtin/{dst.name}", sha)})
    return updates


def write_catalog(out, dicts, gram_path):
    catalog = {
        "schema": 2,
        "updated": datetime.now(timezone(timedelta(hours=8))).isoformat(timespec="seconds"),
        "grammar": grammar_entry(out, gram_path),
        "dicts": dicts,
        "builtinUpdates": builtin_updates(out),
    }
    (out / "catalog.json").write_text(json.dumps(catalog, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    print(f"清单：{out / 'catalog.json'}（{catalog['updated']}）")


def main():
    args = sys.argv[1:]
    def option(name):
        if name in args:
            i = args.index(name)
            value = args[i + 1]
            del args[i:i + 2]
            return value
        return None
    online_dir = option("--online")
    block_path = option("--blocklist")
    baike_path = option("--baike")
    gram_path = option("--grammar")
    if "--catalog-only" in args:
        if not online_dir:
            sys.exit("--catalog-only 要和 --online 一起用")
        out = Path(online_dir)
        dicts = [previous_baike(out)] + [online_entry(out, pack, kind) for pack, kind, _ in ONLINE
                                         if (out / f"ext_{pack}.dict.yaml").exists()]
        write_catalog(out, dicts, gram_path)
        return
    only = set(filter(None, (option("--only") or "").split(",")))
    wikidata_dir = option("--wikidata")
    wikidata = Path(wikidata_dir) if wikidata_dir else None
    known = {pack for pack, _, _ in BUILTIN + ONLINE}
    if only - known:
        sys.exit(f"--only 里有不认识的词库：{', '.join(sorted(only - known))}")
    # 只重新生成 Wikidata 词库时拼音已经在 tsv 里，不用万象、THUOCL。
    needs_sources = not only or any(kind != "wikidata" for pack, kind, _ in BUILTIN + ONLINE if pack in only)
    if needs_sources and len(args) < 2:
        sys.exit(__doc__)
    wanxiang, thuocl = (Path(args[0]), Path(args[1])) if len(args) >= 2 else (None, None)
    baike_block_path = option("--baike-blocklist")
    # 整词精确匹配：词和表里一模一样才删，不做包含匹配（见 05 的敏感词表说明）。
    blocklist = read_blocklist(block_path) if block_path else set()
    baike_block = read_blocklist(baike_block_path) if baike_block_path else set()
    if not block_path:
        print("提醒：没给 --blocklist，没过敏感词过滤，只能用于开发测试。")
    words, chars, char_freq = load_readings(wanxiang) if wanxiang else ({}, {}, {})

    def source(kind, name):
        """这个词库的源文件；None = 这次不重新生成（沿用现有文件）。"""
        if kind == "wikidata":
            path = wikidata / name if wikidata else None
            return path if path and path.exists() else None
        return (SRC if kind == "self" else thuocl) / name

    def rebuild(pack, kind, name):
        return (not only or pack in only) and source(kind, name) is not None

    OUT.mkdir(parents=True, exist_ok=True)
    print("内置词库：")
    manifest = []
    for pack, kind, name in BUILTIN:
        if rebuild(pack, kind, name):
            manifest.append(build(pack, kind, source(kind, name), words, chars, blocklist, OUT))
        elif (OUT / f"ext_{pack}.dict.yaml").exists():
            manifest.append(manifest_entry(pack, OUT / f"ext_{pack}.dict.yaml"))
            print(f"  {pack}: 沿用现有文件")
    previous_filtered = True
    try:
        previous_filtered = json.loads((OUT / "builtin.json").read_text(encoding="utf-8")).get("filtered", True)
    except (OSError, ValueError):
        pass
    filtered = bool(block_path) and (not only or previous_filtered)
    (OUT / "builtin.json").write_text(json.dumps({"filtered": filtered, "dicts": manifest}, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    if online_dir:
        out = Path(online_dir)
        out.mkdir(parents=True, exist_ok=True)
        print("在线词库：")
        rebuild_baike = baike_path and (not only or "baike" in only)
        catalog = [build_baike(Path(baike_path), words, chars, char_freq, blocklist, baike_block, out) if rebuild_baike else previous_baike(out)]
        for pack, kind, name in ONLINE:
            if rebuild(pack, kind, name):
                build(pack, kind, source(kind, name), words, chars, blocklist, out)
            elif (out / f"ext_{pack}.dict.yaml").exists():
                print(f"  {pack}: 沿用现有文件")
            else:
                continue
            catalog.append(online_entry(out, pack, kind))
        # THUOCL 的 MIT 许可原文跟在线词包放在一起分发；Wikidata 词库的来源说明也放一份。
        shutil.copyfile(OUT / "LICENSE-THUOCL.txt", out / "LICENSE-THUOCL.txt")
        (out / "LICENSE-wikidata.txt").write_text(WIKIDATA_LICENSE, encoding="utf-8")
        write_catalog(out, catalog, gram_path)


if __name__ == "__main__":
    main()
