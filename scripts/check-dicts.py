#!/usr/bin/env python3
"""发布前检查 server/dicts（第 99 条，05 合规条件 5）：不通过就不上传（server/publish-dicts.sh 先跑它）。

开了自动更新以后，服务器上换掉的词库会在 7 天内自动推到所有用户手机上（包括内置的游戏、流行语），
所以每次发布前都要再过一遍敏感词表，不能只靠生成时过滤。

用法：
  python3 scripts/check-dicts.py server/dicts --blocklist <敏感词表.txt> [--baike-blocklist <百科补充屏蔽表>]

检查：
1. 目录里每个 *.dict.yaml（含 builtin/）的每个词都不在敏感词表里（整词匹配，05 的规则）；
   百科词库 ext_baike 另外按包含匹配（和 build-ext-dicts.py 一样），还要过百科补充屏蔽表。
2. catalog.json 是 schema 2，列出的文件都在，大小、sha256 对得上，url 的 ?v= 是 sha256 前 8 位。
有问题打印出来，退出码 1。
"""
import hashlib
import json
import re
import sys
from pathlib import Path


def read_list(path):
    return {l.strip() for l in Path(path).read_text(encoding="utf-8").splitlines()
            if l.strip() and not l.strip().startswith("#")}


def words(path):
    body = False
    for line in path.read_text(encoding="utf-8").splitlines():
        if not body:
            body = line == "..."
            continue
        if line and not line.startswith("#"):
            yield line.split("\t")[0]


def main():
    args = sys.argv[1:]

    def option(name):
        if name in args:
            i = args.index(name)
            value = args[i + 1]
            del args[i:i + 2]
            return value
        return None

    block_path = option("--blocklist")
    baike_path = option("--baike-blocklist")
    if not args or not block_path:
        sys.exit("用法：check-dicts.py <词库目录> --blocklist <敏感词表> [--baike-blocklist <百科补充屏蔽表>]")
    folder = Path(args[0])
    blocklist = read_list(block_path)
    baike_block = read_list(baike_path) if baike_path else set()
    contains = re.compile("|".join(sorted(map(re.escape, (b for b in blocklist if len(b) >= 2)), key=len, reverse=True))) \
        if blocklist else None
    problems = []

    files = sorted(folder.rglob("*.dict.yaml"))
    for path in files:
        baike = path.name == "ext_baike.dict.yaml"
        hits = [w for w in words(path)
                if w in blocklist or (baike and (w in baike_block or (contains and contains.search(w))))]
        if hits:
            problems.append(f"{path.relative_to(folder)}：敏感词 {len(hits)} 个：{'、'.join(hits[:20])}{'…' if len(hits) > 20 else ''}")
        print(f"  {path.relative_to(folder)}：{'有敏感词' if hits else '通过'}")

    try:
        catalog = json.loads((folder / "catalog.json").read_text(encoding="utf-8"))
    except (OSError, ValueError) as error:
        problems.append(f"catalog.json 读不了：{error}")
        catalog = {}
    if catalog and catalog.get("schema") != 2:
        problems.append("catalog.json 不是 schema 2（用 build-ext-dicts.py 重新生成）")
    for entry in catalog.get("dicts", []) + catalog.get("builtinUpdates", []):
        url = entry.get("url")
        if not url:
            continue
        name, _, query = url.partition("?")
        path = folder / name
        if not path.exists():
            problems.append(f"{entry['id']}：清单里的 {name} 不在目录里")
            continue
        sha = hashlib.sha256(path.read_bytes()).hexdigest()
        if entry.get("sha256") != sha:
            problems.append(f"{entry['id']}：sha256 对不上（清单 {entry.get('sha256')}，文件 {sha}）")
        if entry.get("size") != path.stat().st_size:
            problems.append(f"{entry['id']}：大小对不上")
        if query != f"v={sha[:8]}":
            problems.append(f"{entry['id']}：url 应该带 ?v={sha[:8]}")

    if problems:
        print("\n不通过，不要上传：")
        for p in problems:
            print("  - " + p)
        return 1
    print(f"\n通过：{len(files)} 个词库文件，清单 {catalog.get('updated')}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
