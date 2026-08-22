# TabType

> 原生 macOS 应用切换器增强：按住 ⌘Tab 后，敲应用名的首字母（中文应用取拼音首字母）直接跳转。
> Native macOS app switcher enhancement: jump to an app by typing its name's initial (pinyin initials for Chinese app names) while holding ⌘Tab.

复刻自 2017 年后停更的 [CmdTap](https://www.yingdev.com/)（YingDev 出品）。原版是 Intel-only 二进制，依赖 Rosetta 2 运行；随着 Apple 移除 Rosetta，它在 Apple Silicon Mac 上即将彻底失效。TabType 是 arm64 原生重写，仅约 600 行 Swift，零第三方依赖。

## 功能

- **⌘Tab 唤起系统原生切换器**（不是替代品——扩展它）
- 按住 ⌘ 期间敲字母选中应用：`w` → 微信（拼音首字母）、`gc` → Google Chrome
- 同首字母多应用：`M` / `M×2` 徽章标注，连按推进（按启动顺序稳定分配，不随使用顺序变）
- 每个图标下有徽章提示该敲什么字母；⌘Tab 按住期间用 ↑↓ 可微调徽章位置（自动保存）
- 按住 fn 时字母豁免——纯净的原生 ⌘Tab 体验
- 松开 ⌘ 切换（完全原生语义）

## 安装

1. 构建或下载 `TabType.app`，放入 `/Applications`
2. 首次启动会请求**辅助功能权限**（系统设置 → 隐私与安全性 → 辅助功能 → 开启 TabType）
3. 重启 TabType，按住 ⌘+Tab 试试

> 权限用途说明：TabType 只用辅助功能权限做两件事——读取系统切换器的应用列表、写入选中项。无任何数据采集、无网络请求。

## 构建

```bash
./build.sh          # swift build → 组装 .app → ad-hoc 或本地证书签名
```

macOS 13+，Apple Silicon 原生。技术上通过 Accessibility API（AXProcessSwitcherList）操纵原生切换器——在 macOS 26 上实测可用；入口是屏幕中心点取+父链爬升（Dock 的 windows 属性在新系统已不可用，详见 `设计/系统设计.md`）。

## 已知限制

- 多显示器：切换器所在屏生效（跟随系统主屏）
- 极快按键（⌘Tab 后 <300ms 内敲字母）会缓存补跳，极少数情况下可能丢失
- 输入法为中文时字母键正常工作（拦截发生在 HID 层，先于输入法）

## 致谢

- [CmdTap](https://www.yingdev.com/) by YingDev——交互设计的原创者
