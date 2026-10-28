#!/usr/bin/env python3
"""从 App/Legal/PrivacyPolicy.swift 生成 docs/privacy.html 和 PRIVACY.md。

App 里的三语全文是唯一来源；改了政策后运行：python3 scripts/gen-privacy.py
加 --check 只检查生成结果和仓库里的是否一致（不一致时退出码 1）。
"""
import html
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SWIFT = ROOT / "App/Legal/PrivacyPolicy.swift"
CONSENT = ROOT / "Shared/PrivacyConsent.swift"
HTML_OUT = ROOT / "docs/privacy.html"
MD_OUT = ROOT / "PRIVACY.md"

LANGS = [
    # 代码里的名字, 页面锚点, html lang, 标题, 生效日期格式, 版本格式, 切换按钮
    ("zh", "zh", "zh-Hans", "飞地输入法隐私政策", "生效日期：{y} 年 {m} 月 {d} 日", "版本：{v}", "中文"),
    ("en", "en", "en", "Enclave Privacy Policy", "Effective date: {month} {d}, {y}", "Version {v}", "English"),
    ("ja", "ja", "ja", "Enclave プライバシーポリシー", "施行日：{y} 年 {m} 月 {d} 日", "バージョン：{v}", "日本語"),
]
MONTHS = ["January", "February", "March", "April", "May", "June", "July",
          "August", "September", "October", "November", "December"]


def read_source():
    src = SWIFT.read_text(encoding="utf-8")
    texts = {}
    for key, *_ in LANGS:
        m = re.search(r'private static let %s = """\n(.*?)\n"""' % key, src, re.S)
        if not m:
            sys.exit(f"找不到 PrivacyPolicy.{key}")
        texts[key] = m.group(1)

    def legal(name):
        m = re.search(r'static let %s = "([^"]*)"' % name, src)
        if not m:
            sys.exit(f"找不到 LegalInfo.{name}")
        return m.group(1)

    m = re.search(r"effectiveDate = DateComponents\(calendar: \.current, year: (\d+), month: (\d+), day: (\d+)\)", src)
    if not m:
        sys.exit("找不到 PrivacyPolicy.effectiveDate")
    date = tuple(int(x) for x in m.groups())
    m = re.search(r"static let currentVersion = (\d+)", CONSENT.read_text(encoding="utf-8"))
    version = int(m.group(1)) if m else None
    return texts, legal("developer"), legal("developerZh"), legal("email"), date, version


def fill(text, lang, developer, developer_zh, email):
    return text.replace("{developer}", developer_zh if lang == "zh" else developer).replace("{email}", email)


def meta_line(fmt_date, fmt_version, date, version):
    y, m, d = date
    parts = [fmt_date.format(y=y, m=m, d=d, month=MONTHS[m - 1])]
    if version:
        parts.append(fmt_version.format(v=version))
    return parts


def inline(s, email):
    s = html.escape(s, quote=False)
    s = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", s)
    s = s.replace(email, f'<a href="mailto:{email}">{email}</a>')
    return s


def to_html(md, email):
    out, para, items, kind = [], [], [], None

    def flush():
        nonlocal para, items, kind
        if para:
            out.append("<p>" + "<br>".join(inline(l, email) for l in para) + "</p>")
            para = []
        if items:
            out.append(f"<{kind}>")
            out.extend(f"<li>{inline(i, email)}</li>" for i in items)
            out.append(f"</{kind}>")
            items, kind = [], None

    for line in md.split("\n"):
        line = line.rstrip()
        if not line:
            flush()
        elif line.startswith("### "):
            flush(); out.append(f"<h3>{inline(line[4:], email)}</h3>")
        elif line.startswith("## "):
            flush(); out.append(f"<h2>{inline(line[3:], email)}</h2>")
        elif re.match(r"\d+\. ", line) or line.startswith("- "):
            new = "ol" if line[0].isdigit() else "ul"
            if para or (kind and kind != new):
                flush()
            kind = new
            items.append(re.sub(r"^(\d+\.|-) ", "", line))
        else:
            if items:
                flush()
            para.append(line)
    flush()
    return "\n".join(out)


def build():
    texts, developer, developer_zh, email, date, version = read_source()
    old = HTML_OUT.read_text(encoding="utf-8")
    head = old.split("<body>", 1)[0]
    head = re.sub(r"<title>.*?</title>", "<title>Enclave Privacy Policy · 飞地输入法隐私政策</title>", head)
    nav = "".join(f'<a href="#{a}">{label}</a>' for _, a, _, _, _, _, label in LANGS)
    page = [head + "<body><div class=\"wrap\">",
            "<!-- 由 scripts/gen-privacy.py 从 App/Legal/PrivacyPolicy.swift 生成，不要手改。 -->",
            f'<header><a class="brand" href="index.html">Enclave keyboard</a>\n<nav class="lang">{nav}</nav></header>']
    md = ["<!-- 由 scripts/gen-privacy.py 从 App/Legal/PrivacyPolicy.swift 生成，不要手改。 -->", ""]
    for key, anchor, lang_attr, title, fd, fv, _ in LANGS:
        body = fill(texts[key], key, developer, developer_zh, email)
        meta = meta_line(fd, fv, date, version)
        page.append(f'<section class="lang" id="{anchor}" lang="{lang_attr}"><h1>{title}</h1>'
                    f'<p class="meta">{" · ".join(meta)}</p>')
        page.append(to_html(body, email))
        page.append("</section>\n")
        md += [f"# {title}", "", "  \n".join(meta), "", body, "", "---", ""]
    page.append(f'<footer>© {date[0]} {developer} · <a href="index.html">Support</a> · '
                f'<a href="privacy.html">Privacy Policy</a> · <a href="mailto:{email}">{email}</a></footer>')
    page.append("</div></body></html>\n")
    return "\n".join(page), "\n".join(md[:-2]).rstrip() + "\n"


def main():
    page, md = build()
    if "--check" in sys.argv:
        stale = [p.name for p, s in ((HTML_OUT, page), (MD_OUT, md)) if p.read_text(encoding="utf-8") != s]
        if stale:
            sys.exit("隐私政策网页和 App 内文字不一致，请运行 python3 scripts/gen-privacy.py：" + "、".join(stale))
        print("隐私政策网页和 App 内文字一致")
        return
    HTML_OUT.write_text(page, encoding="utf-8")
    MD_OUT.write_text(md, encoding="utf-8")
    print(f"已生成 {HTML_OUT.relative_to(ROOT)}、{MD_OUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
