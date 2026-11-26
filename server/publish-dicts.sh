#!/usr/bin/env bash
# 发布热门词库（第 99 条，specs/整句模型下载与热门词库自动更新-方案.md 三之 2）。在 Mac 上跑，不在服务器上跑。
#
#   bash server/publish-dicts.sh <ssh 主机> --blocklist <敏感词表.txt> [选项]
#
# 选项：
#   --wanxiang <万象 dicts 目录> --thuocl <THUOCL data 目录>   先重新生成词库（不给就用 server/dicts 里现有的，只重写清单）
#   --baike <zhwiki-*.dict.yaml> [--baike-blocklist <百科补充屏蔽表>]   重新生成百科词库
#   --grammar <wanxiang-lts-zh-hans.gram>   同时把整句模型传到 /grammar/，清单里的大小和 sha256 按它重算
#   --dry-run   只生成和检查，不上传
#
# 步骤：
#   1. 生成词库和 catalog.json（scripts/build-ext-dicts.py；内容没变的词库版本号不变）。
#   2. 过敏感词表、核对清单（scripts/check-dicts.py）。不通过就停，不上传（05 合规条件 5：开了自动更新，
#      服务器上的词库 7 天内会自动推到所有用户手机上）。
#   3. 先传词库文件，最后传 catalog.json：清单先放临时文件再改名覆盖，App 任何时候拉到的清单指向的文件都已经在了。
#   4. 拉一次线上的 catalog.json，核对 updated 是不是刚才生成的。
#
# 服务器上要能 sudo（文件放在 /var/www/enclavekb/ 下，属主 root）。请求里不带任何设备、用户编号（App 那边）。
set -euo pipefail

cd "$(dirname "$0")/.."
DIR=server/dicts
REMOTE_ROOT=/var/www/enclavekb
STAGING=enclave-dicts-staging

host="" blocklist="" baike_blocklist="" wanxiang="" thuocl="" baike="" grammar="" dry_run=0
while [ $# -gt 0 ]; do
  case "$1" in
    --blocklist) blocklist=$2; shift 2 ;;
    --baike-blocklist) baike_blocklist=$2; shift 2 ;;
    --wanxiang) wanxiang=$2; shift 2 ;;
    --thuocl) thuocl=$2; shift 2 ;;
    --baike) baike=$2; shift 2 ;;
    --grammar) grammar=$2; shift 2 ;;
    --dry-run) dry_run=1; shift ;;
    -*) echo "不认识的选项：$1" >&2; exit 2 ;;
    *) host=$1; shift ;;
  esac
done

if [ -z "$blocklist" ] || [ ! -f "$blocklist" ]; then
  echo "要给 --blocklist（项目文件 compliance/blocklist/敏感词表.txt）。没过敏感词表不能发布。" >&2
  exit 2
fi
if [ -z "$host" ] && [ "$dry_run" = 0 ]; then
  echo "要给 ssh 主机（比如 ubuntu@enclavekb.cn），或者加 --dry-run 只检查。" >&2
  exit 2
fi

echo "== 1. 生成词库和清单"
build_args=(--online "$DIR" --blocklist "$blocklist")
[ -n "$baike" ] && build_args+=(--baike "$baike")
[ -n "$baike_blocklist" ] && build_args+=(--baike-blocklist "$baike_blocklist")
[ -n "$grammar" ] && build_args+=(--grammar "$grammar")
if [ -n "$wanxiang" ] && [ -n "$thuocl" ]; then
  python3 scripts/build-ext-dicts.py "$wanxiang" "$thuocl" "${build_args[@]}"
else
  echo "没给 --wanxiang / --thuocl：用 $DIR 里现有的词库，只重写清单。"
  python3 scripts/build-ext-dicts.py --catalog-only "${build_args[@]}"
fi

echo "== 2. 过敏感词表、核对清单"
check_args=("$DIR" --blocklist "$blocklist")
[ -n "$baike_blocklist" ] && check_args+=(--baike-blocklist "$baike_blocklist")
if ! python3 scripts/check-dicts.py "${check_args[@]}"; then
  echo "检查没通过，没有上传。" >&2
  exit 1
fi

updated=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["updated"])' "$DIR/catalog.json")
if [ "$dry_run" = 1 ]; then
  echo "--dry-run：检查通过，没有上传（清单 $updated）。"
  exit 0
fi

echo "== 3. 上传：先词库文件，最后清单"
ssh "$host" "mkdir -p ~/$STAGING"
rsync -av --delete --exclude catalog.json "$DIR/" "$host:$STAGING/"
scp "$DIR/catalog.json" "$host:$STAGING/catalog.json.new"
ssh "$host" "set -e
  sudo mkdir -p $REMOTE_ROOT/dicts/builtin
  cd ~/$STAGING
  for f in \$(find . -type f ! -name 'catalog.json.new'); do sudo install -m 644 \"\$f\" \"$REMOTE_ROOT/dicts/\$f\"; done
  sudo install -m 644 catalog.json.new $REMOTE_ROOT/dicts/.catalog.json.tmp
  sudo mv -f $REMOTE_ROOT/dicts/.catalog.json.tmp $REMOTE_ROOT/dicts/catalog.json"
if [ -n "$grammar" ]; then
  echo "== 整句模型"
  scp "$grammar" "$host:$STAGING/model.gram.new"
  ssh "$host" "set -e
    sudo install -m 644 ~/$STAGING/model.gram.new $REMOTE_ROOT/grammar/.wanxiang-lts-zh-hans.gram.tmp
    sudo mv -f $REMOTE_ROOT/grammar/.wanxiang-lts-zh-hans.gram.tmp $REMOTE_ROOT/grammar/wanxiang-lts-zh-hans.gram
    rm -f ~/$STAGING/model.gram.new"
fi

echo "== 4. 核对线上清单"
online=$(curl -fsS -H 'Cache-Control: no-cache' https://enclavekb.cn/dicts/catalog.json \
  | python3 -c 'import json,sys; print(json.load(sys.stdin).get("updated"))')
if [ "$online" = "$updated" ]; then
  echo "发布好了：线上清单 updated = $online"
else
  echo "线上清单的 updated 是 $online，本地是 $updated，对不上。看一下 nginx 缓存和上传。" >&2
  exit 1
fi
