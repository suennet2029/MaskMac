# MaskMac 开发总结

## 1. 产品决策

MaskMac 采用手动模式：用户连接外接显示器后，从菜单栏手动执行“只保留外接显示器”；应用不再根据热插拔事件自动关闭内建显示器。这样可以避免扩展坞、KVM 和 WindowServer 在枚举期间造成误触发。

内屏关闭后，外接显示器全部消失时仍会自动恢复内屏，这是防黑屏保护，不属于自动切换功能。

## 2. 分层结构

```text
Sources/MaskMac/
├── App/AppMain.swift
├── Core/
│   ├── DisplayManager.swift
│   └── PrivateDisplayAPI.swift
├── UI/AppDelegate.swift
└── Support/Notifications.swift
```

- `App`：应用生命周期入口。
- `Core`：显示器枚举、状态维护、事务提交、防黑屏监测和私有 API 解析。
- `UI`：菜单栏、状态切换菜单、设置对话框。
- `Support`：模块间通知名称。

## 3. 手动显示切换

菜单项根据状态显示为：

- `只保留外接显示器`：内屏开启时显示；没有真实外接屏时置灰。
- `恢复内建显示器`：内屏关闭时显示，提供明确的手动恢复入口。

设置面板只保留一项高价值配置：

- `退出应用时恢复内建显示器（推荐）`，默认开启。

连接外接屏后的自动关闭开关和延迟设置已完全移除。

## 4. 安全和状态维护

- 关闭前要求至少存在一台真实外接显示器。
- 外接显示器使用物理尺寸及 vendor/model 信息过滤虚拟占位屏。
- 外接屏全部消失后恢复内屏；恢复失败会继续轮询，而不是停止保护。
- 显示器重新出现在活跃列表时，清除过期的 `InternalDisplayOff` 状态，避免菜单项消失。
- 配置事务任一步失败都会取消事务。
- 监听屏幕参数变化、Core Graphics 重配置回调和系统唤醒通知。

## 5. 构建产物

```text
dist/MaskMac.app
dist/MaskMac-arm64.zip
```

`.build/` 仅用于 SwiftPM 临时编译，`Resources/Source/` 保存图标源文件和中间产物，最终资源仅从 `Resources/` 根目录复制到应用包。

运行：

```bash
python3 build_app.py
```

脚本只使用 Python 标准库，完成 release 编译、应用组装、ad-hoc 签名和 arm64 压缩包生成。
