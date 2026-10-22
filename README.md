# Enclave

A self-hosted AI keyboard for iOS. Polish, rewrite, or draft text with your own model, and nothing is sent until you confirm.

Enclave 是一款可以自部署的 iOS AI 输入法。它只调用你自己指定的模型（自建服务器或你选的 API），不经过任何第三方后台。

## 怎么用

键盘上只有一个「执行」键，它读取当前输入框里的文字，按写法决定做什么：

| 输入框里写 | 效果 |
| --- | --- |
| `明天开会改到三点` | 润色 |
| `明天开会改到三点 // 语气正式点` | 按要求改 |
| `// 帮我写一段请假说明，周五，家里有事` | 帮我写 |
| `// 再短一点`（上一轮是帮我写） | 接着上一轮追问 |

结果先显示在预览区，输入框不变。满意后点「替换」或「插入」，发送永远由你自己按。

反复修改：替换后可以直接在输入框里手改，再在末尾加 `// 新要求` 点执行。手改过的内容就是新的起点，模型会保留它。每一轮都会生成一个新版本，预览区顶部可以左右切换，「新会话」清空历史。

## 在自己的 iPhone 上运行

需要一台装了 Xcode 的 Mac，免费 Apple ID 就可以，不需要付费开发者账号。

1. 安装 XcodeGen：`brew install xcodegen`
2. 复制 `Configs/Local.xcconfig.template` 为 `Configs/Local.xcconfig`，填写：
   - `BUNDLE_ID_PREFIX`：全球唯一的前缀，比如 `com.zhangsan`
   - `DEVELOPMENT_TEAM`：在 Xcode › Settings › Accounts 登录 Apple ID 后能看到 Team ID
3. 在仓库根目录运行 `xcodegen generate`，打开生成的 `Enclave.xcodeproj`。
4. iPhone 用数据线连 Mac，在 iPhone 的 设置 › 隐私与安全性 里打开「开发者模式」。
5. 在 Xcode 里选择 Enclave scheme 和你的 iPhone，运行。
6. 打开 Enclave App，填 API 地址、模型名和 API Key，点「测试连接」。
7. 设置 › 通用 › 键盘 › 键盘 › 添加新键盘 › Enclave，再点进去打开「允许完全访问」。

免费 Apple ID 的限制：签名 7 天后过期，需要重新用 Xcode 安装一次；每台设备最多同时装 3 个免费签名的 App。

如果 App 里显示「App 与键盘共享配置：不可用」，说明这次签名没有拿到 App Group。这时在 App 里点「复制配置」，再到键盘里点「从剪贴板导入配置」即可，导入后剪贴板会自动清空。

## 模型接口

任何 OpenAI 兼容的 `/v1/chat/completions` 接口都可以：

- 第三方 API，例如 DeepSeek：地址 `https://api.deepseek.com/v1`，模型 `deepseek-chat`
- 自建 Ollama：地址 `http://<服务器IP>:11434/v1`，模型例如 `qwen3:8b`，API Key 留空
- 手机不在同一个局域网时，推荐用 Tailscale 访问家里或公司的服务器，不要直接暴露到公网

推理模型输出的 `<think>…</think>` 会被自动去掉。为了速度，自建模型建议关闭思考模式，并让模型常驻内存。

## 隐私

- API Key 只存在本机钥匙串，不写进配置文件，也不会提交到仓库。
- 除了你填的 API 地址，App 和键盘不访问任何其他网络地址。
- 编辑历史只存在本机。

## 工程结构

```
project.yml          XcodeGen 配置
Configs/             签名配置（Local.xcconfig 不提交）
App/                 主 App：API 设置、风格预设、开启键盘引导
Keyboard/            键盘扩展：AI 面板
Shared/              两边共用：接口客户端、prompt、版本历史、存储
```

## 路线

- **M1（当前）**：AI 面板 + `//` 语法，真机自用
- **M2**：键盘内置 RIME 拼音，要求直接在面板里打，不用切键盘
- **M3**：语音输入（跳转 App 开启麦克风会话）
