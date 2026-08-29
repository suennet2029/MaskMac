# MaskMac 🖥️

**English** | [简体中文](README_zh.md)

---

**MaskMac** is a lightweight macOS menu bar utility that allows you to **turn off your MacBook's built-in display without closing the lid** when connected to external monitors.

### 🌟 Why MaskMac?

* 🔥 **Protect Display from Heat Damage**: Running high workloads in physical Clamshell Mode traps heat between the keyboard and screen, potentially degrading the display coating and LCD panel over time. MaskMac lets you keep the lid open for superior thermal dissipation.
* ⌨️ **Keep Keyboard & Touch ID**: Continue using the built-in keyboard, trackpad, and Touch ID without requiring external peripherals.
* 🖥️ **Focus on External Monitor**: Disable the built-in screen layout to avoid losing cursor or windows on the unused display.
* 🛡️ **Failsafe Protection**: Built-in screen automatically turns back on if all external monitors are disconnected or when quitting the app.

### ⌨️ Shortcuts

| Action | Shortcut | Description |
| :--- | :---: | :--- |
| **Toggle Internal Display** | `⌘ D` | Turn off or restore the built-in screen |
| **Settings…** | `⌘ ,` | View display topology & quit restore preferences |
| **Quit MaskMac** | `⌘ Q` | Terminate app (automatically restores screen by default) |

### 🚀 Installation & Build

#### Requirements
* Apple Silicon Mac (M1/M2/M3/M4 Series)
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

### Disclaimer

This project uses macOS private display APIs to toggle internal display states. Provided "as-is" without warranties of any kind. The author assumes no liability for device anomalies or compatibility issues.

