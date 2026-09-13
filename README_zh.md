# MaskMac 🖥️

[English](README.md) | **简体中文**

---

**MaskMac** 是一个专为 Apple Silicon 设计的轻量级 macOS 菜单栏实用工具：

1. **Extend**：外接显示器不合盖时，一键安全关闭 MacBook 内建屏幕，专注大屏散热防伤屏；
2. **Duo**：开合 MacBook 屏幕时模拟双屏折叠设备的毛玻璃过渡特效；
3. **Brightness**：在菜单栏下方弹出精致紧凑的毛玻璃微浮窗，通过滑块实时拖拽调节 Mac 屏幕亮度与 MacBook 原生键盘背光（点击外部任意位置立即关闭）。

### 🌟 核心亮点

* 🔥 **开盖使用防止发热伤屏**：MacBook 在“物理合盖（Clamshell Mode）”高负荷运行时，机身热量会直接烘烤屏幕涂层与面板。开盖使用散热更好，有效保护屏幕寿命。
* ⌨️ **保留内置键盘与 Touch ID**：无需额外购置外接键盘、触控板，随时使用 Touch ID 指纹解锁。
* ☀️ **便捷亮度控制 (Brightness)**：点击状态栏 `Brightness`，无需进入系统设置即可通过滑块平滑调节内建屏幕与物理键盘背光亮度，点击外部一键收起。
* 🛡️ **防黑屏安全兜底**：拔掉外接显示器或退出应用时，自动点亮内屏，避免黑屏风险。

### ⌨️ 菜单与快捷操作

| 菜单项 | 快捷键 | 功能说明 |
| :--- | :---: | :--- |
| **Extend** | `⌘ D` | 切换内屏开启 / 关闭状态（只保留外接显示器） |
| **Duo** | — | 开关开合传感器磨砂过渡特效 |
| **Brightness** | `⌘ B` | 呼出紧凑毛玻璃浮窗，滑块调节屏幕与键盘亮度（点击外部自动收起） |
| **Exit** | `⌘ Q` | 退出 MaskMac（默认自动恢复内屏） |

### 🚀 安装与构建

#### 环境要求
* Apple Silicon Mac (M1/M2/M3/M4/M5 系列)
* macOS 14.0 或更高版本

#### 方式 1：直接下载预编译应用
前往 [Releases](../../releases) 下载最新的 `MaskMac-arm64.zip`，解压后拖入 `Applications` 文件夹即可。

#### 方式 2：从源码构建
```bash
git clone https://github.com/suennet2029/MaskMac.git
cd MaskMac
python3 build_app.py
```
构建产物位于 `dist/MaskMac.app`。

---

### 免责声明

本项目调用 macOS 私有显示与控制接口。软件按“原样”提供，作者不对任何设备异常或因硬件兼容性产生的问题承担责任。
