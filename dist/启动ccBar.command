#!/bin/bash

clear
echo ""
echo "  ┌─────────────────────────────────────────────┐"
echo "  │     ccBar.app 安装并启动                    │"
echo "  └─────────────────────────────────────────────┘"
echo ""

# 获取脚本所在目录
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# 杀掉可能卡住的进程
pkill -f ccswitch-bar 2>/dev/null

# 复制到 Applications（覆盖旧版本）
echo "  正在安装到 /Applications..."
rm -rf /Applications/ccBar.app
cp -R "$SCRIPT_DIR/ccBar.app" /Applications/

# 移除隔离属性
xattr -cr /Applications/ccBar.app 2>/dev/null

echo "  ✅ 安装完成"
echo ""

# 启动
echo "  正在启动 ccBar..."
open /Applications/ccBar.app

sleep 2

if pgrep -f ccswitch-bar > /dev/null; then
    echo "  ✅ ccBar 已启动！"
    echo "  菜单栏右上角 ⚡ 图标"
else
    echo "  ⚠️  尝试备用方式..."
    /Applications/ccBar.app/Contents/MacOS/ccswitch-bar &
    sleep 1
    echo "  ✅ 已启动"
fi

echo ""
echo "  以后在启动台或应用程序中直接打开 ccBar 即可"
echo ""
read -p "  按回车键退出..."
