# MaskMac 🖥️

**English** | [简体中文](README_zh.md)

---

**MaskMac** is a lightweight macOS menu bar utility designed for Apple Silicon Macs:

1. **Extend**: Turn off your MacBook's built-in display without closing the lid when connected to external monitors.
2. **Duo**: Frosted glass transition effect mimicking dual-screen folding devices when adjusting the MacBook lid.
3. **Brightness**: Compact frosted HUD popup to smoothly adjust display brightness and MacBook native keyboard backlight with sliders (dismisses immediately upon clicking anywhere outside).
4. **Aura**: Automatically senses local tasks from **Claude Code**, **CodeX**, and **antiGravity**, triggering a vibrant **Top-Bar Neon Laser Runner** and gentle **Keyboard Backlight Breathing** during execution, then smoothly fading away upon completion without interfering with typing.

### 🌟 Highlights

* 🔥 **Protect Display from Heat Damage**: Running high workloads in Clamshell Mode traps heat between the keyboard and screen. Keeping the lid open provides superior thermal dissipation and preserves screen coating.
* ⌨️ **Keep Keyboard & Touch ID**: Continue using built-in keyboard, trackpad, and Touch ID without external peripherals.
* ☀️ **Quick Brightness Controls (Brightness)**: Click `Brightness` in the menu bar to adjust screen and keyboard backlight brightness directly via smooth sliders. Automatically dismisses on outside clicks.
* 🌈 **AI Task Neon Aura (Aura)**: Automatically detects active Claude Code, CodeX, or antiGravity sessions, flowing a vivid cyberpunk laser stream along the top edge while breathing keyboard backlight—zero keystroke conflicts.
* 🛡️ **Failsafe Protection**: Built-in screen automatically turns back on if external monitors are disconnected or when quitting the app.

### ⌨️ Menu & Shortcuts

| Action | Shortcut | Description |
| :--- | :---: | :--- |
| **Extend** | `⌘ D` | Toggle built-in display on / off (external display only) |
| **Duo** | — | Toggle lid angle sensor frosted transition effect |
| **Brightness** | `⌘ B` | Open compact HUD to adjust screen & keyboard brightness (dismisses on outside click) |
| **Aura** | — | Toggle AI task indicator (Top-bar laser runner + keyboard breathing) |
| **Exit** | `⌘ Q` | Terminate app (automatically restores screen by default) |

### 🚀 Installation & Build

#### Requirements
* Apple Silicon Mac (M1/M2/M3/M4/M5 Series)
* macOS 14.0 or later

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

This project uses macOS private display and control interfaces. Provided "as-is" without warranties of any kind. The author assumes no liability for device anomalies or compatibility issues.
