# 打字性能基准

04 每次装机前在 Mac 上跑一次，看这一版打字有没有变慢、内存有没有变大。

```bash
scripts/bench/run-bench.sh            # 编开发版、装到「iPhone SE 0911b」、跑 3 次取中位数、和基线比
scripts/bench/run-bench.sh --no-build # 刚编过就不再编
```

退出码 0：没有变慢；1：有一项超过门槛（先再跑一次排除偶然，还在就别装机，报给 01）；2：没有基线或基线缺字段，什么都没比；64：参数写错。

## 跑的是什么

App 带 `-keyboardDebug bench -playground` 启动，打开「试一试」弹出键盘。键盘不是全键盘时先切过去（跑完、出错都切回原来的布局），
等 Rime 真正启动完（不只是词库文件在）后，
自己把 10 句常用拼音（和 memtest 同一组）一个字母一个字母地打 3 遍。每个键走和手指按键同一条路：
`perform(.letter)` → `feedEngine` → 后台引擎 `inputLater` → `applyEngineResults`（上屏、纠错、候选菜单、刷新候选）
→ 下一轮主循环界面画完时 `TypingStats.record`，耗时取的就是 record 收到的那个数（App「拼音词库」页统计的也是它）。
一个键的候选画完，才按下一个键。

| 字段 | 意思 |
| --- | --- |
| `keyMedianMs`、`keyP95Ms`、`keyMaxMs` | 每个键：从交给引擎到界面按新候选画完 |
| `engineMedianMs`、`engineP95Ms` | 其中引擎自己算的时间 |
| `coldSentenceMs` | 键盘刚启动时打的第一句（热身那遍，不算进中位数） |
| `memStartMB`、`memPeakMB`、`memEndMB` | 键盘进程内存（phys_footprint，和系统杀键盘看的是同一个数） |
| `firstCandidates` | 每句打完的首选，变了只提示 |

第 1 遍是热身，只用后 2 遍算中位数和 P95。

**测不到的：**

- 系统把触摸送到键盘那一段（`KeyTouchView` 之前），以及按键按下的气泡、震动、声音。
- 选词、上屏、学词、联想：每句打完直接清掉拼音，不选词，这样词库不学、几次跑的条件一样。
- 九宫格、双拼、英文。
- 测的是 Debug 编译（`bench` 选项只在 Debug 里有，-Onone），绝对数比手机上的正式包大，只拿来和基线前后比。

基准在跑时，按键耗时交给基准，不记进「拼音词库」页的统计。`bench` 选项和这个钩子只在 Debug 编译里有，
TestFlight 和正式包里没有；没改按键本身的代码。

## 门槛

和 `bench/baseline.json` 比（同一台模拟器前后比；模拟器的绝对数和手机不一样，只看变化）：

- 按键耗时中位数：多 20% 且多 0.5 ms 以上
- 按键耗时 P95：多 30% 且多 2 ms 以上
- 内存峰值：多 10 MB 以上

门槛在 `scripts/bench/compare.py` 开头。

## 基线

**现在还没有基线**（`bench/baseline.json` 没提交过；计时口径在 PR #78 换成了走真实按键路径，之前本地跑出的数也不能拿来比）。
基准合进开发分支后，04 第一次装机前先跑：

```bash
scripts/bench/run-bench.sh --save-baseline
```

确认数字正常后提交 `bench/baseline.json`。之后每个正式版合进 main，04 觉得合适时再用 `--save-baseline` 换新基线并提交。

## 前提

- 模拟器里已经添加飞地键盘（设置 › 通用 › 键盘 › 键盘 › 添加新键盘），并且上次用的是飞地键盘。
- 模拟器菜单 I/O › Keyboard 里关掉「Connect Hardware Keyboard」，否则软键盘不弹。
- 没部署双拼方案（句子是全拼；装了双拼时键盘报 `double pinyin deployed`，不出数）。
- 只编开发版（`INTERNAL_BUILD=NO PUBLIC_BUILD=NO`，Key 不会编进去），产物在 `build/bench/`。
  Bundle ID 跟着 Base.xcconfig：有 `Configs/Local.xcconfig` 时用里面的前缀，没有时是 `com.example`；脚本自己不读它。
- 跑完（包括中途出错、Ctrl-C）都会不带调试选项再启动一次 App，把 `bench` 选项清掉；键盘布局由基准自己切回原来的。
