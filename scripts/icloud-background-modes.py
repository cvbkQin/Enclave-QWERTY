#!/usr/bin/env python3
"""iCloud 同步的后台模式：只在 ICLOUD_SYNC=YES 的包里写进 Info.plist（04 审查 #75 第 7 条）。

后台刷新（fetch）、充电时的后台任务（processing）、CloudKit 静默推送（remote-notification）和两个后台任务编号
只给 iCloud 同步用（App/Sync/ICloudSyncScheduler.swift）。没有同步的包不声明，免得审核问「声明了后台模式却没有用到」。
Xcode 在处理完 Info.plist 之后、签名之前跑这个脚本（project.yml 里的 postBuildScripts），改的是编好的那份。
UIBackgroundModes 里别的功能加的模式不动，只加、减这三种。
"""
import os
import plistlib
import sys

MODES = ["fetch", "processing", "remote-notification"]


def main() -> int:
    path = os.path.join(os.environ["TARGET_BUILD_DIR"], os.environ["INFOPLIST_PATH"])
    enabled = os.environ.get("ICLOUD_SYNC", "NO") == "YES"
    bundle = os.environ["PRODUCT_BUNDLE_IDENTIFIER"]
    tasks = [f"{bundle}.sync.refresh", f"{bundle}.sync.processing"]

    with open(path, "rb") as f:
        data = f.read()
    fmt = plistlib.FMT_BINARY if data.startswith(b"bplist") else plistlib.FMT_XML
    info = plistlib.loads(data)
    before = plistlib.dumps(info, fmt=fmt)

    modes = [m for m in info.get("UIBackgroundModes", []) if m not in MODES]
    ids = [t for t in info.get("BGTaskSchedulerPermittedIdentifiers", []) if t not in tasks]
    if enabled:
        modes += MODES
        ids += tasks
    for key, value in (("UIBackgroundModes", modes), ("BGTaskSchedulerPermittedIdentifiers", ids)):
        if value:
            info[key] = value
        else:
            info.pop(key, None)

    after = plistlib.dumps(info, fmt=fmt)
    if after != before:
        with open(path, "wb") as f:
            f.write(after)
    print(f"iCloud background modes: {'on' if enabled else 'off'} ({path})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
