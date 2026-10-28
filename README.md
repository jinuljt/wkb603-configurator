# WKB603 Configurator

面向京造 WKB603 / JZ990 白光键盘的 macOS 可视化改键工具。点击键帽，选择普通键、组合键或媒体功能，把完整方案保存到键盘。

原生 SwiftUI + IOKit，无第三方依赖，无需常驻，不监听键盘输入。MIT 开源。

## 使用

1. 从 [Releases](https://github.com/jinuljt/wkb603-configurator/releases) 下载通用 macOS 应用，解压到本地后打开。支持 macOS 13+、Apple Silicon 和 Intel；Intel 二进制已交叉编译，未在 Intel 实机运行验证。
2. 用 USB **数据线**连接键盘，关闭无线开关。点击键帽，在右侧选择功能，点“添加到方案”。
3. 按应用提示，在“系统设置 → 隐私与安全性 → 输入监控”为 **WKB603 Configurator** 开启权限，按系统提示重开应用。无需给 ChatGPT、终端或其他应用长期授权。
4. 点“检查并写入键盘”，核对完整清单并确认覆盖范围，再写入。
5. 实际按键测试，保持无线关闭、拔线约 10 秒后重插复测。配置完成后可以关闭该权限并退出应用。

应用仅做本地临时代码签名，**没有 Apple Developer ID 签名或公证**。下载版可能被 Gatekeeper 阻止；先核对源码与校验值，按照 [Apple 官方说明](https://support.apple.com/zh-cn/102445)处理，或自行从源码构建。无需关闭系统安全检查。

## 写入前必须了解

- **不能读取键盘里完整的当前键位表。** 界面显示的是本地方案，不是设备回读。原有自定义键位需要手动加入方案。
- 协议按**整张普通层**覆盖：方案未列出的普通键恢复默认。Fn 层与灯效配置不会发送；Fn 暂不支持编辑。
- 仅验证了指定白光 WKB603（USB 名 `WKB603`，VID `05ac` / PID `024f`，64 字节 Feature 接口）。同名不同批次、RGB 版、RS2 及其他型号未验证；不会自动匹配它们。
- 保存响应成功后仍需测试实际效果。USB 断电重插保留已在一把 WKB603 上验证；跨电脑、蓝牙、2.4 GHz 的效果尚未实测。
- 失败时可能已有部分命令发出。应用立即停止后续发送；请先断开重连再重试。
- 本工具不刷写固件，不含厂家 EXE、DLL、固件或图片资源，不使用云服务、统计或按键监听。

## 已验证示例

“载入三键示例”或导入 [`profiles/mac-three-keys.json`](profiles/mac-three-keys.json)：

| 物理键 | 新功能 |
| --- | --- |
| Insert | Command + Shift + 2 |
| Cal | Command + Space |
| Pause | 播放 / 暂停 |

这组三键已通过独立原生写入工具在实机上验证，USB 断电重插后保留，原来的按键扩散灯效正常。GUI 使用同一份报告数据并有回归自检；更多键位、媒体操作及组合仍应逐项实测。Mac 专用组合键换到 Windows 后用途不同。

## 从源码构建

需要 macOS 13+ 与 Apple Command Line Tools（Swift 5.9+）。

```sh
git clone https://github.com/jinuljt/wkb603-configurator.git
cd wkb603-configurator
swift build
.build/debug/WKB603Configurator --self-test
bash scripts/build-app.sh
```

双击 `dist/WKB603 Configurator.app`。脚本构建 arm64 + x86_64 通用应用与 ZIP，不需要 Xcode 工程或额外包管理器。

本地方案保存在 `~/Library/Application Support/WKB603Configurator/profile.json`；可从 GUI 导出 JSON 备份。不应将本地个人方案提交到仓库。

## 开发与协议

`Sources/WKB603Configurator`：`Layout.swift` 是重新绘制的功能布局与矩阵索引；`Profile.swift` 构造配置；`HID.swift` 管理严格设备匹配和确认响应；`App.swift` 提供 GUI。

[`docs/index.html`](docs/index.html) 是可离线打开的说明与协议记录。`--self-test` 不访问或写入设备，检查实机报告摘要、方案验证、设备匹配、确认顺序及失败后停止行为。持续集成只运行离线检查。

This is an independent macOS remapping utility for one verified WKB603 white-backlight model. No affiliation with the keyboard manufacturer. Full normal-layer replacement, not a firmware flasher. Existing onboard mappings cannot be read back. See the limitations above before writing.
