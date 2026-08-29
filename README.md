# MaskMac 🖥️

[English](#english) | [中文说明](#中文说明)

---

## 中文说明

**MaskMac** 是一个轻量的 macOS 菜单栏工具：外接显示器时，**无需合盖即可一键关闭 MacBook 内建屏幕**。

### 🌟 为什么需要 MaskMac？

* 🔥 **防止发热伤屏**：MacBook 在“物理合盖（Clamshell Mode）”高负荷运行时，机身热量会直接烘烤屏幕，潜移默化损伤屏幕涂层与面板。开盖使用散热更好，有效保护屏幕寿命。
* ⌨️ **保留内置键盘与 Touch ID**：无需额外购置外接键盘、触控板，随时使用 Touch ID 指纹解锁。
* 🖥️ **专注外接大屏**：一键关闭内屏桌面，避免鼠标误移入内屏或窗口迷失。
* 🛡️ **防黑屏安全机制**：拔掉外接显示器或退出应用时，自动点亮内屏，避免黑屏风险。

### 快捷操作

| 菜单项 | 快捷键 | 说明 |
| :--- | :---: | :--- |
| **只保留外接显示器 / 恢复内建显示器** | `⌘ D` | 切换内屏开启 / 关闭状态 |
| **设置…** | `⌘ ,` | 查看显示器状态、配置退出时是否恢复内屏 |
| **退出 MaskMac** | `⌘ Q` | 退出应用（默认自动点亮内屏） |

### 安装与构建

#### 环境要求
* Apple Silicon Mac (M1/M2/M3/M4 系列)
* macOS 13.0 或更高版本

#### 方式 1：直接下载
前往 [Releases](../../releases) 下载最新的 `MaskMac-arm64.zip`，解压后拖入 `Applications` 文件夹即可。

#### 方式 2：从源码构建
```bash
git clone https://github.com/suennet2029/MaskMac.git
cd MaskMac
python3 build_app.py
```
构建产物位于 `dist/MaskMac.app`。

---

## English

**MaskMac** is a lightweight macOS menu bar utility that allows you to **turn off your MacBook's built-in display without closing the lid** when connected to external monitors.

### 🌟 Why MaskMac?

* 🔥 **Protect Display from Heat Damage**: Running high workloads in physical Clamshell Mode traps heat between the keyboard and screen, potentially degrading the display coating and LCD panel over time. MaskMac lets you keep the lid open for superior thermal dissipation.
* ⌨️ **Keep Keyboard & Touch ID**: Continue using the built-in keyboard, trackpad, and Touch ID without requiring external peripherals.
* 🖥️ **Focus on External Monitor**: Disable the built-in screen layout to avoid losing cursor or windows on the unused display.
* 🛡️ **Failsafe Protection**: Built-in screen automatically turns back on if all external monitors are disconnected or when quitting the app.

### Shortcuts

| Action | Shortcut | Description |
| :--- | :---: | :--- |
| **Toggle Internal Display** | `⌘ D` | Turn off or restore the built-in screen |
| **Settings…** | `⌘ ,` | View display topology & quit restore preferences |
| **Quit MaskMac** | `⌘ Q` | Terminate app (automatically restores screen by default) |

### Installation & Build

#### Requirements
* Apple Silicon Mac (M-series chips)
* macOS 13.0 or later

#### Option 1: Download Pre-built App
Download the latest `MaskMac-arm64.zip` from [Releases](../../releases), unzip and drag `MaskMac.app` to your `Applications` folder.

#### Option 2: Build from Source
```bash
git clone https://github.com/suennet2029/MaskMac.git
cd MaskMac
python3 build_app.py
```
The output app bundle will be placed in `dist/MaskMac.app`.

---

### 免责声明 / Disclaimer

本项目调用 macOS 私有显示接口以切换内屏状态。软件按“原样”提供，作者不对任何设备异常或因硬件兼容性产生的问题承担责任。

This project uses macOS private display APIs. Provided "as-is" without warranties of any kind.
