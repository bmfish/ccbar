#!/bin/bash
# 重新编译并安装 ccBar
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"

pkill -f ccswitch-bar 2>/dev/null; sleep 0.5

echo "🔨 编译..."
swiftc -O -o ccswitch-bar main.swift -framework AppKit -lsqlite3

echo "🎨 生成图标..."
python3 gen_icon.py
iconutil -c icns /tmp/ccBar.iconset -o ccBar.icns

APP="/Applications/ccBar.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ccswitch-bar "$APP/Contents/MacOS/"
cp ccBar.icns "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>ccswitch-bar</string>
    <key>CFBundleIdentifier</key><string>com.ccbar.app</string>
    <key>CFBundleName</key><string>ccBar</string>
    <key>CFBundleDisplayName</key><string>ccBar</string>
    <key>CFBundleIconFile</key><string>ccBar</string>
    <key>CFBundleVersion</key><string>1.0</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
EOF

open "$APP"
echo "✅ 安装完成: $APP"
