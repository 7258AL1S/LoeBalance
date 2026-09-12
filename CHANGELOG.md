# Changelog

## 0.2.0 - 2026-09-13

- 新增 Windows 版（.NET 8 / WPF，独立于 macOS 实现，源码位于 `windows/`）：托盘图标与右键菜单、任务栏余额读数、桌面卡片、登录与设置窗口、单实例运行。
- 新增 Windows Credential Manager 凭据保存（仅 refresh token 与 user id）、`%LOCALAPPDATA%\LoeBalance` 设置与快照存储（原子写入）、网络恢复与系统唤醒刷新、开机启动注册。
- 新增 Windows 安装包（win-x64 / win-x86，按用户安装、无需管理员权限）与统一的 Release 流水线，一次发布 macOS 与 Windows 四个包。
- macOS 应用代码与 0.1.1 相同，本次仅同步版本号。

## 0.1.1 - 2026-09-12

- 增加可复现的双架构发布脚本。
- 同时发布 Intel Mac（`x86_64`）和 Apple Silicon（`arm64`）安装包。

## 0.1.0 - 2026-09-12

- 增加 macOS 桌面余额卡片和菜单栏余额显示。
- 增加消费红字、充值数字和高频念珠式上浮动画。
- 增加桌面卡片震动关闭、弱、强三档设置。
- 增加自定义刷新间隔，最低支持 1 秒。
- 增加 Keychain 凭据保存、Token 自动刷新和退出登录。
- 增加网络恢复、系统唤醒、限流退避和缓存恢复处理。
- 增加 SwiftPM 构建脚本、独立测试 harness 和 Intel Mac 发布包。
