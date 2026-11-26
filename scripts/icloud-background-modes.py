#!/usr/bin/env python3
"""后台模式和后台任务编号：按包里有什么功能写进 Info.plist（04 审查 #75 第 7 条；第 99 条加了词库自动更新）。

- 每个包都有：后台刷新（fetch）和热门词库自动更新的任务编号 <bundle>.dicts.refresh（App/DictAutoUpdate.swift）。
- 只在 ICLOUD_SYNC=YES 的包里有：充电时的后台任务（processing）、CloudKit 静默推送（remote-notification）
  和同步的两个任务编号（App/Sync/ICloudSyncScheduler.swift）。没有同步的包不声明，免得审核问「声明了后台模式却没有用到」。
Xcode 在处理完 Info.plist 之后、签名之前跑这个脚本（project.yml 里的 postBuildScripts），改的是编好的那份。
UIBackgroundModes 里别的功能加的模式不动，只加、减这里列的几种。
"""
import os
import plistlib
import sys

ALWAYS_MODES = ["fetch"]
SYNC_MODES = ["processing", "remote-notification"]


def main() -> int:
    path = os.path.join(os.environ["TARGET_BUILD_DIR"], os.environ["INFOPLIST_PATH"])
    enabled = os.environ.get("ICLOUD_SYNC", "NO") == "YES"
    bundle = os.environ["PRODUCT_BUNDLE_IDENTIFIER"]
    always_tasks = [f"{bundle}.dicts.refresh"]
    sync_tasks = [f"{bundle}.sync.refresh", f"{bundle}.sync.processing"]

    with open(path, "rb") as f:
        data = f.read()
    fmt = plistlib.FMT_BINARY if data.startswith(b"bplist") else plistlib.FMT_XML
    info = plistlib.loads(data)
    before = plistlib.dumps(info, fmt=fmt)

    managed_modes = ALWAYS_MODES + SYNC_MODES
    managed_tasks = always_tasks + sync_tasks
    modes = [m for m in info.get("UIBackgroundModes", []) if m not in managed_modes] + ALWAYS_MODES
    ids = [t for t in info.get("BGTaskSchedulerPermittedIdentifiers", []) if t not in managed_tasks] + always_tasks
    if enabled:
        modes += SYNC_MODES
        ids += sync_tasks
    for key, value in (("UIBackgroundModes", modes), ("BGTaskSchedulerPermittedIdentifiers", ids)):
        if value:
            info[key] = value
        else:
            info.pop(key, None)

    after = plistlib.dumps(info, fmt=fmt)
    if after != before:
        with open(path, "wb") as f:
            f.write(after)
    print(f"Background modes: fetch + dicts refresh; iCloud sync {'on' if enabled else 'off'} ({path})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
