#!/usr/bin/env python3
"""从 OpenStreetMap 整理海外餐厅的中文名和英文名（T106，用户 11-27：有名的餐厅、网红餐厅；05 第四节第 3 条）。

用法（要能上外网。云端连不上 Overpass，在 Mac 上跑；scripts/update-wikidata-dicts.sh 会顺带跑）：
  python3 scripts/fetch-osm-names.py fetch <原始数据目录>
  python3 scripts/fetch-osm-names.py parse <原始数据目录> <万象 dicts 目录> <输出目录>

许可（05：compliance/词库-Wikidata/许可和审核要求.md 第四节）：
- OSM 数据是 ODbL 1.0，要求相同方式共享。所以从 OSM 来的词单独成一个在线词库（ext_osm）和一个英文补全文件
  （Keyboard/English/en_osm.tsv），按 ODbL 发布，署名「© OpenStreetMap contributors」，许可页单列一条。
- 只取名称（name:zh-Hans、name:zh、name:en、name），不取坐标、地址、营业时间。
- 中国大陆境内 OSM 数据少，不取；只取下面 REGIONS 里的地区。
- 中文名只收简体：name:zh-Hans；新加坡、马来西亚的 name:zh 本来就是简体，也收。
- 请求的 User-Agent 写项目地址，不写个人邮箱。App 不访问 OSM，只有这个开发脚本在开发机上一次性拉。

输出目录：
  osm.tsv      词\\t拼音\\t热度，给 build-ext-dicts.py --wikidata <输出目录> 生成在线词库 ext_osm
  en-osm.tsv   英文名\\t热度，给 build-english-names.py 生成 Keyboard/English/en_osm.tsv
  review-osm-hkmo.tsv  香港、澳门来源的中文名，全部交 05 看
热度：同名的店有几家（连锁多的靠前），有 wikidata、brand:wikidata 标签的另加分。
"""
import collections
import json
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import importlib.util
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ENDPOINTS = ["https://overpass-api.de/api/interpreter", "https://overpass.kumi.systems/api/interpreter"]
UA = "EnclaveDictBuilder/1.0 (https://github.com/cvbkQin/Enclave-QWERTY)"
# 地区：(编号, Overpass 里找这个地区的条件)。
REGIONS = [
    ("SG", '["ISO3166-1"="SG"]'), ("MY", '["ISO3166-1"="MY"]'), ("JP", '["ISO3166-1"="JP"]'),
    ("KR", '["ISO3166-1"="KR"]'), ("TH", '["ISO3166-1"="TH"]'), ("VN", '["ISO3166-1"="VN"]'),
    ("HK", '["ISO3166-2"="CN-HK"]'), ("MO", '["ISO3166-2"="CN-MO"]'),
]
# name:zh 本来就是简体的地区。
SIMPLIFIED = {"SG", "MY"}
AMENITY = "restaurant|cafe|fast_food|food_court|ice_cream"
HAN = re.compile(r"[一-鿿]{2,12}")
EN_NAME = re.compile(r"[A-Za-z][A-Za-z0-9 .'&-]{1,39}")
LIMITS = {"osm": 60_000}


def overpass(query, retries=4):
    data = urllib.parse.urlencode({"data": query}).encode()
    for attempt in range(retries):
        url = ENDPOINTS[attempt % len(ENDPOINTS)]
        request = urllib.request.Request(url, data=data, headers={"User-Agent": UA})
        try:
            with urllib.request.urlopen(request, timeout=900) as response:
                return json.loads(response.read().decode("utf-8"))["elements"]
        except urllib.error.HTTPError as error:
            # 429、504：服务器忙，等一会儿换一台再试。
            print(f"    {url} HTTP {error.code}，{30 * (attempt + 1)} 秒后再试", flush=True)
        except (TimeoutError, urllib.error.URLError, ConnectionError, json.JSONDecodeError, UnicodeDecodeError) as error:
            print(f"    {url} {error}，{30 * (attempt + 1)} 秒后再试", flush=True)
        time.sleep(30 * (attempt + 1))
    raise TimeoutError("重试次数用完")


def fetch(raw):
    raw.mkdir(parents=True, exist_ok=True)
    print("OpenStreetMap 海外餐厅：")
    for code, area in REGIONS:
        path = raw / f"osm_{code}.json"
        if path.exists():
            continue
        print(f"  {code} …", flush=True)
        query = f"""[out:json][timeout:900];
area{area}->.a;
nwr["amenity"~"^({AMENITY})$"][~"^name:zh"~"."](area.a);
out tags;"""
        tags = [element.get("tags", {}) for element in overpass(query)]
        path.write_text(json.dumps(tags, ensure_ascii=False), encoding="utf-8")
        time.sleep(5)
    print(f"下好了：{raw}")


def clean(text):
    text = re.sub(r"[（(][^）)]*[）)]", "", text)
    return re.sub(r"\s+", "", text)


def english(tags):
    for key in ("name:en", "name"):
        name = re.sub(r"\s+", " ", re.sub(r"[（(][^）)]*[）)]", "", tags.get(key, ""))).strip()
        if EN_NAME.fullmatch(name):
            return name
    return None


def parse(raw, wanxiang, out):
    spec = importlib.util.spec_from_file_location("build_ext_dicts", ROOT / "scripts" / "build-ext-dicts.py")
    build = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(build)
    words, chars, _ = build.load_readings(wanxiang)
    zh_count, en_count = collections.Counter(), collections.Counter()
    hkmo = set()
    for code, _ in REGIONS:
        path = raw / f"osm_{code}.json"
        if not path.exists():
            print(f"  没有 {path.name}，跳过")
            continue
        for tags in json.loads(path.read_text(encoding="utf-8")):
            bonus = 3 if ("wikidata" in tags or "brand:wikidata" in tags) else 0
            zh = tags.get("name:zh-Hans") or (tags.get("name:zh") if code in SIMPLIFIED else None)
            if zh:
                for part in re.split(r"[;；/]", zh):
                    name = clean(part)
                    if HAN.fullmatch(name):
                        zh_count[name] += 1 + bonus
                        if code in ("HK", "MO"):
                            hkmo.add((code, name, zh))
            name = english(tags)
            if name:
                en_count[name] += 1 + bonus
    rows, skipped = [], 0
    for word, popularity in sorted(zh_count.items(), key=lambda kv: (-kv[1], kv[0])):
        if word in words:
            continue
        reading = build.pinyin(word, words, chars)
        if not reading or not re.fullmatch(r"[a-z]+( [a-z]+)*", reading) or len(reading.split()) != len(word):
            skipped += 1
            continue
        rows.append((word, reading, popularity))
    rows = rows[:LIMITS["osm"]]
    out.mkdir(parents=True, exist_ok=True)
    (out / "osm.tsv").write_text("".join("\t".join(map(str, r)) + "\n" for r in rows), encoding="utf-8")
    en_rows = sorted(en_count.items(), key=lambda kv: (-kv[1], kv[0]))[:LIMITS["osm"]]
    (out / "en-osm.tsv").write_text("".join(f"{n}\t{c}\n" for n, c in en_rows), encoding="utf-8")
    # 香港、澳门来源的中文名全部交 05 看（05 核对 PR #127 第 3 条）。
    (out / "review-osm-hkmo.tsv").write_text("# 待审（05）：地区\t词条\tOSM 原名\n" + "".join(f"{c}\t{n}\t{o}\n" for c, n, o in sorted(hkmo)),
                                             encoding="utf-8")
    print(f"  osm: {len(rows)} 条（标不出拼音 {skipped}），英文名 {len(en_rows)} 条；香港、澳门来源 {len(hkmo)} 条写进 review-osm-hkmo.tsv")


def main():
    args = sys.argv[1:]
    if len(args) == 2 and args[0] == "fetch":
        fetch(Path(args[1]))
    elif len(args) == 4 and args[0] == "parse":
        parse(Path(args[1]), Path(args[2]), Path(args[3]))
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
