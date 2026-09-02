#!/bin/bash

clear
echo ""
echo "  ┌─────────────────────────────────────────────┐"
echo "  │                                             │"
echo "  │     ccBar.app 修复工具 v2                   │"
echo "  │                                             │"
echo "  └─────────────────────────────────────────────┘"
echo ""

# 检查 app 是否已安装
if [ ! -d "/Applications/ccBar.app" ]; then
    echo "  ❌ 未找到 /Applications/ccBar.app"
    echo ""
    echo "  请先将 ccBar.app 拖入"应用程序"文件夹"
    echo "  然后重新运行此脚本"
    echo ""
    read -p "  按回车键退出..."
    exit 1
fi

echo "  正在修复..."
echo "  可能需要输入密码（输入时不显示字符）"
echo ""

# 方法1: 移除隔离属性
sudo xattr -r -d com.apple.quarantine /Applications/ccBar.app 2>/dev/null

# 方法2: 添加到 Gatekeeper 白名单
sudo spctl --add /Applications/ccBar.app 2>/dev/null
sudo spctl --enable --label ccBar /Applications/ccBar.app 2>/dev/null

# 方法3: 强制信任
sudo xattr -cr /Applications/ccBar.app 2>/dev/null

echo ""
echo "  ✅ 修复完成！"
echo ""
echo "  请按以下步骤操作："
echo "  ─────────────────────────────────────────"
echo "  1. 关闭此终端窗口"
echo "  2. 打开"系统设置" → "隐私与安全性""
echo "  3. 找到 ccBar，点击"仍要打开""
echo "  4. 或者直接在"启动台"中点击 ccBar 图标"
echo ""
echo "  如果还不行，请在终端执行："
echo "  sudo xattr -cr /Applications/ccBar.app && open /Applications/ccBar.app"
echo ""
read -p "  按回车键退出..."
