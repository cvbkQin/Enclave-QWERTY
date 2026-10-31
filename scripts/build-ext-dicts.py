#!/usr/bin/env python3
"""把扩展词包整理成 Rime 词库（带拼音）：内置的放 Configs/ExtDicts/，在线的放服务器目录。

用法：
  python3 scripts/build-ext-dicts.py <万象 dicts 目录> <THUOCL data 目录> [--online server/dicts] [--blocklist <敏感词表>]
                                    [--baike <zhwiki-*.dict.yaml>]

在线词库和清单 catalog.json 写到 --online 目录，原样放到 enclavekb.cn/dicts/（见 server/README.md）。

拼音：整词在万象词库里有就用万象的读音（多音字词读得对），没有就逐字取单字表里最常用的读音。
有字查不到读音（英文、数字、生僻字）的词跳过。
词频压得很低（1–9），排在基础词库后面，不抢常用词的首选。
"""
import hashlib
import json
import math
import re
import shutil
import sys
import unicodedata
from datetime import date
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
]
# 在线：放 enclavekb.cn/dicts/，在 App 里点「下载」才下。
ONLINE = [
    ("medical", "thuocl", "THUOCL_medical.txt"),
    ("law", "thuocl", "THUOCL_law.txt"),
    ("poem", "thuocl", "THUOCL_poem.txt"),
    ("lishimingren", "thuocl", "THUOCL_lishimingren.txt"),
]
ONLINE_NAMES = {
    "medical": {"zh": "医学", "en": "Medicine", "ja": "医学"},
    "law": {"zh": "法律", "en": "Law", "ja": "法律"},
    "poem": {"zh": "诗词", "en": "Poetry", "ja": "詩詞"},
    "lishimingren": {"zh": "历史名人", "en": "Historical figures", "ja": "歴史上の人物"},
}
# 百科词库：中文维基百科条目标题（fcitx5-pinyin-zhwiki 的 release，已转成简体），过敏感词表、精简到 20 万条。
# 没给 --baike 时沿用 --online 目录里上次生成的；一次都没生成过，清单里 url 写 null，App 显示「准备中」。
BAIKE_LIMIT = 200_000
BAIKE = {
    "id": "baike", "name": {"zh": "百科词库", "en": "Wikipedia", "ja": "ウィキペディア辞書"},
    "summary": {"zh": "人名、地名、作品、游戏角色", "en": "People, places, works and game characters", "ja": "人名、地名、作品、ゲームキャラクター"},
    "license": "wiki", "entries": 200000, "size": 3100000, "version": "", "sha256": None, "url": None,
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
    """(词, 词频)。自整理的没有词频，按在表里的先后给。"""
    text = path.read_text(encoding="utf-8")
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


def weight(freq, top):
    """压到 1–9：按对数词频，最高的 9。"""
    if top <= 1:
        return 5
    return max(1, min(9, round(1 + 8 * math.log(freq + 1) / math.log(top + 1))))


def build(pack, kind, path, words, chars, blocklist, out):
    rows = read_words(kind, path)
    top = max((f for _, f in rows), default=1)
    seen, kept, skipped, blocked = set(), [], 0, []
    for word, freq in rows:
        if word in seen:
            continue
        seen.add(word)
        if word in blocklist:
            blocked.append(word)
            continue
        code = pinyin(word, words, chars)
        if not code or not re.fullmatch(r"[a-z]+( [a-z]+)*", code):
            skipped += 1
            continue
        kept.append((word, code, weight(freq, top)))
    source = "THUOCL 清华大学开放中文词库（github.com/thunlp/THUOCL），MIT 许可，Copyright (c) 2018 THUNLP" \
        if kind == "thuocl" else "飞地输入法整理"
    version = date.today().isoformat()
    target = out / f"ext_{pack}.dict.yaml"
    with target.open("w", encoding="utf-8") as f:
        f.write(f"# 飞地输入法扩展词库 · 来源：{source}\n# 由 scripts/build-ext-dicts.py 生成，拼音按万象拼音词库标注。\n")
        f.write(f"---\nname: ext_{pack}\nversion: \"{version}\"\nsort: by_weight\n...\n")
        for word, code, w in kept:
            f.write(f"{word}\t{code}\t{w}\n")
    print(f"  {pack}: {len(kept)} 条（查不到读音 {skipped}，过滤 {len(blocked)}{'：' + '、'.join(blocked) if blocked else ''}）")
    return {"id": pack, "entries": len(kept), "version": version, "size": target.stat().st_size}


def build_baike(path, words, chars, char_freq, blocklist, out):
    """维基标题没有词频，按「字常不常用、长度合不合适」打分，取前 20 万条。

    跳过：万象里已经有的词（基础词库能打出来）、不是 2–8 个汉字的、有生僻字（万象单字表里没有）的。
    分数 = 每个字的对数字频取平均，4 字以上每多一个字扣一点：常用字组成的短标题（人名、地名、作品名）排前面。"""
    rows, blocked, skipped = [], [], 0
    for text, code, _ in rime_entries(path):
        if text in words or not re.fullmatch(r"[\u4e00-\u9fff]{2,8}", text):
            continue
        if text in blocklist:
            blocked.append(text)
            continue
        if any(c not in char_freq for c in text):
            skipped += 1
            continue
        reading = pinyin(text, words, chars)
        if not reading or not re.fullmatch(r"[a-z]+( [a-z]+)*", reading) or len(reading.split()) != len(text):
            reading = code if re.fullmatch(r"[a-z]+( [a-z]+)*", code or "") and len(code.split()) == len(text) else None
        if not reading:
            skipped += 1
            continue
        score = sum(math.log(char_freq[c] + 1) for c in text) / len(text) - 0.6 * max(0, len(text) - 4)
        rows.append((score, text, reading))
    rows.sort(key=lambda r: -r[0])
    kept = rows[:BAIKE_LIMIT]
    version = date.today().isoformat()
    target = out / "ext_baike.dict.yaml"
    with target.open("w", encoding="utf-8") as f:
        f.write("# 飞地输入法扩展词库 · 来源：中文维基百科条目标题（zh.wikipedia.org），CC BY-SA 4.0；"
                f"标题表取自 fcitx5-pinyin-zhwiki（github.com/felixonmars/fcitx5-pinyin-zhwiki，{path.name}）\n"
                "# 由 scripts/build-ext-dicts.py 生成，拼音按万象拼音词库标注，按 CC BY-SA 4.0 分发。\n")
        f.write(f"---\nname: ext_baike\nversion: \"{version}\"\nsort: by_weight\n...\n")
        n = len(kept)
        for i, (_, text, reading) in enumerate(kept):
            f.write(f"{text}\t{reading}\t{max(1, 5 - (5 * i) // max(n, 1))}\n")
    print(f"  baike: {len(kept)} 条（候选 {len(rows)}，生僻字或查不到读音 {skipped}，"
          f"过滤 {len(blocked)}{'：' + '、'.join(blocked[:30]) + ('…' if len(blocked) > 30 else '') if blocked else ''}）")
    return {**BAIKE, "entries": len(kept), "size": target.stat().st_size, "version": version,
            "sha256": hashlib.sha256(target.read_bytes()).hexdigest(), "url": target.name}


def previous_baike(out):
    """没给 --baike：清单里上次生成的百科条目还对得上文件就沿用。"""
    try:
        old = json.loads((out / "catalog.json").read_text(encoding="utf-8"))
        entry = next(d for d in old["dicts"] if d["id"] == "baike")
        if entry.get("url") and (out / entry["url"]).exists():
            return {**BAIKE, **{k: entry[k] for k in ("entries", "size", "version", "sha256", "url")}}
    except (OSError, ValueError, KeyError, StopIteration):
        pass
    return BAIKE


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
    wanxiang, thuocl = Path(args[0]), Path(args[1])
    blocklist = set()
    if block_path:
        # 整词精确匹配：词和表里一模一样才删，不做包含匹配（见 05 的敏感词表说明）。# 开头是注释，空行跳过。
        blocklist = {l.strip() for l in Path(block_path).read_text(encoding="utf-8").splitlines()
                     if l.strip() and not l.strip().startswith("#")}
    else:
        print("提醒：没给 --blocklist，没过敏感词过滤，只能用于开发测试。")
    words, chars, char_freq = load_readings(wanxiang)
    OUT.mkdir(parents=True, exist_ok=True)
    print("内置词库：")
    manifest = []
    for pack, kind, name in BUILTIN:
        path = (SRC if kind == "self" else thuocl) / name
        manifest.append(build(pack, kind, path, words, chars, blocklist, OUT))
    (OUT / "builtin.json").write_text(json.dumps({"filtered": bool(block_path), "dicts": manifest}, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    if online_dir:
        out = Path(online_dir)
        out.mkdir(parents=True, exist_ok=True)
        print("在线词库：")
        catalog = [build_baike(Path(baike_path), words, chars, char_freq, blocklist, out) if baike_path else previous_baike(out)]
        for pack, kind, name in ONLINE:
            info = build(pack, kind, thuocl / name, words, chars, blocklist, out)
            path = out / f"ext_{pack}.dict.yaml"
            catalog.append({"id": pack, "name": ONLINE_NAMES[pack], "license": kind, "entries": info["entries"],
                            "size": info["size"], "version": info["version"],
                            "sha256": hashlib.sha256(path.read_bytes()).hexdigest(), "url": path.name})
        # THUOCL 的 MIT 许可原文跟在线词包放在一起分发。
        shutil.copyfile(OUT / "LICENSE-THUOCL.txt", out / "LICENSE-THUOCL.txt")
        (out / "catalog.json").write_text(json.dumps({"dicts": catalog}, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
