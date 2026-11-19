# 打字性能基准

04 每次装机前在 Mac 上跑一次，看这一版打字有没有变慢、内存有没有变大。

```bash
scripts/bench/run-bench.sh            # 编开发版、装到「iPhone SE 0911b」、跑 3 次取中位数、和基线比
scripts/bench/run-bench.sh --no-build # 刚编过就不再编
```

退出码 0：没有变慢；1：有一项超过门槛（先再跑一次排除偶然，还在就别装机，报给 01）。

## 跑的是什么

App 带 `-keyboardDebug "qwerty,bench" -playground` 启动，打开「试一试」弹出键盘。键盘等拼音引擎加载好后，
自己把 10 句常用拼音（和 memtest 同一组）一个字母一个字母地打 3 遍，键与键之间让界面照常画一轮：

| 字段 | 意思 |
| --- | --- |
| `keyMedianMs`、`keyP95Ms`、`keyMaxMs` | 每个键：引擎算候选 + 候选交给界面 + 键盘界面排完，接近手机上「按下到候选出来」（不含系统触摸和画到屏幕） |
| `engineMedianMs`、`engineP95Ms` | 其中引擎那部分 |
| `coldSentenceMs` | 键盘刚启动时打的第一句（热身那遍，不算进中位数） |
| `memStartMB`、`memPeakMB`、`memEndMB` | 键盘进程内存（phys_footprint，和系统杀键盘看的是同一个数） |
| `firstCandidates` | 每句打完的首选，变了只提示 |

第 1 遍是热身，只用后 2 遍算中位数和 P95。基准只调引擎、刷新界面，输入框里只有带下划线的拼音、每句打完清掉，不上屏，不改按键本身的代码；
`bench` 选项只在 Debug 编译里有，TestFlight 和正式包里没有。

## 门槛

和 `bench/baseline.json` 比（同一台模拟器前后比；模拟器的绝对数和手机不一样，只看变化）：

- 按键耗时中位数：多 20% 且多 0.5 ms 以上
- 按键耗时 P95：多 30% 且多 2 ms 以上
- 内存峰值：多 10 MB 以上

门槛在 `scripts/bench/compare.py` 开头。

## 基线

`bench/baseline.json` 是 0.97 的数（`--save-baseline` 存的）。正式版合进 main 后，04 确认数字没问题，
可以用 `--save-baseline` 换成新版本的基线并提交。

## 前提

- 模拟器里已经添加飞地键盘（设置 › 通用 › 键盘 › 键盘 › 添加新键盘），并且上次用的是飞地键盘。
- 模拟器菜单 I/O › Keyboard 里关掉「Connect Hardware Keyboard」，否则软键盘不弹。
- 只编开发版（`INTERNAL_BUILD=NO PUBLIC_BUILD=NO`），产物在 `build/bench/`，不读 `Configs/Local.xcconfig`。
- 跑完会不带调试选项再启动一次 App，把 `bench` 选项清掉，模拟器上留下的是一个普通开发版。
