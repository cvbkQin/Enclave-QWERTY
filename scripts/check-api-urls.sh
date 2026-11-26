#!/usr/bin/env bash
# 「常用 API 地址」列表（T102）里每个地址用真 Key 拉一次模型列表，看通不通。在自己 Mac 上跑。
#
#   bash scripts/check-api-urls.sh            # 每个地址问一次 Key（输入不显示，回车跳过 = 只看地址通不通）
#   bash scripts/check-api-urls.sh --no-key   # 不用 Key，只看地址通不通（401 / 403 也算通：服务器在、要 Key）
#
# Key 只在这次运行的内存里，不写文件、不打印。列表要和 App/Provider.swift 的 ConfigTemplate.endpoints 一致。
# 不用 set -u：中途出错退出的话，后面粘贴的 Key 会落到终端里当命令执行（也会进终端历史）。
# 变量一律写成 ${x}：Mac 自带的 bash 3.2 会把紧跟的中文标点当成变量名的一部分。

ENDPOINTS=(
  "DeepSeek|通用|https://api.deepseek.com/v1"
  "Kimi|非中国大陆|https://api.moonshot.ai/v1"
  "Kimi|中国大陆|https://api.moonshot.cn/v1"
  "千问（阿里云百炼）|非中国大陆|https://dashscope-intl.aliyuncs.com/compatible-mode/v1"
  "千问（阿里云百炼）|中国大陆|https://dashscope.aliyuncs.com/compatible-mode/v1"
  "千问 AI 平台|中国大陆|https://maas.qianwenaiapi.com/compatible-mode/v1"
  "智谱 GLM|非中国大陆|https://api.z.ai/api/paas/v4"
  "智谱 GLM|中国大陆|https://open.bigmodel.cn/api/paas/v4"
  "腾讯混元|中国大陆|https://tokenhub.tencentmaas.com/v1"
  "豆包（火山方舟）|非中国大陆|https://ark.ap-southeast.bytepluses.com/api/v3"
  "豆包（火山方舟）|中国大陆|https://ark.cn-beijing.volces.com/api/v3"
  "文心（百度千帆）|中国大陆|https://qianfan.baidubce.com/v2"
  "MiniMax|非中国大陆|https://api.minimax.io/v1"
  "MiniMax|中国大陆|https://api.minimax.cn/v1"
  "阶跃星辰|非中国大陆|https://api.stepfun.ai/v1"
  "阶跃星辰|中国大陆|https://api.stepfun.com/v1"
  "硅基流动|非中国大陆|https://api.siliconflow.com/v1"
  "硅基流动|中国大陆|https://api.siliconflow.cn/v1"
)

ASK=1
[ "${1:-}" = "--no-key" ] && ASK=0

body=$(mktemp)
trap 'rm -f "$body"' EXIT

printf '%-20s %-10s %-6s %s\n' "服务商" "哪一边" "结果" "说明"
for row in "${ENDPOINTS[@]}"; do
  IFS='|' read -r name side url <<<"$row"
  key=""
  if [ "$ASK" = 1 ]; then
    printf '%s（%s）%s 的 Key（回车跳过）: ' "$name" "$side" "$url" >&2
    IFS= read -rs key </dev/tty
    echo >&2
  fi
  if [ -n "$key" ]; then
    code=$(curl -s -o "$body" -w '%{http_code}' -m 20 -H "Authorization: Bearer $key" "$url/models")
  else
    code=$(curl -s -o "$body" -w '%{http_code}' -m 20 "$url/models")
  fi
  key=""
  count=$(python3 -c 'import json,sys
try:
    d=json.load(open(sys.argv[1])); items=d.get("data") or d.get("models") or []
    print(len(items))
except Exception: print("")' "$body" 2>/dev/null)
  case "$code" in
    200) result="✓"; note="通了${count:+，${count} 个模型}" ;;
    401|403)
      result="?"; note="服务器在，HTTP ${code}（没填 Key 是正常的；填了 Key 就是 Key 不对或不是这一边的 Key）" ;;
    404) result="✗"; note="HTTP 404：这个地址没有 /models，App 里拉不到模型（只能手动填模型名）" ;;
    000) result="✗"; note="连不上（超时或域名不通）" ;;
    *) result="✗"; note="HTTP ${code}：$(head -c 120 "$body" | tr '\n' ' ')" ;;
  esac
  printf '%-20s %-10s %-6s %s\n' "$name" "$side" "$result" "$note"
done
