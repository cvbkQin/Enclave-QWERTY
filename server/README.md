# enclavekb.cn 服务器

腾讯云上海轻量服务器（Ubuntu）上跑这些，都在 nginx 后面：

- `/`：首页（`www/index.html`），网站名「飞地输入法」和底部 ICP 备案号。拿到公安备案号后也加在页脚。
- `/grammar/`：整句模型 `wanxiang-lts-zh-hans.gram` 的静态下载，支持 HTTPS 和 Range（断点续传）。中国大陆店面的默认下载地址。
- `/dicts/`：在线扩展词库（B6）的清单 `catalog.json` 和词库文件，原样是仓库里的 `server/dicts/`（由 `scripts/build-ext-dicts.py --online server/dicts` 生成），连同 THUOCL 的许可原文 `LICENSE-THUOCL.txt`。
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

整句模型放到 `/var/www/enclavekb/grammar/wanxiang-lts-zh-hans.gram`。在线词库：`sudo mkdir -p /var/www/enclavekb/dicts && sudo cp dicts/* /var/www/enclavekb/dicts/`（更新词库后重新拷一次）。

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
