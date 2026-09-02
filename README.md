# ccBar

macOS 菜单栏 Token 用量监控工具，为 [CC Switch](https://github.com/nicepkg/ccswitch) 设计。

<img src="https://img.shields.io/badge/platform-macOS%2013%2B-blue" alt="macOS 13+"> <img src="https://img.shields.io/badge/language-Swift-orange" alt="Swift">

## 功能

- 📊 菜单栏实时显示今日 Token 总量
- 🤖 按模型拆分用量明细
- 📅 近 7 天 / 30 天 Token 汇总
- ⏱️ 自动计算今日工作时长
- ✨ 随机问候语，每次打开都有惊喜
- ⚙️ 可配置刷新间隔（5-3000 秒）和数据库路径
- 🚫 无 Dock 图标，纯菜单栏应用

## 安装

### 方式一：源码编译

```bash
git clone https://github.com/<your-username>/ccBar.git
cd ccBar
./install.sh
```

需要 Xcode Command Line Tools（`xcode-select --install`）。

### 方式二：直接下载

从 [Releases](https://github.com/<your-username>/ccBar/releases) 下载 `ccBar.app`，拖入 `/Applications` 即可。

## 使用

启动后菜单栏右侧会出现数字，即今日 Token 总量。点击可查看：

```
✨ 冲冲冲！· 5.3h
───────────────────
🚀 今日请求    42 次
💎 今日 Token    18万
───────────────────
🤖 模型明细
  mimo-v2.5-pro    15万 · 30次
  claude-opus-5    3万 · 12次
───────────────────
📅 近7天 Token    120万 · 300次
📅 近30天 Token    500万 · 1200次
───────────────────
🔄 刷新
⚙️ 设置
退出
```

### 设置

| 选项 | 说明 | 默认值 |
|------|------|--------|
| 刷新间隔 | 自动刷新周期（秒） | 30 |
| 数据库路径 | CC Switch 数据库位置 | `~/.cc-switch/cc-switch.db` |

### 开机自启

```bash
osascript -e 'tell application "System Events" to make login item at end with properties {path:"/Applications/ccBar.app", hidden:true}'
```

## 项目结构

```
ccBar/
├── main.swift      # 主程序（菜单栏 + 设置窗口 + SQLite 查询）
├── gen_icon.py     # 图标生成脚本
├── install.sh      # 编译、打包、安装一键脚本
└── README.md
```

## 数据来源

ccBar 读取 CC Switch 的 SQLite 数据库，包含两张表：

- `proxy_request_logs` — 原始请求日志（实时数据）
- `usage_daily_rollups` — 每日聚合数据（历史数据）

## 系统要求

- macOS 13.0+
- Swift 5.9+（Xcode 15+）

## License

MIT
