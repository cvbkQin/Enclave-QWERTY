# 纠错测试集（0.94）

- `corpus.txt`：13 段日常文字（聊天、工作、生活）。
- `chunks.json`：按 1–3 个词切成的 266 段，带拼音（`qw`）和九宫格数字（`t9`）。
- `eval_inputs.json`：由 `scripts/correction/make_inputs.py` 生成。每段原样打一次，再按五种手误各造一次，另外列出打到一半的所有中间状态。造法和随机种子与纠错原型相同。
- `results/`：跑出来的结果（不进 Git）。

## 怎么跑

1. 装好 Debug 版 App，打开一次，等词库部署完。
2. `bash scripts/correction/run-eval.sh sim <名字>`（模拟器）或 `bash scripts/correction/run-eval.sh device <名字> <设备 id>`（手机）。
3. 和基线比：`python3 scripts/correction/score.py Tests/Correction/results/<新>.json --base Tests/Correction/results/<基线>.json`

每一步改动都要跑：正常输入首选掉超过 0.5 个百分点，或者打到一半的中间状态首选被改动，就不合。
