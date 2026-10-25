# Enclave keyboard

A Chinese Pinyin keyboard for iOS whose AI features run on your own API. Connect any OpenAI-compatible endpoint or a model you host yourself. Nothing is sent until you tap Polish, and the developer runs no servers.

Enclave 是一款 iOS 中文拼音输入法，最大的特点是 AI 功能用你自己的接口：填上任意 OpenAI 兼容接口，或者自己部署的模型，文字直接发给你选的服务，不经过任何中转服务器。

- 支持页：https://cvbkqin.github.io/Enclave-QWERTY/
- 隐私政策：https://cvbkqin.github.io/Enclave-QWERTY/privacy.html（全文也在 [PRIVACY.md](PRIVACY.md)）
- 界面语言：简体中文、English、日本語

## 功能

**拼音键盘**
- 全键盘（26 键）和九宫格，九宫格带数字面板
- 模糊拼音、常用词
- 词库来自万象拼音，键盘自带一份编译好的词库，不开「允许完全访问」也能正常打字
- 遇到数字、电话号码输入框时自动切到数字键盘

**AI 润色**
- 写完一句话点「润色」，按选好的风格改写：自动、正式、口语、简短、结构，也可以自己写风格
- 在输入框末尾加 `// 要求` 可以按要求改，例如 `明天开会改到三点 // 语气正式点`；只写 `// 帮我写一段请假说明` 是帮你写
- 结果先显示在键盘上，点「替换」或「插入」才会改动输入框；不满意点「再润」
- App 里的「场景实验室」可以在不同场景下试效果

**隐私**
- 只在点「润色」「再润」时发送；第一次发送前、以及换了接口地址后，会显示发送地址并征得同意
- 打字、候选、输入学习都在本机完成
- API Key 只存在本机钥匙串；没有广告、统计、崩溃上报或其他第三方 SDK

**价格**
- 14 天免费试用，AI 功能不限次数
- 试用结束后 AI 功能每天免费 10 次，App 内一次买断（US$2.99）不限次数
- 打字和拼音永久免费

## 模型接口

任何 OpenAI 兼容的 `/v1/chat/completions` 接口都可以，在 App 的「API」页选服务商或「自定义」：

| 例子 | 地址 | 模型 |
| --- | --- | --- |
| DeepSeek | `https://api.deepseek.com/v1` | `deepseek-chat` |
| 自建 Ollama | `http://<电脑的局域网 IP>:11434/v1` | 例如 `qwen3:8b`，API Key 留空 |

也支持 vLLM、LM Studio 等自建服务。手机不在同一个局域网时，建议用 Tailscale 之类的 VPN 访问，不要把服务直接暴露到公网。推理模型输出的 `<think>…</think>` 会被自动去掉；自建模型建议关闭思考模式，并让模型常驻内存。

## 从源码构建

需要一台装了 Xcode 26 的 Mac。

1. 安装 XcodeGen：`brew install xcodegen`
2. 复制 `Configs/Local.xcconfig.template` 为 `Configs/Local.xcconfig`，填写 `BUNDLE_ID_PREFIX`（全球唯一，例如 `com.zhangsan`）和 `DEVELOPMENT_TEAM`（Xcode › Settings › Accounts 里能看到）。
3. 下载拼音引擎和词库，并生成键盘自带的词库：
   ```sh
   bash scripts/fetch-rime.sh
   bash scripts/prebuild-rime.sh
   ```
4. `xcodegen generate`，打开 `Enclave.xcodeproj`，选 Enclave scheme 运行。
5. 手机上：设置 › 通用 › 键盘 › 键盘 › 添加新键盘 › Enclave。要用 AI 功能再打开「允许完全访问」。

模拟器里购买走 `Configs/Enclave.storekit` 的本地配置，不连 App Store。

用免费 Apple ID 签名时拿不到 App Group，App 和键盘不能共享设置。这时 App 里会出现「复制配置」，在键盘里点「从剪贴板导入配置」即可，导入后剪贴板会自动清空。

## 工程结构

```
project.yml      XcodeGen 配置（版本号也在这里）
Configs/         签名配置（Local.xcconfig 不提交）、RIME 方案、StoreKit 本地配置
App/             主 App：接口设置、风格、常用词、场景实验室、试用与购买、隐私政策和开源许可
Keyboard/        键盘扩展：拼音键盘、AI 栏
Shared/          两边共用：模型接口客户端、prompt、发送同意、试用计数、存储
scripts/         下载 librime 和万象词库、生成词库
docs/            支持页和隐私政策（GitHub Pages）
```

## 开源组件

拼音引擎 [librime](https://github.com/rime/librime)（BSD-3-Clause），词库来自 [万象拼音](https://github.com/amzxyz/rime_wanxiang)（CC BY 4.0，去掉了声调并按词频删减），以及 OpenCC、Boost、glog、LevelDB、marisa-trie、yaml-cpp、librime-lua、Lua。完整列表和许可证见 App 里的「关于 › 开源许可」。
