# dsh-tray

Windows 系统托盘小工具，用于便捷地管理 [DeepSeek Harness](https://github.com/deepseek-ai/DeepSeek-Harness)（npm 包 [@deepseek-ai/dsh](https://www.npmjs.com/package/@deepseek-ai/dsh)，官方描述：*dsh CLI: profile boot, plugin management, and the browser UI alias*）的 Web 服务。

dsh 的 Web 界面默认运行在 `http://127.0.0.1:3080`。本工具把它从"终端里敲命令"变成**常驻托盘的开关 + 状态灯**：一键启动 / 停止服务，双击托盘图标用浏览器打开界面，图标颜色实时反映服务运行状态。

## 功能特性

- 🚀 **自动启动**：脚本运行后立即在后台（隐藏窗口）启动 `dsh web`，无需手动开终端；若 dsh 已在运行则不会重复启动，直接接管
- 🎛️ **托盘菜单**：重启 dsh / 停止 dsh / 退出
- 🔵 **状态指示灯**：启动时立即检测一次，此后每 2 秒用原生 socket 探测 3080 端口 —— 蓝色 = 运行中，灰色 = 已停止
- 🖱️ **双击打开**：双击托盘图标，用默认浏览器打开 dsh Web 界面
  - 默认浏览器是 Edge / Chrome 时，自动以 `--app` 应用模式打开（无地址栏，更像桌面应用）
  - 打开后按 `config.ini` 的 `[window]` 配置调整窗口位置/尺寸，未配置则最大化
- 🛑 **一键停止**：通过进程命令行特征定位并终止 dsh 的 node 进程；托盘退出时**不会**停止 dsh，服务保持后台运行
- ⚙️ **零配置定位 dsh**：自动查找 npm 全局安装的 `dsh.cmd`，找不到时回退到 `npx -y @deepseek-ai/dsh`

## 环境要求

| 依赖 | 说明 |
| --- | --- |
| [AutoHotkey v2](https://www.autohotkey.com/) | 运行托盘脚本 |
| [dsh](https://www.npmjs.com/package/@deepseek-ai/dsh) | 全局安装（`npm i -g @deepseek-ai/dsh`）或可被 npx 拉取；源码见 [deepseek-ai/deepseek-harness](https://github.com/deepseek-ai/DeepSeek-Harness)（CLI 在 `apps/cli`） |
| Windows | 脚本使用 WinSock 与进程管理 API |

## 使用方法

1. 安装 AutoHotkey v2（`dsh-tray.ahk` 首行有 `#Requires AutoHotkey v2.0` 校验）。
2. 全局安装 dsh：`npm i -g @deepseek-ai/dsh`（可选，未安装时会自动走 npx）。
3. 双击运行 `dsh-tray.ahk`（建议放入启动文件夹实现开机自启）。
4. 托盘出现鲸鱼图标后即可通过菜单 / 双击操作。

> 单独停止 dsh（不启动托盘）也可以命令行执行：
> ```powershell
> .\dsh-tray.ahk -stop
> ```

## 配置

脚本顶部常量可自行调整：

| 常量 | 默认值 | 说明 |
| --- | --- | --- |
| `DSH_PORT` | `3080` | dsh Web 服务端口（同时用于启动参数与运行检测） |
| `DSH_HOST` | `127.0.0.1` | 监听地址（同时用于启动参数与运行检测） |
| `ICON_ON` / `ICON_OFF` | `assets\whale-blue.ico` / `whale-gray.ico` | 运行 / 停止状态图标 |

双击打开时的窗口位置可选配置（脚本同目录 `config.ini`，未提供则最大化）：

```ini
[window]
x=100
y=100
w=1200
h=800
```

## 工作原理

- **状态检测**：`UpdateStatus` 在启动时立即执行一次、此后每 2 秒调用 `IsRunning()` —— 用 `ws2_32` socket 直连 `DSH_HOST:DSH_PORT`（地址由 `ParseAddr()` 从配置解析）探测端口连通性，纯 socket 不阻塞消息循环，状态变化时切换托盘图标。
- **启动**：先探测端口，已在运行则跳过；否则 `ResolveDshCmd()` 依次在 `%APPDATA%\npm`、`%LocalAppData%\npm` 下查找 `dsh.cmd`，都没有则使用 `npx -y @deepseek-ai/dsh`；以隐藏窗口方式运行 `dsh web --host 127.0.0.1 --port 3080`。
- **重启**：托盘菜单「重启 dsh」先走「停止」逻辑，再走「启动」逻辑，即停止一次后重新拉起服务。
- **停止**：`tools/stop-dsh.ps1` 遍历 node.exe 进程，按命令行匹配 `dsh\lib\bin.js` 或 `@deepseek-ai/dsh` 的特征强杀。
- **打开界面**：读取系统默认浏览器关联（`.html` 的 `UserChoice` ProgId），Edge/Chrome 走 `--app` 模式，其余直接 `Run` URL；随后按 `config.ini` 的 `[window]` 段定位浏览器窗口，读不到配置则最大化。

## 项目结构

```
dsh-tray/
├── dsh-tray.ahk        # 主程序（AutoHotkey v2，全部逻辑）
├── assets/             # 托盘图标（DeepSeek 鲸鱼，三色变体）
│   ├── whale-blue.ico  # 运行中
│   ├── whale-gray.ico  # 已停止
│   └── whale-black.ico # 备用
└── tools/
    ├── make-icons.mjs  # 用 sharp 从官方 favicon SVG 生成图标
    └── stop-dsh.ps1    # 停止 dsh 后台进程
```

### 重新生成图标

图标取自 dsh 官方 Web 前端的 favicon SVG，用 [sharp](https://sharp.pixelplumbing.com/) 渲染为多尺寸 ICO：

```powershell
npm i sharp   # 或设置 SHARP_PATH 指向已安装的 sharp
node tools/make-icons.mjs
```

## 常见问题

- **托盘图标一直灰色**：检查 dsh 是否已安装、3080 端口是否被占用，或看托盘提示"无法启动 dsh"中的命令是否可手动执行。
- **停止后图标未立即变灰**：状态轮询间隔为 2 秒，稍等片刻即可。
- **重复运行托盘脚本**：`#SingleInstance Force` 会用新实例替换旧实例，但托盘退出/重载时**不再**停止 dsh——服务保持运行，新实例检测到 3080 端口已被占用后直接接管（不会重复启动）。
