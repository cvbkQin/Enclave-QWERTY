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
`server/dicts/` 里是在线词库和清单 `catalog.json`，拷到服务器 `/var/www/enclavekb/dicts/`。百科词库加 `--baike <zhwiki-*.dict.yaml>`（github.com/felixonmars/fcitx5-pinyin-zhwiki 的 release）：跳过万象里已有的词和有生僻字的，按字频和长度打分取前 20 万条；不给就沿用上次生成的。

许可：THUOCL 是 MIT（Copyright (c) 2018 THUNLP），分发时附上 `Configs/ExtDicts/LICENSE-THUOCL.txt`。
