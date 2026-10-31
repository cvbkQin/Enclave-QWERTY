# 扩展词库源文件

`scripts/build-ext-dicts.py` 把这里的词表和 THUOCL 词表转成 Rime 词库（带拼音），输出到 `Configs/ExtDicts/`（随 App 带的内置词库）和服务器用的在线词库目录。

- `*.txt`：飞地自整理的词包，一行一个词，`#` 开头是注释。只从官方公开资料（官网的英雄、角色列表、公告）自己整理，不照搬别人整理好的词表，不抓 fan wiki。
- **现在的游戏词包和网络流行语只是占位**（每个十几个词），用来跑通流程，正式发布前要换成整理好的完整词表。
- 发布前所有词包都要过敏感词过滤：`--blocklist <词表文件>`，词表文件不进仓库。

生成：

```sh
python3 scripts/build-ext-dicts.py <万象 dicts 目录> <THUOCL data 目录> --online server/dicts --blocklist <敏感词表>
```

万象 dicts 目录是 rime_wanxiang 仓库的 `dicts/`（带声调的原版，用来标拼音）；THUOCL data 目录是 github.com/thunlp/THUOCL 的 `data/`。
`server/dicts/` 里是在线词库和清单 `catalog.json`，拷到服务器 `/var/www/enclavekb/dicts/`。百科词库还没生成：要先过敏感词过滤、精简到 20 万条，清单里它的 `url` 现在是 null，App 显示「准备中」。

许可：THUOCL 是 MIT（Copyright (c) 2018 THUNLP），分发时附上 `Configs/ExtDicts/LICENSE-THUOCL.txt`。
