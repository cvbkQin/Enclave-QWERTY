#!/usr/bin/env python3
"""分支看板：每条分支在不在主干、合进了哪个版本、还有什么没装。

只读，不改任何分支、tag 或文件。04 每轮装机前跑一次：

    python3 scripts/branch-board.py --fetch > board.md
    python3 scripts/branch-board.py --fetch --prs prs.json   # 可选：附上 PR 列表

版本以 04 打的 tag 为准：
    dev/0.96_N   开发版装机（打在装机的那个提交上）
    v0.96        合进 main 的正式版本号
    tf/0.96.0    TestFlight 内测 / tf/0.96.1 公测
没有 tag 的老版本，退回去读提交说明「开发版 0.9x_N（…）」或「0.96：合并…」，
在看板上标「据提交说明」，以 04 的版本总览为准。

--prs 是一个 JSON 列表，每项至少有 number、title、head（分支名）、base、state，
可以用 `gh pr list --state all --json number,title,headRefName,baseRefName,state`
导出（headRefName/baseRefName 也认）。不给时只从提交说明里的 (#NN) 认 PR。
只依赖 Python 3.9+ 标准库和 git。
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import re
import subprocess
import sys
from dataclasses import dataclass, field

DEV_SUBJECT = re.compile(r"^开发版\s*(\d+\.\d+_\d+)")
REL_SUBJECT = re.compile(r"^(?:Enclave\s+|版本\s*)?(\d+\.\d+)[：:]\s*")
TAG_DEV = re.compile(r"^dev/(\d+\.\d+_\d+)$")
TAG_REL = re.compile(r"^v(\d+\.\d+)$")
TAG_TF = re.compile(r"^tf/(\d+\.\d+)\.(\d+)$")
PR_REF = re.compile(r"\(#(\d+)\)")
IDLE_DAYS = 7


def git(*args: str, check: bool = True) -> str:
    r = subprocess.run(["git", *args], capture_output=True, text=True)
    if check and r.returncode != 0:
        raise SystemExit(f"git {' '.join(args)} 失败：{r.stderr.strip()}")
    return r.stdout.strip()


def is_ancestor(a: str, b: str) -> bool:
    return subprocess.run(["git", "merge-base", "--is-ancestor", a, b]).returncode == 0


def version_key(v: str) -> tuple:
    """0.95_24 < 0.96 < 0.96.0(tf) < 0.96_1 ..."""
    m = re.match(r"(\d+)\.(\d+)(?:_(\d+))?(?:\.(\d+))?$", v)
    if not m:
        return (999, 999, 999, 0)
    a, b, n, tf = m.groups()
    if n is not None:
        return (int(a), int(b), 1, int(n))
    if tf is not None:
        return (int(a), int(b), 0, 1)
    return (int(a), int(b), 0, 0)


@dataclass
class Marker:
    version: str          # 0.96_17 / 0.96 / 0.96.0
    kind: str             # dev / release / testflight
    sha: str
    source: str           # tag / 提交说明
    date: str = ""

    @property
    def label(self) -> str:
        name = {"dev": "开发版 ", "release": "正式版 ", "testflight": "TestFlight "}[self.kind]
        return name + self.version + ("" if self.source == "tag" else "（据提交说明）")


@dataclass
class Branch:
    name: str
    sha: str
    last: str
    idle: int
    unmerged: list = field(default_factory=list)  # [(sha, date, subject)]
    behind: int = 0
    first_version: Marker | None = None
    missing_after_latest: list = field(default_factory=list)
    prs: list = field(default_factory=list)
    in_branches: list = field(default_factory=list)


def collect_markers(refs: list[str]) -> list[Marker]:
    markers: dict[tuple, Marker] = {}
    for line in git("for-each-ref", "--format=%(refname:short) %(*objectname) %(objectname)", "refs/tags").splitlines():
        parts = line.split()
        if not parts:
            continue
        name, sha = parts[0], parts[-1] if len(parts) == 2 else parts[1]
        sha = git("rev-parse", f"{name}^{{commit}}")
        for rx, kind in ((TAG_DEV, "dev"), (TAG_REL, "release")):
            m = rx.match(name)
            if m:
                markers[(kind, m.group(1))] = Marker(m.group(1), kind, sha, "tag")
        m = TAG_TF.match(name)
        if m:
            v = f"{m.group(1)}.{m.group(2)}"
            markers[("testflight", v)] = Marker(v, "testflight", sha, "tag")
    # 没打 tag 的版本：读提交说明。同一版本号有多条时取最新那条。
    log = git("log", "--format=%H%x09%ad%x09%s", "--date=short", *refs)
    for line in log.splitlines():
        sha, date, subj = line.split("\t", 2)
        m = DEV_SUBJECT.match(subj)
        kind = "dev"
        if not m:
            m = REL_SUBJECT.match(subj)
            kind = "release"
            if m and "合并" not in subj and "merge" not in subj.lower():
                m = None
        if not m:
            continue
        key = (kind, m.group(1))
        if key in markers:
            continue  # tag 或更新的一条已经记了（log 从新到旧）
        markers[key] = Marker(m.group(1), kind, sha, "提交说明", date)
    out = sorted(markers.values(), key=lambda mk: version_key(mk.version))
    for mk in out:
        if not mk.date:
            mk.date = git("log", "-1", "--format=%ad", "--date=short", mk.sha)
    return out


def contained_in(sha: str, marker: Marker) -> bool:
    return is_ancestor(sha, marker.sha)


def patch_missing(marker_sha: str, branch: str) -> list[str]:
    """branch 上有、marker 里既不是祖先也没有等价补丁的提交。"""
    out = git("cherry", marker_sha, branch, check=False)
    return [l[2:] for l in out.splitlines() if l.startswith("+ ")]


def load_prs(path: str | None) -> list[dict]:
    if not path:
        return []
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    prs = []
    for p in data:
        head = p.get("head") or p.get("headRefName")
        base = p.get("base") or p.get("baseRefName")
        if isinstance(head, dict):
            head = head.get("ref")
        if isinstance(base, dict):
            base = base.get("ref")
        state = str(p.get("state", "")).lower()
        if p.get("merged") or p.get("merged_at") or state == "merged":
            state = "merged"
        prs.append({"number": p["number"], "title": p.get("title", ""), "head": head,
                    "base": base, "state": state, "draft": p.get("draft") or p.get("isDraft")})
    return prs


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--fetch", action="store_true", help="先 git fetch --prune --tags（只更新云端记录）")
    ap.add_argument("--remote", default="origin")
    ap.add_argument("--base", default="main")
    ap.add_argument("--prs", help="PR 列表 JSON（可选）")
    ap.add_argument("--pr-limit", type=int, default=25, help="「PR 合进了哪个版本」列最近几个 PR")
    ap.add_argument("--versions", type=int, default=6, help="「每个版本合进了什么」列最近几个版本")
    args = ap.parse_args()

    if args.fetch:
        git("fetch", "--prune", "--tags", args.remote)
        git("fetch", args.remote, "+refs/pull/*/head:refs/pull/*", check=False)
    base = f"{args.remote}/{args.base}"
    today = dt.date.today()
    refs = [r for r in git("for-each-ref", "--format=%(refname:short)", f"refs/remotes/{args.remote}").splitlines()
            if r not in (args.remote, f"{args.remote}/HEAD")]
    prs = load_prs(args.prs)
    markers = collect_markers(refs)
    dev_markers = [m for m in markers if m.kind == "dev"]
    latest_dev = dev_markers[-1] if dev_markers else None

    branches: list[Branch] = []
    for ref in refs:
        if ref == base:
            continue
        name = ref[len(args.remote) + 1:]
        sha = git("rev-parse", ref)
        last = git("log", "-1", "--format=%ad", "--date=short", ref)
        idle = (today - dt.date.fromisoformat(last)).days
        b = Branch(name, sha, last, idle)
        for l in git("cherry", "-v", base, ref).splitlines():
            if l.startswith("+ "):
                s, subj = l[2:].split(" ", 1)
                b.unmerged.append((s, git("log", "-1", "--format=%ad", "--date=short", s), subj))
        b.behind = int(git("rev-list", "--count", f"{ref}..{base}"))
        b.prs = [p for p in prs if p["head"] == name]
        if b.unmerged:
            for mk in markers:
                if not patch_missing(mk.sha, ref):
                    b.first_version = mk
                    break
            if latest_dev and not b.first_version:
                b.missing_after_latest = patch_missing(latest_dev.sha, ref)
        branches.append(b)

    # 同一批提交被别的分支整个包含（比如 01 的分支已并进 03 的分支）
    for b in branches:
        if not b.unmerged or b.first_version:
            continue
        for o in branches:
            if o is not b and o.unmerged and is_ancestor(b.sha, o.sha) and o.sha != b.sha:
                b.in_branches.append(o.name)
            elif o is not b and o.sha == b.sha and o.name < b.name:
                b.in_branches.append(o.name + "（同一个提交）")

    w = print
    w(f"# 分支看板 · {today.isoformat()}")
    w()
    w(f"主干：`{base}` 最新 `{git('log', '-1', '--format=%h %ad %s', '--date=short', base)}`")
    if latest_dev:
        w(f"最新开发版：{latest_dev.label}（`{latest_dev.sha[:7]}`，{latest_dev.date}）")
    rel = [m for m in markers if m.kind == "release"]
    if rel:
        w(f"最新正式版：{rel[-1].label}（`{rel[-1].sha[:7]}`，{rel[-1].date}）")
    if not any(m.source == "tag" for m in markers):
        w()
        w("> 还没有版本 tag，版本是从「开发版 0.9x_N」提交推断的，以 04 的版本总览为准。"
          "装机的提交可能比那条版本提交晚（例如之后又并进的 PR），这时会被误标「未装」；04 补打 tag 后就准了。")
    w()

    merged = [b for b in branches if not b.unmerged]
    shipped = [b for b in branches if b.unmerged and b.first_version]
    pending = [b for b in branches if b.unmerged and not b.first_version]

    def pr_text(b: Branch) -> str:
        if not b.prs:
            nums = sorted({n for _, _, s in b.unmerged for n in PR_REF.findall(s)})
            return "；提交里提到 " + "、".join(f"#{n}" for n in nums) if nums else ""
        return "；" + "、".join(
            f"PR #{p['number']}（{p['state']}{'，草稿' if p['draft'] else ''}，→ {p['base']}）" for p in b.prs)

    w("## 还没进任何版本（未装）")
    w()
    if not pending:
        w("没有。")
    for b in sorted(pending, key=lambda x: x.idle):
        status = "很久没动" if b.idle >= IDLE_DAYS else "进行中"
        w(f"### `{b.name}` · {status}，{b.idle} 天前最后提交{pr_text(b)}")
        if b.in_branches:
            w(f"- 已被 {', '.join('`'+x+'`' for x in b.in_branches)} 包含，跟着那条走")
        w(f"- 不在主干的提交 {len(b.unmerged)} 个，主干领先它 {b.behind} 个")
        miss = set(b.missing_after_latest)
        todo = [u for u in b.unmerged if not latest_dev or u[0] in miss] if latest_dev else b.unmerged
        if latest_dev and len(todo) < len(b.unmerged):
            w(f"- 其中 {len(b.unmerged) - len(todo)} 个已在 {latest_dev.label} 里；还没装的：")
        for s, d, subj in todo[:8]:
            w(f"  - `{s[:7]}` {d} {subj[:100]}")
        if len(todo) > 8:
            w(f"  - ……另 {len(todo) - 8} 个")
        w()

    w("## 已装进开发版、还没进主干")
    w()
    if not shipped:
        w("没有。")
    for b in sorted(shipped, key=lambda x: version_key(x.first_version.version)):
        w(f"- `{b.name}`：全部改动最早进了 **{b.first_version.label}**，"
          f"{len(b.unmerged)} 个提交待随下次正式版进 main{pr_text(b)}")
    w()

    w(f"## 已进主干（{len(merged)} 条，可清理候选）")
    w()
    w(", ".join(f"`{b.name}`" for b in merged) or "没有。")
    w()

    w("## PR 合进了哪个版本")
    w()
    pr_rows = prs or [{"number": int(r.split("/")[-1]), "title": git("log", "-1", "--format=%s", r) + "（取自最后一个提交）",
                        "state": "?", "base": "?", "head": "?", "draft": False}
                       for r in git("for-each-ref", "--format=%(refname)", "refs/pull").splitlines()]
    pr_rows = sorted(pr_rows, key=lambda p: -p["number"])[: args.pr_limit]
    w("| PR | 状态 | 标题 | 最早进的版本 |")
    w("|---|---|---|---|")
    for p in pr_rows:
        ref = f"refs/pull/{p['number']}"
        if subprocess.run(["git", "rev-parse", "-q", "--verify", ref], capture_output=True).returncode != 0:
            ref = f"{args.remote}/{p['head']}" if p.get("head") else None
        found = None
        if ref:
            for mk in markers:
                if is_ancestor(ref, mk.sha) or not patch_missing(mk.sha, ref):
                    found = mk
                    break
        state = {"merged": "已合", "open": "开着" + ("（草稿）" if p.get("draft") else ""), "closed": "已关、没合"}.get(p["state"], p["state"])
        title = p["title"].replace("|", "/")[:60]
        w(f"| #{p['number']} | {state} | {title} | {found.label if found else '**未装**'} |")
    w()

    w("## 每个版本合进了什么")
    w()
    recent = markers[-args.versions:]
    for mk in reversed(recent):
        prev = None
        for o in markers:
            if o is mk or version_key(o.version) >= version_key(mk.version):
                continue
            if is_ancestor(o.sha, mk.sha):
                prev = o
        rng = f"{prev.sha}..{mk.sha}" if prev else mk.sha
        subjects = [s for s in git("log", "--no-merges", "--format=%h %s", rng).splitlines()
                    if not DEV_SUBJECT.match(s.split(" ", 1)[1])][:15]
        w(f"### {mk.label} · {mk.date} · `{mk.sha[:7]}`" + (f"（相对 {prev.version}）" if prev else ""))
        for s in subjects:
            w(f"- {s[:110]}")
        w()
    return 0


if __name__ == "__main__":
    sys.exit(main())
