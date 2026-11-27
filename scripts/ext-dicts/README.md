# 扩展词库源文件

`scripts/build-ext-dicts.py` 把这里的词表和 THUOCL 词表转成 Rime 词库（带拼音），输出到 `Configs/ExtDicts/`（随 App 带的内置词库）和服务器用的在线词库目录。

- `*.txt`：飞地自整理的词包，一行一个词，`#` 开头是注释。只从官方公开资料（官网的英雄、角色列表、公告）自己整理，不照搬别人整理好的词表，不抓 fan wiki。
- 游戏词包用 `scripts/fetch-game-words.py` 从官网、官方维基的公开数据整理（先 `fetch` 下载原始数据，再 `parse` 写词表）；网络流行语还是占位，正式发布前要换成整理好的词表。
- 发布前所有词包都要过敏感词过滤：`--blocklist <词表文件>`，词表文件不进仓库。

生成：

```sh
python3 scripts/build-ext-dicts.py <万象 dicts 目录> <THUOCL data 目录> --online server/dicts --blocklist <敏感词表>
```

万象 dicts 目录是 rime_wanxiang 仓库的 `dicts/`（带声调的原版，用来标拼音）；THUOCL data 目录是 github.com/thunlp/THUOCL 的 `data/`。
`server/dicts/` 里是在线词库和清单 `catalog.json`，拷到服务器 `/var/www/enclavekb/dicts/`。百科词库加 `--baike <zhwiki-*.dict.yaml>`（github.com/felixonmars/fcitx5-pinyin-zhwiki 的 release）：跳过万象里已有的词和有生僻字的，按派生条目数和字频打分取前 20 万条，同时写出 `LICENSE-baike.txt`；`--baike-blocklist <表>` 是 05 审核加的百科补充屏蔽表（整词匹配，表不进仓库）。不给 `--baike` 就沿用上次生成的。

许可：THUOCL 是 MIT（Copyright (c) 2018 THUNLP），分发时附上 `Configs/ExtDicts/LICENSE-THUOCL.txt`。

## 景点、机场、地标、餐厅和名人（Wikidata，T106）

内置词库 `lvyou`（景点、机场、地标、城市）和在线词库 `renwu`（名人）的词条名称来自 Wikidata 的中文标签和别名，CC0 1.0。许可写法和人物筛选规则是 05 定的（项目文件 `compliance/词库-Wikidata/许可和审核要求.md`）。

1. 在 Mac 上（要能上外网）：`bash scripts/update-wikidata-dicts.sh`，结果写到仓库外的 `~/Enclave-QWERTY/wikidata/`：`lvyou.tsv`、`renwu.tsv`（词、拼音、热度），待审的 `review-politicians.tsv`、`review-convicted.tsv`，和按规则排除掉的 `excluded.tsv`。这些文件不进仓库。
2. 生成词库（不用万象、THUOCL 目录，拼音已经在 tsv 里）：

```sh
python3 scripts/build-ext-dicts.py --only lvyou,renwu --wikidata ~/Enclave-QWERTY/wikidata --online server/dicts --blocklist <敏感词表>
```

`--only` 只重新生成列出的词库，别的词库文件不动。过敏感词表删掉的词写到 `--wikidata` 目录的 `lvyou-blocked.txt`、`renwu-blocked.txt`，和待审文件一起交 05。在线目录里同时写出 `LICENSE-wikidata.txt`。

英文名（用户 11-27：「这些都需要中英文的」）：同一次抓取还写出 `en-lvyou.tsv`、`en-renwu.tsv`（英文名、热度）。
`python3 scripts/build-english-names.py ~/Enclave-QWERTY/wikidata` 把景点、机场、地标、餐厅英文名里英文词表没有的词
写进 `Keyboard/English/en_names.tsv`、`en_names_next.tsv`，随键盘打包，英文补全里能打出 Changi、下一个词联想出 Airport。
人名等 05 看完待审文件再加（`--people`）。
