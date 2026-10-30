#!/usr/bin/env bash
# 在腾讯云轻量服务器（Ubuntu）上一次装好 enclavekb.cn：nginx + HTTPS 证书 + 整句模型目录 + 反馈接口。
# 前提：enclavekb.cn 的网站备案已通过，DNS 已解析到这台服务器，防火墙放行 80、443。
# 用法（在仓库 server/ 目录里，用 root 运行）：sudo bash setup.sh 你的邮箱
# 可以重复运行。
set -euo pipefail
cd "$(dirname "$0")"
EMAIL="${1:?用法：sudo bash setup.sh 接收证书到期提醒的邮箱}"

apt-get update
apt-get install -y nginx certbot python3-certbot-nginx python3

# 1. 文件目录和 nginx
mkdir -p /var/www/enclavekb/grammar
cp nginx/enclavekb.cn.conf /etc/nginx/sites-available/enclavekb.cn.conf
ln -sf /etc/nginx/sites-available/enclavekb.cn.conf /etc/nginx/sites-enabled/enclavekb.cn.conf
rm -f /etc/nginx/sites-enabled/default
nginx -t && systemctl reload nginx

# 2. 访问日志保留 180 天
cat > /etc/logrotate.d/enclavekb <<'ROT'
/var/log/nginx/enclavekb.access.log {
    daily
    rotate 180
    compress
    missingok
    notifempty
    sharedscripts
    postrotate
        [ -s /run/nginx.pid ] && kill -USR1 $(cat /run/nginx.pid)
    endscript
}
ROT

# 3. HTTPS 证书（Let's Encrypt，自动续期）
certbot --nginx -n --agree-tos -m "$EMAIL" -d enclavekb.cn -d www.enclavekb.cn --redirect

# 4. 反馈接口
mkdir -p /opt/enclave
cp feedback.py /opt/enclave/feedback.py
if [ ! -f /etc/enclave-feedback.env ]; then
    cat > /etc/enclave-feedback.env <<'ENV'
# 发信邮箱（推荐 QQ 邮箱：设置 › 账户 › 开启 SMTP 服务，拿到「授权码」填到 SMTP_PASS，不是 QQ 密码）
SMTP_HOST=smtp.qq.com
SMTP_PORT=465
SMTP_USER=
SMTP_PASS=
# 反馈发到哪个邮箱（隐私政策里写的联系邮箱，已在政策里告知出境）
MAIL_TO=cvbk.qin@gmail.com
ENV
    chmod 600 /etc/enclave-feedback.env
    echo "已生成 /etc/enclave-feedback.env，填好 SMTP_USER 和 SMTP_PASS 后运行：systemctl restart enclave-feedback"
fi
chown root:www-data /etc/enclave-feedback.env && chmod 640 /etc/enclave-feedback.env
cp enclave-feedback.service /etc/systemd/system/enclave-feedback.service
systemctl daemon-reload
systemctl enable --now enclave-feedback
systemctl restart enclave-feedback

echo "完成。整句模型放到 /var/www/enclavekb/grammar/wanxiang-lts-zh-hans.gram"
