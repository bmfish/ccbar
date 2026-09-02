#!/bin/bash

clear
echo ""
echo "  ┌─────────────────────────────────────────────┐"
echo "  │     ccBar.app 一键启动                      │"
echo "  └─────────────────────────────────────────────┘"
echo ""

# 获取脚本所在目录
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# 杀掉可能卡住的进程
pkill -f ccswitch-bar 2>/dev/null

# 移除隔离属性
xattr -cr "$SCRIPT_DIR/ccBar.app" 2>/dev/null

echo "  正在启动 ccBar..."
echo ""

# 直接启动 DMG 里的 app
open "$SCRIPT_DIR/ccBar.app"

sleep 2

# 检查是否启动成功
if pgrep -f ccswitch-bar > /dev/null; then
    echo "  ✅ ccBar 已启动！"
    echo ""
    echo "  请查看菜单栏右上角 ⚡ 图标"
else
    echo "  ⚠️  正在尝试备用方式..."
    "$SCRIPT_DIR/ccBar.app/Contents/MacOS/ccswitch-bar" &
    sleep 1
    echo "  ✅ 已启动"
fi

echo ""
echo "  可以关闭此窗口了"
echo ""
read -p "  按回车键退出..."
