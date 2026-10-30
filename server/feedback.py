#!/usr/bin/env python3
"""App 内反馈的接收接口（A4）：收到一条反馈就转成邮件发给开发者，不写盘、不进数据库。

只用 Python 标准库。监听 127.0.0.1，前面由 nginx 接 HTTPS 并传真实 IP（X-Real-IP）。
限流：同一 IP 每分钟 1 条、一天 20 条；全站一天 300 条（保护发信邮箱的额度）。计数只在内存里，重启清零。
配置从环境变量读（systemd 的 EnvironmentFile=/etc/enclave-feedback.env）：
  SMTP_HOST SMTP_PORT(默认 465) SMTP_USER SMTP_PASS MAIL_TO [MAIL_FROM] [LISTEN_PORT 默认 8081]
"""
import base64
import binascii
import json
import os
import re
import smtplib
import ssl
import threading
import time
from collections import defaultdict, deque
from email.message import EmailMessage
from email.utils import formataddr, make_msgid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

MAX_BODY = 6 * 1024 * 1024
MAX_IMAGES = 3
MAX_IMAGE_BYTES = 1536 * 1024
IMAGE_TYPES = {b"\xff\xd8\xff": ("jpeg", "jpg"), b"\x89PNG": ("png", "png")}
MAX_MESSAGE = 5000
MAX_CONTACT = 200
MAX_META_KEYS = 20
MAX_META_VALUE = 200
CATEGORIES = {"bug", "suggestion", "other"}

PER_IP = [(60, 1), (86400, 20)]
GLOBAL_PER_DAY = 300

EMAIL_RE = re.compile(r"^[^@\s<>]+@[^@\s<>]+\.[^@\s<>]+$")

_lock = threading.Lock()
_hits = defaultdict(deque)
_global = deque()


def allow(ip):
    """记一次请求，超限返回 False。只存时间戳，不存内容。"""
    now = time.time()
    with _lock:
        while _global and now - _global[0] > 86400:
            _global.popleft()
        q = _hits[ip]
        while q and now - q[0] > 86400:
            q.popleft()
        if len(_global) >= GLOBAL_PER_DAY:
            return False
        for window, limit in PER_IP:
            if sum(1 for t in q if now - t <= window) >= limit:
                return False
        q.append(now)
        _global.append(now)
        if len(_hits) > 50000:  # 防止被大量 IP 撑爆内存
            for k in [k for k, v in _hits.items() if not v or now - v[-1] > 86400]:
                del _hits[k]
        return True


def clean(text, limit):
    return "".join(ch for ch in str(text) if ch in "\n\t" or ch >= " ")[:limit]


def parse(body):
    """校验并整理请求，不合格抛 ValueError（返回 400）。"""
    data = json.loads(body.decode("utf-8"))
    if not isinstance(data, dict):
        raise ValueError("body must be an object")
    message = clean(data.get("message", ""), MAX_MESSAGE + 1).strip()
    if not message or len(message) > MAX_MESSAGE:
        raise ValueError("message must be 1-5000 characters")
    category = data.get("category", "other")
    if category not in CATEGORIES:
        category = "other"
    contact = clean(data.get("contact") or "", MAX_CONTACT + 1).strip()
    if len(contact) > MAX_CONTACT:
        raise ValueError("contact too long")
    meta = data.get("meta") or {}
    if not isinstance(meta, dict) or len(meta) > MAX_META_KEYS:
        raise ValueError("meta must be an object with at most 20 keys")
    meta = {clean(k, 40): clean(v, MAX_META_VALUE) for k, v in meta.items()}
    diagnostics = data.get("diagnostics")
    images = data.get("images") or []
    if not isinstance(images, list) or len(images) > MAX_IMAGES:
        raise ValueError("images must be a list of at most 3")
    decoded = []
    for item in images:
        try:
            raw = base64.b64decode(item, validate=True)
        except (binascii.Error, TypeError):
            raise ValueError("images must be base64")
        kind = next((v for k, v in IMAGE_TYPES.items() if raw.startswith(k)), None)
        if not kind or len(raw) > MAX_IMAGE_BYTES:
            raise ValueError("each image must be JPEG or PNG, at most 1.5MB")
        decoded.append((raw, kind))
    return category, message, contact, meta, diagnostics, decoded


def send_mail(category, message, contact, meta, diagnostics, images=()):
    env = os.environ
    msg = EmailMessage()
    sender = env.get("MAIL_FROM") or env["SMTP_USER"]
    msg["From"] = formataddr(("飞地输入法反馈", sender))
    msg["To"] = env["MAIL_TO"]
    version = meta.get("version", "?")
    first_line = message.splitlines()[0][:40]
    msg["Subject"] = f"[Enclave 反馈·{category}] {version} · {first_line}"
    msg["Message-ID"] = make_msgid(domain="enclavekb.cn")
    if contact and EMAIL_RE.match(contact):
        msg["Reply-To"] = contact
    lines = [message, "", "—", f"类型：{category}", f"联系方式：{contact or '（未填）'}"]
    lines += [f"{k}：{v}" for k, v in sorted(meta.items())]
    msg.set_content("\n".join(lines))
    if diagnostics:
        payload = json.dumps(diagnostics, ensure_ascii=False, indent=2).encode("utf-8")
        msg.add_attachment(payload, maintype="application", subtype="json", filename="diagnostics.json")
    for i, (raw, (subtype, ext)) in enumerate(images, 1):
        msg.add_attachment(raw, maintype="image", subtype=subtype, filename=f"screenshot-{i}.{ext}")
    port = int(env.get("SMTP_PORT", "465"))
    ctx = ssl.create_default_context()
    if port == 465:
        with smtplib.SMTP_SSL(env["SMTP_HOST"], port, context=ctx, timeout=20) as s:
            s.login(env["SMTP_USER"], env["SMTP_PASS"])
            s.send_message(msg)
    else:
        with smtplib.SMTP(env["SMTP_HOST"], port, timeout=20) as s:
            s.starttls(context=ctx)
            s.login(env["SMTP_USER"], env["SMTP_PASS"])
            s.send_message(msg)


class Handler(BaseHTTPRequestHandler):
    server_version = "enclave-feedback"
    sys_version = ""

    def reply(self, code, payload):
        body = json.dumps(payload).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/api/feedback/health":
            self.reply(200, {"ok": True})
        else:
            self.reply(404, {"ok": False, "error": "not_found"})

    def do_POST(self):
        if self.path != "/api/feedback":
            return self.reply(404, {"ok": False, "error": "not_found"})
        length = int(self.headers.get("Content-Length") or 0)
        if length <= 0 or length > MAX_BODY:
            return self.reply(413, {"ok": False, "error": "too_large"})
        body = self.rfile.read(length)
        ip = self.headers.get("X-Real-IP") or self.client_address[0]
        if not allow(ip):
            return self.reply(429, {"ok": False, "error": "rate_limited"})
        try:
            fields = parse(body)
        except (ValueError, UnicodeDecodeError) as e:
            return self.reply(400, {"ok": False, "error": "invalid", "detail": str(e)[:100]})
        try:
            send_mail(*fields)
        except Exception as e:  # 发信失败：App 提示稍后再试或改用邮件
            self.log_error("mail failed: %s", type(e).__name__)
            return self.reply(502, {"ok": False, "error": "mail_failed"})
        self.reply(200, {"ok": True})

    def log_message(self, fmt, *args):
        # 不记请求日志（访问日志由 nginx 统一记，不含正文）；只记错误类型。
        pass

    def log_error(self, fmt, *args):
        print("error: " + (fmt % args), flush=True)


if __name__ == "__main__":
    port = int(os.environ.get("LISTEN_PORT", "8081"))
    ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()
