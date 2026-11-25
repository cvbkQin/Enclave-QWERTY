#!/usr/bin/env python3
"""从游戏官网、官方维基的公开数据整理游戏词表，写到 scripts/ext-dicts/<id>.txt。

用法：
  python3 scripts/fetch-game-words.py fetch <原始数据目录>   # 下载官方数据（要能上外网）
  python3 scripts/fetch-game-words.py parse <原始数据目录>   # 整理成词表

两步分开：下载的原始 JSON 留在原始数据目录（不进仓库），整理规则改了不用重新下载。
只用官方来源，不抓第三方 fan wiki：
  英雄联盟  国服官网 lol.qq.com 的数据（game.gtimg.cn），缺的用 Riot 官方 Data Dragon 的 zh_CN
  王者荣耀  官网 pvp.qq.com 的英雄、装备、召唤师技能、皮肤
  Dota 2    官网 dota2.com 的 datafeed（简体中文）
  原神      米游社「观测枢」（miHoYo 官方维基）
  和平精英  官网 gp.qq.com「游戏资料」的枪械、载具（官网用的 infocms 数据）
词表里只留纯中文的名字（去掉「·」和空格），其余交给 build-ext-dicts.py 标拼音、过敏感词表。
"""
import gzip
import http.client
import json
import re
import sys
import time
import urllib.request
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "scripts" / "ext-dicts"
UA = {"User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 Safari/605.1.15",
      "Referer": "https://lol.qq.com/"}

OBC = "https://api-takumi-static.mihoyo.com/common/blackboard/ys_obc/v1"

# (保存的文件名, URL)。{ddv} 是 Data Dragon 的最新版本号。
SOURCES = {
    "lol": [
        ("hero_list.json", "https://game.gtimg.cn/images/lol/act/img/js/heroList/hero_list.js"),
        ("items.json", "https://game.gtimg.cn/images/lol/act/img/js/items/items.js"),
        ("dd_versions.json", "https://ddragon.leagueoflegends.com/api/versions.json"),
        ("dd_champion.json", "https://ddragon.leagueoflegends.com/cdn/{ddv}/data/zh_CN/champion.json"),
        ("dd_item.json", "https://ddragon.leagueoflegends.com/cdn/{ddv}/data/zh_CN/item.json"),
        ("dd_summoner.json", "https://ddragon.leagueoflegends.com/cdn/{ddv}/data/zh_CN/summoner.json"),
        ("dd_runes.json", "https://ddragon.leagueoflegends.com/cdn/{ddv}/data/zh_CN/runesReforged.json"),
        ("dd_map.json", "https://ddragon.leagueoflegends.com/cdn/{ddv}/data/zh_CN/map.json"),
    ],
    "wzry": [
        ("herolist.json", "https://pvp.qq.com/web201605/js/herolist.json"),
        ("item.json", "https://pvp.qq.com/web201605/js/item.json"),
        ("summoner.json", "https://pvp.qq.com/web201605/js/summoner.json"),
    ],
    "dota2": [
        ("herolist.json", "https://www.dota2.com/datafeed/herolist?language=schinese"),
        ("itemlist.json", "https://www.dota2.com/datafeed/itemlist?language=schinese"),
    ],
    "genshin": [
        # 「图鉴」栏目（189）一次带回所有子栏目和各自的完整列表。
        ("obc_189.json", OBC + "/home/content/list?app_sn=ys_obc&channel_id=189"),
    ],
    # 官网首页「游戏资料」的枪械、载具两栏（web202411/js/rander_cms_ready.js 里的 id）。
    "hpjy": [
        ("guns.json", "https://fza.qq.com/infocms/data/gp/os/684259ce333f5ab1a4921ee0.json"),
        ("vehicles.json", "https://fza.qq.com/infocms/data/gp/os/684259d4333f5ab1a4921ee8.json"),
    ],
}

NAMES = {
    "lol": "英雄联盟",
    "wzry": "王者荣耀",
    "dota2": "Dota 2",
    "genshin": "原神",
    "hpjy": "和平精英",
}
CREDITS = {
    "lol": "英雄联盟国服官网（lol.qq.com）公开数据，Riot Data Dragon zh_CN 补充",
    "wzry": "王者荣耀官网（pvp.qq.com）公开数据",
    "dota2": "Dota 2 官网（dota2.com）datafeed 简体中文",
    "genshin": "米游社「观测枢」原神官方维基（bbs.mihoyo.com/ys/obc）",
    "hpjy": "和平精英官网（gp.qq.com）「游戏资料」枪械、载具，加上飞地整理的常用说法",
}
# 观测枢「图鉴」里要收的子栏目，按这个顺序排（越靠前词频越高）；栏目名完全一样才收。
# 不收：角色逸闻 / 彩蛋、成就、任务、活动、地图文本、书籍、名片、教程、洞天摆设等（多是标题或句子，不是名字）。
OBC_WANT = ["角色", "武器", "圣遗物", "敌人", "秘境", "组织", "食物", "背包", "动物", "NPC&商店"]


def get(url, tries=4):
    """下载；连接被中途断开（IncompleteRead）时重试几次。"""
    for attempt in range(tries):
        try:
            # 要 gzip：观测枢图鉴有 7 MB，不压缩时常被中途断开。
            req = urllib.request.Request(url, headers={**UA, "Accept-Encoding": "gzip"})
            with urllib.request.urlopen(req, timeout=60) as resp:
                raw = resp.read()
                if resp.headers.get("Content-Encoding") == "gzip":
                    raw = gzip.decompress(raw)
            break
        except http.client.IncompleteRead:
            if attempt == tries - 1:
                raise
            time.sleep(2 * (attempt + 1))
    for enc in ("utf-8", "gbk"):
        try:
            return raw.decode(enc)
        except UnicodeDecodeError:
            pass
    return raw.decode("utf-8", "replace")


def as_json(text):
    """官网的 .js 有的是 `var x = {...};`，取第一个 { 或 [ 到最后一个 } 或 ]。"""
    text = text.strip()
    start = min([i for i in (text.find("{"), text.find("[")) if i >= 0], default=0)
    end = max(text.rfind("}"), text.rfind("]"))
    return json.loads(text[start:end + 1])


def fetch(raw):
    raw.mkdir(parents=True, exist_ok=True)
    ddv = None
    for game, items in SOURCES.items():
        folder = raw / game
        folder.mkdir(exist_ok=True)
        for name, url in items:
            # 已经下好的不重下（网络不稳时多跑几次补齐缺的）；删掉原始数据目录就全部重下。
            if (folder / name).exists():
                if name == "dd_versions.json":
                    ddv = json.loads((folder / name).read_text(encoding="utf-8"))[0]
                print(f"  {game}/{name}: 已有")
                continue
            if "{ddv}" in url:
                if not ddv:
                    print(f"  {game}/{name}: 跳过（没拿到 Data Dragon 版本号）")
                    continue
                url = url.replace("{ddv}", ddv)
            try:
                data = as_json(get(url))
            except Exception as e:  # noqa: BLE001 — 单个来源失败不影响其他
                print(f"  {game}/{name}: 失败 {e}")
                continue
            (folder / name).write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")
            if name == "dd_versions.json":
                ddv = data[0]
            print(f"  {game}/{name}: 好")


def clean(name):
    """去掉「·」、空格和括号里的说明；只留纯中文、2–8 个字。"""
    if not isinstance(name, str):
        return None
    name = re.sub(r"[（(【\[].*?[)）】\]]", "", name)
    name = re.sub(r"[·・•\s　\-—]", "", name)
    if not re.fullmatch(r"[一-鿿]{2,8}", name):
        return None
    # 官方数据里的占位、兑换券、活动道具之类，不是游戏里的名字。
    if any(w in name for w in ("占位", "兑换券", "邀请函", "符文等级")):
        return None
    return name


def load(folder, name):
    path = folder / name
    return json.loads(path.read_text(encoding="utf-8")) if path.exists() else None


def parse_lol(f):
    heroes, items, misc = [], [], []
    if data := load(f, "hero_list.json"):
        for h in data.get("hero", []):
            heroes += [h.get("title"), h.get("name")]  # title 是「亚索」，name 是「疾风剑豪」
    if data := load(f, "dd_champion.json"):
        for h in data.get("data", {}).values():
            heroes += [h.get("title"), h.get("name")]
    if data := load(f, "items.json"):
        items += [i.get("name") for i in data.get("items", [])]
    if data := load(f, "dd_item.json"):
        items += [i.get("name") for i in data.get("data", {}).values()]
    if data := load(f, "dd_summoner.json"):
        misc += [s.get("name") for s in data.get("data", {}).values()]
    if data := load(f, "dd_runes.json"):
        for tree in data:
            misc.append(tree.get("name"))
            for slot in tree.get("slots", []):
                misc += [r.get("name") for r in slot.get("runes", [])]
    if data := load(f, "dd_map.json"):
        misc += [m.get("MapName") for m in data.get("data", {}).values()]
    return heroes + misc + items


def parse_wzry(f):
    heroes, skins, items = [], [], []
    for h in load(f, "herolist.json") or []:
        heroes += [h.get("cname"), h.get("title")]
        skins += (h.get("skin_name") or "").split("|")
    items += [i.get("item_name") for i in load(f, "item.json") or []]
    items += [s.get("summoner_name") for s in load(f, "summoner.json") or []]
    return heroes + items + skins


def parse_dota2(f):
    words = []
    if data := load(f, "herolist.json"):
        words += [h.get("name_loc") for h in data.get("result", {}).get("data", {}).get("heroes", [])]
    if data := load(f, "itemlist.json"):
        items = data.get("result", {}).get("data", {}).get("itemabilities", [])
        words += [i.get("name_loc") for i in items if not str(i.get("name", "")).startswith("item_recipe")]
    return words


def parse_genshin(f):
    data = load(f, "obc_189.json")
    if not data:
        return []
    channels = {}
    for root in data.get("data", {}).get("list", []):
        for child in root.get("children") or []:
            channels[child.get("name")] = child.get("list") or []
    words = []
    for name in OBC_WANT:
        words += [c.get("title") for c in channels.get(name, [])]
    return words


# 和平精英官网只列了当前版本的十几把枪和载具；这些是玩家常说的词（原来的占位词表），放在最前面。
HPJY_COMMON = ["吃鸡", "空投", "三级头", "三级甲", "信号圈", "决赛圈", "平底锅", "海岛地图", "雨林地图"]


def hpjy_list(f, name):
    """infocms 的数据是 {"contents": [...]}，有时直接是列表。"""
    data = load(f, name) or []
    return data.get("contents", []) if isinstance(data, dict) else data


def parse_hpjy(f):
    guns = hpjy_list(f, "guns.json")
    vehicles = hpjy_list(f, "vehicles.json")
    return (HPJY_COMMON + [g.get("name") for g in guns] + [g.get("kindName") for g in guns]
            + [v.get("name") for v in vehicles])


PARSERS = {"lol": parse_lol, "wzry": parse_wzry, "dota2": parse_dota2, "genshin": parse_genshin, "hpjy": parse_hpjy}


def parse(raw):
    today = date.today().isoformat()
    for game, parser in PARSERS.items():
        folder = raw / game
        if not folder.exists():
            print(f"  {game}: 没有原始数据，跳过")
            continue
        seen, words = set(), []
        for w in parser(folder):
            w = clean(w)
            if w and w not in seen:
                seen.add(w)
                words.append(w)
        if not words:
            print(f"  {game}: 一个词都没整理出来，保留原来的词表")
            continue
        target = OUT / f"{game}.txt"
        with target.open("w", encoding="utf-8") as out:
            out.write(f"# {NAMES[game]} · 来源：{CREDITS[game]}，{today} 由 scripts/fetch-game-words.py 整理\n")
            out.write("# 只收名字（英雄、角色、装备、技能、地图），按重要程度排，越靠前词频越高。\n")
            out.write("\n".join(words) + "\n")
        print(f"  {game}: {len(words)} 个词")


def main():
    if len(sys.argv) != 3 or sys.argv[1] not in ("fetch", "parse"):
        sys.exit(__doc__)
    raw = Path(sys.argv[2])
    if sys.argv[1] == "fetch":
        fetch(raw)
    else:
        parse(raw)


if __name__ == "__main__":
    main()
