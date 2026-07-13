# ClipboardManager

<p align="center">
  <strong>会思考的剪贴板管理器。</strong><br>
  自动去除 URL 追踪参数 · 检测敏感信息 · 按目标应用智能粘贴
</p>

[English](README.md)

## 为什么选择 ClipboardManager？

多数剪贴板工具只负责**记录**。ClipboardManager 还会**处理**。

每次复制时，规则引擎实时评估内容——去除 URL 追踪参数、识别 API Key / 银行卡号、或自动置顶特定应用内容。粘贴时，Smart Paste 会按目标应用自动适配格式。

### 功能对比

```
                        ClipboardManager    Maccy    Raycast Clipboard
规则引擎                       ✅              ❌         ❌
Smart Paste                    ✅              ❌         ❌
URL 追踪去除                   ✅              ❌         ❌
敏感信息检测                   ✅              ❌         ❌
正则变换                       ✅              ❌         ❌
OCR（图片 → 文字）             ✅              ❌         ✅
模糊搜索                       ✅              ✅         ✅
富文本 / 图片                  ✅              ❌         ✅
iCloud 同步                    ✅              ❌         ❌
代码语法高亮                   ✅              ❌         ❌
Quick Paste（光标旁）          ✅              ❌         ❌
粘贴队列模式                   ✅              ❌         ❌
截图自动捕获                   ✅              ❌         ❌
按当前应用筛选                 ✅              ❌         ❌
100% 开源                      ✅              ✅         ❌
```

## 核心功能

### 剪贴板规则引擎

- **去除 URL 追踪参数** — `utm_source`、`fbclid`、`gclid` 等
- **敏感内容检测** — 信用卡、AWS Key、SSH 私钥；默认 60 秒后过期
- **自定义规则** — 正则 / 应用 / 内容类型触发，支持 JavaScript 脚本动作

### Smart Paste

- VSCode / Obsidian：URL 转 Markdown 链接，代码块自动围栏
- Terminal / iTerm2 / Warp：危险字符自动转义
- Slack / 邮件 / 笔记等：按应用适配格式

### 剪贴板历史

- 文本、富文本、图片
- 模糊搜索 + 高亮匹配
- 置顶、多选合并粘贴、拖放
- 冷热分层存储：热数据常驻内存，冷数据走 SQLite/FTS

### 隐私优先

- 敏感内容自动检测与过期
- 默认排除密码管理器
- 数据本地存储（iCloud 同步可选）
- 无遥测、无分析

### 其它

- 全局快捷键（`⌘⇧V`，可自定义）
- 粘贴队列（`⌘⇧B`）
- OCR（设备端 Vision）
- 文本变换、代码高亮、Snippet 文本扩展
- 导入/导出备份、开机启动
- 中英文界面

## 安装

### Homebrew

```bash
brew install --cask clipboardmanager
```

### 下载 DMG

从 [Releases](https://github.com/nicebro/ClipboardManager/releases) 下载最新版本。

### 从源码构建

要求：macOS 13.0+、Xcode 15.0+、[XcodeGen](https://github.com/yonaskolb/XcodeGen)

```bash
git clone https://github.com/nicebro/ClipboardManager.git
cd ClipboardManager
xcodegen generate
xcodebuild -scheme ClipboardManager -configuration Release build
```

## 使用方法

1. 启动应用 — 图标出现在菜单栏
2. 复制任意内容 — 自动进入历史
3. 点击菜单栏图标或按 `⌘⇧V` 打开
4. 点击条目即可复制并粘贴
5. 悬停可置顶 / 删除

### 快捷键

| 快捷键 | 功能 |
|--------|------|
| `⌘⇧V` | 打开/关闭剪贴板管理器 |
| `⌘⇧B` | 粘贴队列下一项 |

### 筛选

- **全部 / 文字 / 图片 / 截图**
- **按来源应用筛选**
- **仅当前应用**

## 设置

- 开机自启动
- 语言（中文 / 英文）
- 规则管理与测试
- iCloud 同步
- 历史数量与自动清理

## 权限说明

需要 **辅助功能** 权限以支持全局快捷键与模拟粘贴。

系统设置 → 隐私与安全性 → 辅助功能 → 启用 ClipboardManager

## 技术栈

- Swift 5.9 · SwiftUI · AppKit
- SQLite FTS5 · Carbon 全局快捷键
- 零第三方运行时依赖（Sparkle 可选）

## 性能相关优化

- 启动仅加载热窗口历史（默认约 2000 条 + 全部置顶），完整库仍可通过 FTS 搜索
- 列表刷新基于 `historyRevision`，useCount 等小改动不整表刷新
- 大库 Fuzzy 回退扫描有上限，优先 FTS
- 剪贴板轮询空闲深度降频，降低后台 CPU

## 许可证

MIT License

## 贡献

欢迎提交 Issue 与 Pull Request。详见 [CONTRIBUTING.md](CONTRIBUTING.md)。
