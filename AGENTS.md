# Extend 显示事务

- 不要向内屏启停事务添加 `CGConfigureDisplayFadeEffect`。2026-09-13 在本机验证：设置效果返回成功，但提交返回 `kCGErrorNotImplemented`（1006）；不添加效果的事务正常。
- 显示接口的兼容性必须验证到 `CGCompleteDisplayConfiguration` 提交结果；符号存在、设置成功或状态单元测试通过，都不代表硬件切换成功。
- 修改底层切屏事务后，在具备内屏与物理外屏的环境中验证关闭和恢复，并在结束时确认内屏恢复。单独标明实机验证与纯状态测试的结果，不把状态确认耗时等同于视觉过渡耗时。
- 不触发实际切屏的状态测试：`sh Tests/run_tests.sh`。
