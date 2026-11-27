#!/usr/bin/env python3
"""从 Wikidata 整理景点、机场、地标、有名的餐厅（内置词库 lvyou）和人物（在线词库 renwu）的中文名（T106，用户 11-27：
「词库还需要增加各地热门景点，机场，地标，名人」，例子是新加坡樟宜机场打不出来）。

用法（要能上外网。云端连不上 wikidata.org，在 Mac 上跑；一步跑完用 scripts/update-wikidata-dicts.sh）：
  python3 scripts/fetch-wikidata-names.py fetch <原始数据目录>
  python3 scripts/fetch-wikidata-names.py parse <原始数据目录> <万象 dicts 目录> <输出目录>

两步分开：下载的原始 JSON 留在原始数据目录，整理规则改了不用重新下载；fetch 跑到一半断了再跑一次，下好的不重下。
每类先只查编号和热度，名字、地名前缀再按 500 个编号一批查（一次查全部，结果太大会被查询服务截断），
每批存在原始数据目录的 parts/ 里，断了从断的那一批接着下。

许可和审核（05：项目文件 compliance/词库-Wikidata/许可和审核要求.md）：
- Wikidata 的结构化数据是 CC0 1.0。只取中文标签（label）和别名（alias），不取维基百科正文、摘要、描述。
- 地名只用简体（zh-hans、zh-cn）标签，是中国大陆的标准写法；不收「中华民国」开头的、「台湾国」这类写法和带政治含义的别名。
- 人物按知名度（sitelinks：有多少种语言的维基写了这个人）设下限；按职业排除色情演员，按信仰、组织排除法轮功等
  （名单在下面 EXCLUDE_*，05 补）；中国大陆、台湾、香港、澳门籍的政治人物和有「被判有罪」（P1399）的人不收进词库，
  单独写进待审文件交 05 人工看。
- 拼音不是 Wikidata 给的，按万象拼音词库标注（和 build-ext-dicts.py 同一套）。
- 请求的 User-Agent 写项目地址，不写个人邮箱。App 不访问 Wikidata，只有这个开发脚本在开发机上一次性拉。

输出目录（不进仓库：待审文件里是要人工看的敏感人名，仓库是公开的）：
  lvyou.tsv、renwu.tsv   词\\t拼音\\t热度（sitelinks），给 build-ext-dicts.py --wikidata <输出目录> 生成词库
  en-lvyou.tsv、en-renwu.tsv  英文名\\t热度，给 scripts/build-english-names.py 生成英文补全的专有名词
  review-politicians.tsv 待审：大陆、台湾、香港、澳门籍政治人物（交 05）
  review-convicted.tsv   待审：有判罪记录的人（交 05）
  excluded.tsv           按规则排除掉的（色情演员、法轮功和名单里的组织、政治写法的地名），05 备查
"""
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
ENDPOINT = "https://query.wikidata.org/sparql"
UA = "EnclaveDictBuilder/1.0 (https://github.com/cvbkQin/Enclave-QWERTY)"
ZH = '"zh-hans", "zh-cn"'
# 英文名（用户 11-27：「这些都需要中英文的」）：进英文补全（Keyboard/English/en_names.tsv）。
LANGS = ZH + ', "en"'

# 景点、地标：直接属于这些类型（P31，不追子类，查询才不超时）的条目。值是 sitelinks 下限：越常见的类型下限越高，只留有名的。
PLACE_CLASSES = {
    "Q570116": ("景点", 3),
    "Q2319498": ("地标", 3),
    "Q33506": ("博物馆", 8),
    "Q207694": ("美术馆", 6),
    "Q46169": ("国家公园", 4),
    "Q194195": ("游乐园", 4),
    "Q22698": ("公园", 8),
    "Q1107656": ("园林", 6),
    "Q167346": ("植物园", 6),
    "Q43501": ("动物园", 5),
    "Q2281788": ("水族馆", 5),
    "Q12518": ("塔", 6),
    "Q1440300": ("观光塔", 4),
    "Q11303": ("摩天大楼", 6),
    "Q12280": ("桥", 10),
    "Q16560": ("宫殿", 6),
    "Q23413": ("城堡", 10),
    "Q44539": ("寺庙", 6),
    "Q2977": ("主教座堂", 10),
    "Q4989906": ("纪念碑", 8),
    "Q5003624": ("纪念馆", 6),
    "Q174782": ("广场", 8),
    "Q483110": ("体育场", 10),
    "Q8502": ("山", 15),
    "Q23397": ("湖", 15),
    "Q34038": ("瀑布", 6),
    "Q40080": ("海滩", 6),
    "Q39594": ("岛", 20),
    "Q1497375": ("建筑群", 6),
    "Q839954": ("考古遗址", 10),
    "Q11315": ("购物中心", 4),
    "Q2416723": ("主题公园", 3),
}
# 餐厅（用户 11-27 补：有名的餐厅、米其林这类榜单上的）：只用 Wikidata 自己的数据（CC0），不抓米其林、大众点评等榜单网站。
# 餐厅及其子类（快餐店、咖啡馆连锁等）按 sitelinks 下限取；拿过奖（P166，米其林星级在 Wikidata 里记在这里）的不论 sitelinks 都收。
RESTAURANT = "Q11707"
RESTAURANT_MIN_SITELINKS = 3
# 世界遗产（P1435 = Q9259）不论类型都收。
WORLD_HERITAGE = "Q9259"

# 人物：sitelinks 下限。≥ 20 大约是「好几个大语种的维基都有条目」，冷门人物（包括大量冷门敏感人物）先去掉。
PEOPLE_MIN_SITELINKS = 20
# 按出生年份分段查（一次查全部人会超时）；超时的段自动再对半分。
PEOPLE_RANGES = [(-3000, 1000), (1000, 1500), (1500, 1700), (1700, 1800), (1800, 1850), (1850, 1900)] + \
    [(y, y + 10) for y in range(1900, 2030, 10)]

# 排除：职业是这些（含子类）的人不收。Q488111 色情演员（AV 女优是它的子类）。05 要加的写在这里。
EXCLUDE_OCCUPATIONS = ["Q488111"]
# 排除：宗教（P140）、所属组织（P463）、政党（P102）是这些的人不收。Q190765 法轮功。其余名单由 05 按 compliance/blocklist 的分类补。
EXCLUDE_ORGS = ["Q190765"]
# 待审：这些国籍（P27）的政治人物（职业是政治人物 Q82955 及子类，或担任过职务 P39）。
# Q148 中华人民共和国、Q865 台湾、Q8646 香港、Q14773 澳门。
REVIEW_CITIZENSHIP = ["Q148", "Q865", "Q8646", "Q14773"]

# 地名不收的写法（05 第二节第 1 步）：开头、包含。这些词也要进敏感词表。
PLACE_DENY_PREFIX = ("中华民国",)
PLACE_DENY_CONTAINS = ("台湾国", "东突厥斯坦", "东突")

# 每个词库最多收多少条（按热度排）。
LIMITS = {"lvyou": 60_000, "renwu": 120_000}


BATCH = 500


def sparql(query, retries=4):
    data = urllib.parse.urlencode({"query": query}).encode()
    request = urllib.request.Request(ENDPOINT, data=data, headers={
        "User-Agent": UA, "Accept": "application/sparql-results+json",
        "Content-Type": "application/x-www-form-urlencoded"})
    for attempt in range(retries):
        try:
            with urllib.request.urlopen(request, timeout=90) as response:
                # 查询服务 60 秒超时时会把已经出来的一半结果发过来，JSON 不完整，下面按出错重试。
                return json.loads(response.read().decode("utf-8"))["results"]["bindings"]
        except urllib.error.HTTPError as error:
            # 429：按 Retry-After 等；500/502/504 多半是查询超时，交给调用的地方拆小。
            if error.code == 429:
                time.sleep(int(error.headers.get("Retry-After", "30")))
                continue
            if error.code in (500, 502, 503, 504) and attempt == retries - 1:
                raise TimeoutError(f"HTTP {error.code}") from error
            time.sleep(5 * (attempt + 1))
        except (TimeoutError, urllib.error.URLError, ConnectionError, json.JSONDecodeError, UnicodeDecodeError) as error:
            if attempt == retries - 1:
                raise TimeoutError(str(error)) from error
            time.sleep(5 * (attempt + 1))
    raise TimeoutError("重试次数用完")


def qid(binding, key="item"):
    return binding[key]["value"].rsplit("/", 1)[-1]


def save(raw, name, rows):
    (raw / name).write_text(json.dumps(rows, ensure_ascii=False), encoding="utf-8")


def fetch_once(raw, name, query):
    """只有编号的小查询（排除、待审名单）：下好了就不重下。"""
    path = raw / name
    if path.exists():
        return
    print(f"  {name} …", flush=True)
    rows = sparql(query)
    save(raw, name, rows)
    time.sleep(1)


# MARK: - 查询

def values(qids):
    return "VALUES ?item { " + " ".join(f"wd:{q}" for q in qids) + " }"


def labels_query(qids):
    """中文（简体）和英文的标签、别名，一行一个（label 或 alias 二选一，不做交叉，结果小）。"""
    return f"""SELECT ?item ?label ?alias WHERE {{
  {values(qids)}
  {{ ?item rdfs:label ?label . FILTER(LANG(?label) IN ({LANGS})) }}
  UNION
  {{ ?item skos:altLabel ?alias . FILTER(LANG(?alias) IN ({LANGS})) }}
}}"""


def prefixes_query(qids):
    """地名前面常带的城市、所在地、国家名（「新加坡樟宜机场」的「新加坡」），整理时去掉它得到简称「樟宜机场」。"""
    return f"""SELECT ?item ?prefix WHERE {{
  {values(qids)}
  ?item wdt:P931|wdt:P131|wdt:P17 ?place .
  ?place rdfs:label ?prefix . FILTER(LANG(?prefix) IN ({ZH}))
}}"""


def batched(raw, stem, kind, qids, make_query):
    """按 BATCH 个编号一批查，每批存 parts/，下好的批不重下。"""
    parts = raw / "parts"
    parts.mkdir(exist_ok=True)
    rows = []
    total = (len(qids) + BATCH - 1) // BATCH
    for index in range(total):
        path = parts / f"{stem}_{kind}_{index:04d}.json"
        if not path.exists():
            print(f"    {stem} {kind} {index + 1}/{total}", flush=True)
            save(parts, path.name, sparql(make_query(qids[index * BATCH:(index + 1) * BATCH])))
            time.sleep(0.5)
        rows += json.loads(path.read_text(encoding="utf-8"))
    return rows


def fetch_set(raw, stem, where, prefixes=True):
    """一类条目：先查编号和热度（sitelinks），再分批查中文名、别名和地名前缀。
    写出 <stem>.json（item、sl、label、alias，和 parse 读的格式一样）和 <stem>_prefix.json。"""
    done = (raw / f"{stem}.json").exists() and (not prefixes or (raw / f"{stem}_prefix.json").exists())
    if done:
        return
    print(f"  {stem} …", flush=True)
    ids_path = raw / "parts" / f"{stem}_ids.json"
    (raw / "parts").mkdir(exist_ok=True)
    if not ids_path.exists():
        # 编号查询超时多半是一次查太多，少试几次，交给人物那边按年份拆小。
        rows = sparql(f"SELECT DISTINCT ?item ?sl WHERE {{\n  {where}\n  ?item wikibase:sitelinks ?sl .\n}}", retries=2)
        save(raw / "parts", ids_path.name, rows)
    sitelinks = {}
    for row in json.loads(ids_path.read_text(encoding="utf-8")):
        sitelinks[qid(row)] = max(sitelinks.get(qid(row), 0), int(row["sl"]["value"]))
    qids = sorted(sitelinks)
    if not (raw / f"{stem}.json").exists():
        rows = batched(raw, stem, "labels", qids, labels_query)
        for row in rows:
            row["sl"] = {"value": str(sitelinks[qid(row)])}
        save(raw, f"{stem}.json", rows)
    if prefixes and not (raw / f"{stem}_prefix.json").exists():
        save(raw, f"{stem}_prefix.json", batched(raw, stem, "prefix", qids, prefixes_query))


def xsd_year(year):
    """xsd:dateTime 的年份：至少 4 位，公元前写负号（-3000）。"""
    return f"{year:04d}" if year >= 0 else f"-{-year:04d}"


def fetch_people(raw, y0, y1):
    stem = f"people_{y0}_{y1}"
    if (raw / f"{stem}.json").exists():
        return
    # rangeSafe：告诉查询服务年份、sitelinks 的类型一致，可以按范围走索引，不然要扫全部一千多万人、必定超时。
    where = f"""?item wdt:P569 ?born . hint:Prior hint:rangeSafe true .
  ?item wikibase:sitelinks ?n . hint:Prior hint:rangeSafe true .
  ?item wdt:P31 wd:Q5 .
  FILTER(?n >= {PEOPLE_MIN_SITELINKS})
  FILTER(?born >= "{xsd_year(y0)}-01-01T00:00:00Z"^^xsd:dateTime && ?born < "{xsd_year(y1)}-01-01T00:00:00Z"^^xsd:dateTime)"""
    split = raw / "parts" / f"{stem}.split"
    try:
        if split.exists():
            raise TimeoutError("上次已经拆开")
        fetch_set(raw, stem, where, prefixes=False)
    except TimeoutError:
        if (raw / "parts" / f"{stem}_ids.json").exists():
            raise  # 编号查到了、分批查名字还失败，是网络问题，不拆；再跑一次接着下
        if y1 - y0 <= 1:
            print(f"  {stem} 一直超时，跳过", flush=True)
            return
        mid = (y0 + y1) // 2
        if not split.exists():
            print(f"  {stem} 超时，拆成 {y0}–{mid}、{mid}–{y1}", flush=True)
            split.parent.mkdir(exist_ok=True)
            split.write_text("", encoding="utf-8")
        fetch_people(raw, y0, mid)
        fetch_people(raw, mid, y1)


def fetch(raw):
    raw.mkdir(parents=True, exist_ok=True)
    print("机场（有 IATA 代码的）：")
    fetch_set(raw, "airport", "?item wdt:P238 ?iata .")
    print("景点、地标：")
    for cls, (title, minimum) in PLACE_CLASSES.items():
        where = f"?item wdt:P31 wd:{cls} ; wikibase:sitelinks ?n . FILTER(?n >= {minimum})"
        fetch_set(raw, f"place_{cls}", where)
    print("餐厅：")
    restaurant = f"?item wdt:P31/wdt:P279* wd:{RESTAURANT} ; wikibase:sitelinks ?n . FILTER(?n >= {RESTAURANT_MIN_SITELINKS})"
    fetch_set(raw, "place_restaurant", restaurant)
    fetch_set(raw, "place_restaurant_award", f"?item wdt:P31/wdt:P279* wd:{RESTAURANT} ; wdt:P166 ?award .")
    heritage = f"?item wdt:P1435 wd:{WORLD_HERITAGE} ."
    fetch_set(raw, "place_heritage", heritage)
    print("人物：")
    for y0, y1 in PEOPLE_RANGES:
        fetch_people(raw, y0, y1)
    print("人物排除名单、待审名单：")
    # 只查热度够进人物词库的人（和上面同一个 sitelinks 下限），结果小，不会被截断。
    famous = f"?item wikibase:sitelinks ?n . FILTER(?n >= {PEOPLE_MIN_SITELINKS})"
    for occupation in EXCLUDE_OCCUPATIONS:
        fetch_once(raw, f"exclude_occupation_{occupation}.json",
                   f"SELECT DISTINCT ?item WHERE {{ ?item wdt:P106/wdt:P279* wd:{occupation} . {famous} }}")
    for org in EXCLUDE_ORGS:
        fetch_once(raw, f"exclude_org_{org}.json",
                   f"SELECT DISTINCT ?item WHERE {{ ?item wdt:P140|wdt:P463|wdt:P102 wd:{org} . {famous} }}")
    citizenship = " ".join(f"wd:{c}" for c in REVIEW_CITIZENSHIP)
    fetch_once(raw, "review_politician.json", f"""SELECT DISTINCT ?item WHERE {{
  VALUES ?country {{ {citizenship} }}
  ?item wdt:P27 ?country ; wdt:P106/wdt:P279* wd:Q82955 .
  {famous}
}}""")
    fetch_once(raw, "review_position.json", f"""SELECT DISTINCT ?item WHERE {{
  VALUES ?country {{ {citizenship} }}
  ?item wdt:P27 ?country ; wdt:P39 ?position ; wdt:P31 wd:Q5 .
  {famous}
}}""")
    fetch_once(raw, "review_convicted.json",
               f"SELECT DISTINCT ?item WHERE {{ ?item wdt:P1399 ?crime ; wdt:P31 wd:Q5 . {famous} }}")
    print(f"下好了：{raw}")


# MARK: - 整理

HAN = re.compile(r"[一-鿿]{2,10}")
DOTS = re.compile(r"[·・•‧∙]")


def clean(text):
    """去掉括号里的说明（「长城（中国）」）和空格。"""
    text = re.sub(r"[（(][^）)]*[）)]", "", text)
    return re.sub(r"\s+", "", text)


def load_items(raw, pattern):
    """{qid: (sitelinks, {中文名和别名}, {英文名和别名})}"""
    items = {}
    for path in sorted(raw.glob(pattern)):
        if path.name.endswith("_prefix.json"):
            continue
        for row in json.loads(path.read_text(encoding="utf-8")):
            q = qid(row)
            sl, zh, en = items.get(q, (0, set(), set()))
            sl = max(sl, int(row["sl"]["value"]))
            for key in ("label", "alias"):
                if key in row:
                    lang = row[key].get("xml:lang", "zh-hans")
                    (en if lang == "en" else zh).add(row[key]["value"])
            items[q] = (sl, zh, en)
    return items


def load_prefixes(raw):
    prefixes = {}
    for path in raw.glob("*_prefix.json"):
        for row in json.loads(path.read_text(encoding="utf-8")):
            prefixes.setdefault(qid(row), set()).add(clean(row["prefix"]["value"]))
    return prefixes


def load_ids(raw, pattern):
    ids = set()
    for path in raw.glob(pattern):
        ids.update(qid(row) for row in json.loads(path.read_text(encoding="utf-8")))
    return ids


def place_forms(name, prefixes):
    """「新加坡樟宜机场」→ 本身、去掉前面地名的「樟宜机场」、「国际机场」换成「机场」、机场的核心名「樟宜」。"""
    forms = {name}
    for prefix in prefixes:
        if len(prefix) >= 2 and name.startswith(prefix) and len(name) - len(prefix) >= 3:
            forms.add(name[len(prefix):])
    for form in list(forms):
        if form.endswith("国际机场") and len(form) > 5:
            forms.add(form[:-4] + "机场")
        core = re.sub(r"(国际)?机场$", "", form)
        if core != form and 2 <= len(core) <= 4:
            forms.add(core)
    return forms


def person_forms(name):
    """「唐纳德·特朗普」→「唐纳德特朗普」和姓「特朗普」（两个字以上）；中文名照原样。"""
    parts = [p for p in DOTS.split(name) if p]
    forms = {"".join(parts)}
    if len(parts) > 1 and len(parts[-1]) >= 2:
        forms.add(parts[-1])
    return forms


def place_denied(name):
    return name.startswith(PLACE_DENY_PREFIX) or any(word in name for word in PLACE_DENY_CONTAINS)


EN_NAME = re.compile(r"[A-Za-z][A-Za-z0-9 .'&-]{1,39}")
EN_DENY = ("republic of china", "east turkestan", "taiwan country")


def english(name):
    """英文名：去掉括号里的说明、多余空格；只留拉丁字母写的（不带变音符号，英文键盘打得出来）。"""
    name = re.sub(r"\s+", " ", re.sub(r"[（(][^）)]*[）)]", "", name)).strip()
    if not EN_NAME.fullmatch(name) or any(word in name.lower() for word in EN_DENY):
        return None
    return name


def write_english(out, pack, scored):
    rows = sorted(scored.items(), key=lambda kv: (-kv[1], kv[0]))[:LIMITS[pack]]
    write_tsv(out / f"en-{pack}.tsv", rows)
    print(f"  {pack} 英文名：{len(rows)} 条")


def readings_module():
    spec = importlib.util.spec_from_file_location("build_ext_dicts", ROOT / "scripts" / "build-ext-dicts.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def write_tsv(path, rows):
    path.write_text("".join("\t".join(map(str, row)) + "\n" for row in rows), encoding="utf-8")


def parse(raw, wanxiang, out):
    build = readings_module()
    words, chars, _ = build.load_readings(wanxiang)
    out.mkdir(parents=True, exist_ok=True)
    excluded = []

    def finish(pack, scored):
        """scored: {词: 热度}。万象里已经有的词不收（基础词库打得出来），标不出拼音的不收，按热度取前 LIMITS 条。"""
        rows, skipped = [], 0
        for word, popularity in sorted(scored.items(), key=lambda kv: (-kv[1], kv[0])):
            if word in words or not HAN.fullmatch(word):
                continue
            reading = build.pinyin(word, words, chars)
            if not reading or not re.fullmatch(r"[a-z]+( [a-z]+)*", reading) or len(reading.split()) != len(word):
                skipped += 1
                continue
            rows.append((word, reading, popularity))
        rows = rows[:LIMITS[pack]]
        write_tsv(out / f"{pack}.tsv", rows)
        print(f"  {pack}: {len(rows)} 条（标不出拼音 {skipped}）")

    print("景点、机场、地标：")
    prefixes = load_prefixes(raw)
    places = {**load_items(raw, "place_*.json"), **load_items(raw, "airport*.json")}
    scored, scored_en = {}, {}
    for q, (sl, zh, en) in places.items():
        for name in map(clean, zh):
            if place_denied(name):
                excluded.append(("地名写法", q, name))
                continue
            for form in place_forms(name, prefixes.get(q, set())):
                scored[form] = max(scored.get(form, 0), sl)
        for name in filter(None, map(english, en)):
            scored_en[name] = max(scored_en.get(name, 0), sl)
    finish("lvyou", scored)
    write_english(out, "lvyou", scored_en)

    print("人物：")
    people = load_items(raw, "people_*.json")
    blocked = load_ids(raw, "exclude_*.json")
    politicians = load_ids(raw, "review_politician.json") | load_ids(raw, "review_position.json")
    convicted = load_ids(raw, "review_convicted.json")
    scored, scored_en, review_politicians, review_convicted = {}, {}, [], []
    for q, (sl, zh, en) in people.items():
        names = sorted(map(clean, zh)) + sorted(filter(None, map(english, en)))
        if q in blocked:
            excluded += [("职业或组织", q, name) for name in names]
            continue
        if q in politicians or q in convicted:
            target = review_politicians if q in politicians else review_convicted
            target += [(q, name, sl) for name in names]
            continue
        for name in map(clean, zh):
            for form in person_forms(name):
                scored[form] = max(scored.get(form, 0), sl)
        for name in filter(None, map(english, en)):
            scored_en[name] = max(scored_en.get(name, 0), sl)
    finish("renwu", scored)
    write_english(out, "renwu", scored_en)
    header = [("# 待审（05）：Wikidata 编号\t名字\t热度（sitelinks）。看完标出保留的，保留的由 01 加回词库。",)]
    write_tsv(out / "review-politicians.tsv", header + sorted(review_politicians, key=lambda r: -r[2]))
    write_tsv(out / "review-convicted.tsv", header + sorted(review_convicted, key=lambda r: -r[2]))
    write_tsv(out / "excluded.tsv", [("# 按规则排除：原因\tWikidata 编号\t名字",)] + excluded)
    print(f"  待审：政治人物 {len(review_politicians)} 个名字，有判罪记录 {len(review_convicted)} 个名字；按规则排除 {len(excluded)} 个")
    print(f"整理好了：{out}")


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
