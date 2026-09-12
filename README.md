# LoeBalance

LoeBalance 是一个面向 [Sub2API](https://api.loe.cx/) 的非官方 macOS 余额小组件。它同时在桌面卡片和菜单栏中显示账户余额，并在产生消费时用类似游戏“掉血”的数字动画展示余额变化。

## 功能

- 桌面常驻余额卡片，显示当前余额、今日消费、今日请求数和连接状态。
- 菜单栏余额显示，不需要打开浏览器仪表盘。
- 消费时显示红色扣费数字，支持高频、单轨、念珠式连续上浮。
- 充值时显示正向余额变化。
- 桌面卡片震动可选关闭、弱、强；菜单栏余额本身不会抖动。
- 30 秒、1 分钟、5 分钟刷新预设，以及最低 1 秒的自定义刷新间隔。
- 网络恢复、系统唤醒和手动刷新时触发即时更新。
- 支持开机启动、桌面卡片显示开关和退出登录。

## 系统要求

- macOS 13 Ventura 或更高版本。
- 当前发布包同时提供 Intel Mac（`x86_64`）和 Apple Silicon（`arm64`）版本。
- 有效的 Sub2API 账户。

## 安装

1. 从 GitHub Releases 下载与你的 Mac 芯片匹配的安装包：`x86_64` 对应 Intel，`arm64` 对应 Apple Silicon。
2. 解压后将 `LoeBalance.app` 移入“应用程序”文件夹。
3. 首次启动时，若 macOS 阻止打开，请在 Finder 中右键应用并选择“打开”。
4. 使用 Sub2API 邮箱和密码登录。

当前发布包采用临时签名，尚未使用 Apple Developer ID 签名或公证，因此 Gatekeeper 可能显示安全提示。

## 设置

点击菜单栏中的 LoeBalance 区域可打开菜单和设置：

- `Shake`：选择桌面卡片扣费时的震动强度。
- `Refresh`：选择预设刷新频率，或选择 `Custom` 输入秒数并应用；最小值为 1 秒。
- `Show Desktop Card`：显示或隐藏桌面卡片。
- `Launch at Login`：控制登录 macOS 后自动启动。

过短的刷新间隔会增加 API 请求频率。遇到服务端限流时，应用会遵守 `Retry-After` 并延后请求。

## 隐私与凭据

- 密码只用于登录请求，不会写入磁盘。
- Access Token 仅保存在应用进程内存中。
- Refresh Token 使用 macOS Keychain 保存，并设置为仅限当前设备使用。
- 日志不会主动记录密码、Token 或 Authorization 请求头。

## 从源码构建

项目使用 Swift Package Manager，主程序是 AppKit/SwiftUI 混合的菜单栏应用。

```bash
git clone https://github.com/7258AL1S/LoeBalance.git
cd LoeBalance
./script/build_and_run.sh --verify
```

构建后的应用位于 `dist/LoeBalance.app`。也可以只编译：

```bash
swift build
```

生成两个架构的发布包：

```bash
./script/package_release.sh 0.1.0
```

发布包会写入 `outputs/`，分别为 `LoeBalance-macOS-x86_64.zip` 和 `LoeBalance-macOS-arm64.zip`。

运行 XCTest 需要完整 Xcode 工具链：

```bash
swift test
```

仓库中的 `.superpowers/sdd/.../harnesses` 还包含无需 XCTest 的独立回归测试，用于验证刷新调度、动画、桌面卡片、菜单栏和应用生命周期。

## 项目结构

```text
Sources/LoeBalance/
  Animation/       扣费与充值动画
  App/             应用入口和生命周期
  Auth/            登录、Token 刷新和 Keychain
  DesktopCard/     桌面卡片
  Networking/      Sub2API 请求与响应解析
  Persistence/     偏好和缓存
  Refresh/         余额刷新、调度和消费记录对账
  Settings/        登录与设置窗口
  StatusBar/       菜单栏界面
Tests/             XCTest 测试
script/            构建、打包和运行脚本
docs/              设计与实施文档
```

## 说明

本项目不是 Sub2API 官方客户端。API 结构或服务端行为发生变化时，应用可能需要同步更新。
