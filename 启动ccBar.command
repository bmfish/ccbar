#!/bin/bash
# 启动ccBar脚本

# 复制到Applications
cp -R /Users/caozhiyu/bm/workspace/bm-note/ccswitch-menubar/ccBar.app /Applications/

# 移除隔离属性
sudo xattr -r -d com.apple.quarantine /Applications/ccBar.app 2>/dev/null

# 启动应用
open /Applications/ccBar.app

echo "ccBar 已启动！"
