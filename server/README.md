# enclavekb.cn 服务器

腾讯云上海轻量服务器（Ubuntu）上跑这些，都在 nginx 后面：

- `/`：首页（`www/index.html`），网站名「飞地输入法」和底部 ICP 备案号。拿到公安备案号后也加在页脚。
- `/grammar/`：整句模型 `wanxiang-lts-zh-hans.gram` 的静态下载，支持 HTTPS 和 Range（断点续传）。中国大陆店面的默认下载地址。
- `/dicts/`：在线扩展词库（B6）的清单 `catalog.json`（也是自动更新的版本清单，含整句模型的版本和两条线路的地址）、词库文件和内置词库的服务器版（`builtin/`），原样是仓库里的 `server/dicts/`（由 `scripts/build-ext-dicts.py --online server/dicts` 生成，`server/publish-dicts.sh` 发布），连同 THUOCL 的许可原文 `LICENSE-THUOCL.txt` 和百科词库的许可说明 `LICENSE-baike.txt`（CC BY-SA 4.0）。
- `/api/feedback`：App 内反馈的接收接口（`feedback.py`，只用 Python 标准库），可带最多 3 张截图。收到后转成邮件发出，不写盘；同一 IP 每分钟 1 条、每天 20 条，全站每天 300 条。

请求格式、返回码和合规说明见项目文件 `compliance/A3-A4-服务器与反馈合规.md`。

## 安装

前提：enclavekb.cn 网站备案已通过、DNS 指到这台服务器、防火墙放行 80 和 443。

```sh
git clone https://github.com/cvbkQin/Enclave-QWERTY.git && cd Enclave-QWERTY/server
sudo bash setup.sh 你的邮箱          # 装 nginx、证书、反馈服务
sudo nano /etc/enclave-feedback.env  # 填发信邮箱和授权码
sudo systemctl restart enclave-feedback
```

整句模型放到 `/var/www/enclavekb/grammar/wanxiang-lts-zh-hans.gram`。在线词库第一次：`sudo mkdir -p /var/www/enclavekb/dicts && sudo cp -r dicts/* /var/www/enclavekb/dicts/`；以后用下面的发布脚本。

## 发布新词库（第 99 条）

App 的「自动更新词库」默认开：服务器上的 `dicts/catalog.json` 就是版本清单，App 约 7 天拉一次，按 sha256 判断哪些词库变了，变了的（下载过的和内置的）自动下载替换。所以**服务器上换了词库，7 天内会推到所有用户手机上**，发布前一定要过敏感词表。

在 Mac 上跑（不在服务器上跑），一条命令做完生成、检查、上传、核对：

```sh
bash server/publish-dicts.sh ubuntu@enclavekb.cn \
  --blocklist <项目文件 compliance/blocklist/敏感词表.txt> \
  --wanxiang <万象 dicts 目录> --thuocl <THUOCL data 目录> \
  [--baike <zhwiki-*.dict.yaml> --baike-blocklist <百科补充屏蔽表>] \
  [--grammar <wanxiang-lts-zh-hans.gram>]       # 同时更新整句模型（只提示，App 不自动下）
# 先看一遍不上传：加 --dry-run
```

1. `scripts/build-ext-dicts.py` 重新生成。内容没变的词库**版本号和文件都不变**（不会误报「有更新」）；变了的写当天日期，同一天第二次写「2026-11-26.2」。清单里的地址带 `?v=sha256 前 8 位`。内置词库（游戏、流行语、成语等）的服务器版放在 `dicts/builtin/`，清单里在 `builtinUpdates`（不放 `dicts`，老版本 App 会当成可下载的词库）。
2. `scripts/check-dicts.py` 过敏感词表（整词匹配；百科词库另按包含匹配），核对清单里每个文件的大小、sha256。**不通过就停，不上传。**
3. 先传词库文件，最后传 `catalog.json`（先写临时文件再改名），App 任何时候拉到的清单指向的文件都已经在了。
4. 拉线上的 `catalog.json`，核对 `updated` 是刚才生成的时间。

只改了清单（比如整句模型换版本）不重新生成词库：不给 `--wanxiang` / `--thuocl`，脚本只重写清单。

nginx 里 `catalog.json` 是 `Cache-Control: no-cache`（自带 ETag，没变时只回 304），带 `?v=` 的词库文件缓存一天。改 nginx 配置后：`sudo cp nginx/enclavekb.cn.conf /etc/nginx/sites-available/enclavekb.cn && sudo nginx -t && sudo systemctl reload nginx`（certbot 加的证书段要保留，先比一下再拷）。

## 检查

```sh
curl -sI https://enclavekb.cn/grammar/wanxiang-lts-zh-hans.gram          # 200，有 Accept-Ranges: bytes
curl -s -r 0-99 -o /dev/null -w '%{http_code}\n' https://enclavekb.cn/grammar/wanxiang-lts-zh-hans.gram   # 206
curl -s https://enclavekb.cn/api/feedback/health                         # {"ok": true}
curl -s -X POST https://enclavekb.cn/api/feedback -H 'Content-Type: application/json' \
  -d '{"category":"other","message":"服务器测试","meta":{"version":"test"}}'   # {"ok": true}，邮箱收到一封
```

## 日志

nginx 访问日志 `/var/log/nginx/enclavekb.access.log` 只记 IP、时间、地址、状态、大小、UA，不记正文，保留 180 天（网络安全法要求不少于六个月）。反馈服务只记发信失败的错误类型：`journalctl -u enclave-feedback`。
