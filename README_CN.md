# ClipboardManager

一个简洁优雅的 macOS 剪贴板管理工具。

[English](README.md)

## 功能特点

- 📋 **剪贴板历史** - 自动保存复制的文本和图片
- 🔍 **快速搜索** - 即时查找剪贴板内容
- 📌 **置顶功能** - 将重要内容固定在顶部
- 🖼️ **图片支持** - 预览和管理复制的图片
- ⌨️ **全局快捷键** - 使用 `⌘⇧V` 快速访问
- 🚀 **开机自启** - 随 macOS 自动启动
- 🌐 **多语言** - 支持中文和英文
- 🎯 **拖放支持** - 将内容拖放到任意应用
- 💾 **持久存储** - 重启后历史记录不丢失

## 安装

### 下载 DMG

从 [Releases](https://github.com/yourusername/ClipboardManager/releases) 页面下载最新版本。

### 从源码构建

要求：
- macOS 13.0+
- Xcode 15.0+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

```bash
# 克隆仓库
git clone https://github.com/yourusername/ClipboardManager.git
cd ClipboardManager

# 生成 Xcode 项目
xcodegen generate

# 构建
xcodebuild -scheme ClipboardManager -configuration Release build
```

## 使用方法

1. 启动应用 - 图标会出现在菜单栏
2. 复制任何内容 - 自动保存到历史记录
3. 点击菜单栏图标或按 `⌘⇧V` 打开
4. 点击项目即可复制并粘贴
5. 悬停可看到置顶/删除按钮

### 快捷键

| 快捷键 | 功能 |
|--------|------|
| `⌘⇧V` | 打开/关闭剪贴板管理器 |

### 筛选标签

- **全部** - 显示所有项目
- **文字** - 仅显示文本
- **图片** - 仅显示图片

## 设置

- **开机自启动** - 登录时自动启动
- **语言** - 切换中文和英文

## 权限说明

应用需要 **辅助功能** 权限才能使全局快捷键正常工作。

前往：系统设置 → 隐私与安全性 → 辅助功能 → 启用 ClipboardManager

## 技术栈

- Swift 5.9
- SwiftUI
- AppKit
- Carbon（用于全局快捷键）

## 许可证

MIT License

## 贡献

欢迎贡献代码！请随时提交 Pull Request。
