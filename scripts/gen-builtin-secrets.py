#!/usr/bin/env python3
"""Xcode 编译前（两个 target 的 Run Script）生成 BuiltinSecrets.swift，放在 DERIVED_FILE_DIR，不进 Git。

内测包（INTERNAL_BUILD=YES）：
- Key 不进 Info.plist。从 Local.xcconfig 传进来的 INTERNAL_API_KEY / INTERNAL_ANSWER_API_KEY 用每次随机的掩码异或，
  拆成几段写成字节数组，运行时才拼回来（Shared/BuiltinAPI.swift）。strings 和 Info.plist 里都找不到。
- 证书绑定：连一次内置接口的服务器，记下证书链里中间证书和根证书（从 macOS 系统根证书里按名字找）的 SHA-256，
  运行时内置接口的请求只认这些证书（Shared/BuiltinAPI.swift 里的 PinnedSession）。
- 检查：INTERNAL_BUILD 和 PUBLIC_BUILD 不能同时是 YES；内测包必须有 Key 和证书指纹，否则停编。

开发者版、公测版：生成空的。这个脚本从不打印 Key。
"""
import base64
import hashlib
import os
import re
import secrets
import subprocess
import sys
from urllib.parse import urlparse


def fail(message):
    print(f"error: {message}", file=sys.stderr)
    sys.exit(1)


def obfuscate(text):
    """返回 (段, 掩码)：每段和同样长的随机掩码异或。"""
    data = text.encode("utf-8")
    if not data:
        return [], []
    cuts = sorted(secrets.SystemRandom().sample(range(1, len(data)), min(3, len(data) - 1))) if len(data) > 1 else []
    parts, masks, start = [], [], 0
    for end in cuts + [len(data)]:
        chunk = data[start:end]
        mask = secrets.token_bytes(len(chunk))
        parts.append(bytes(a ^ b for a, b in zip(chunk, mask)))
        masks.append(mask)
        start = end
    return parts, masks


def swift_bytes(chunks):
    return "[" + ", ".join("[" + ", ".join(str(b) for b in c) + "]" for c in chunks) + "]"


def chain_pins(host):
    """服务器发来的证书链里，除了叶子证书的每一张，再加上系统根证书里签发最后一张的根证书。"""
    try:
        out = subprocess.run(
            ["openssl", "s_client", "-connect", f"{host}:443", "-servername", host, "-showcerts"],
            input=b"", capture_output=True, timeout=30).stdout.decode("utf-8", "replace")
    except Exception as e:  # noqa: BLE001
        fail(f"连不上 {host}，取不到证书：{e}")
    pems = re.findall(r"-----BEGIN CERTIFICATE-----(.*?)-----END CERTIFICATE-----", out, re.S)
    if len(pems) < 2:
        fail(f"{host} 没有发来中间证书，没法做证书绑定")
    pins = set()
    for body in pems[1:]:
        pins.add(hashlib.sha256(base64.b64decode("".join(body.split()))).hexdigest())
    last = "-----BEGIN CERTIFICATE-----" + pems[-1] + "-----END CERTIFICATE-----\n"
    issuer = subprocess.run(["openssl", "x509", "-noout", "-issuer", "-nameopt", "multiline"],
                            input=last.encode(), capture_output=True).stdout.decode("utf-8", "replace")
    match = re.search(r"commonName\s*=\s*(.+)", issuer)
    if match:
        roots = subprocess.run(["security", "find-certificate", "-a", "-c", match.group(1).strip(), "-Z",
                                "/System/Library/Keychains/SystemRootCertificates.keychain"],
                               capture_output=True).stdout.decode("utf-8", "replace")
        for digest in re.findall(r"SHA-256 hash:\s*([0-9A-Fa-f]{64})", roots):
            pins.add(digest.lower())
    return pins


def main():
    env = os.environ
    internal = env.get("INTERNAL_BUILD", "NO") == "YES"
    public = env.get("PUBLIC_BUILD", "NO") == "YES"
    out_dir = env.get("DERIVED_FILE_DIR") or fail("没有 DERIVED_FILE_DIR，要在 Xcode 里跑")
    if internal and public:
        fail("INTERNAL_BUILD 和 PUBLIC_BUILD 不能同时是 YES：内测包带内置 Key，不能当公测包发出去")

    key = answer_key = ""
    pins = set()
    if internal:
        key = env.get("INTERNAL_API_KEY", "").strip()
        answer_key = env.get("INTERNAL_ANSWER_API_KEY", "").strip()
        if not key:
            fail("INTERNAL_BUILD=YES 但 Local.xcconfig 里没有 INTERNAL_API_KEY")
        hosts = {urlparse(env.get(name, "")).hostname for name in ("INTERNAL_BASE_URL", "INTERNAL_ANSWER_BASE_URL")}
        for host in sorted(h for h in hosts if h):
            pins |= chain_pins(host)
        if not pins:
            fail("内测包没取到任何证书指纹")

    key_parts, key_masks = obfuscate(key)
    answer_parts, answer_masks = obfuscate(answer_key)
    swift = f"""// 由 scripts/gen-builtin-secrets.py 在编译时生成，不进 Git，不要手改。
enum BuiltinSecrets {{
    static let keyParts: [[UInt8]] = {swift_bytes(key_parts)}
    static let keyMasks: [[UInt8]] = {swift_bytes(key_masks)}
    static let answerKeyParts: [[UInt8]] = {swift_bytes(answer_parts)}
    static let answerKeyMasks: [[UInt8]] = {swift_bytes(answer_masks)}
    static let pins: Set<String> = [{", ".join(f'"{p}"' for p in sorted(pins))}]
}}
"""
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, "BuiltinSecrets.swift")
    old = open(path).read() if os.path.exists(path) else None
    # 非内测包内容不变就不重写，免得每次都重编。
    if old != swift or internal:
        with open(path, "w") as f:
            f.write(swift)
    print(f"BuiltinSecrets.swift：{'内测包，' + str(len(pins)) + ' 个证书指纹' if internal else '空'}")


main()
