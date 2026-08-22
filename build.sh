#!/bin/bash
# 构建链：源码 → swift build release → 组装 .app → 固定本地证书签名（TCC 权限稳定性，设计 §五.3）
set -euo pipefail
cd "$(dirname "$0")"
ROOT="$(pwd)"

swift build -c release --package-path 源码

APP="构建/TabType.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "源码/.build/release/TabType" "$APP/Contents/MacOS/TabType"

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key>
	<string>TabType</string>
	<key>CFBundleIdentifier</key>
	<string>com.zhangweijian.tabtype</string>
	<key>CFBundleName</key>
	<string>TabType</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>0.1.0</string>
	<key>LSMinimumSystemVersion</key>
	<string>13.0</string>
	<key>LSUIElement</key>
	<true/>
	<key>NSHumanReadableCopyright</key>
	<string>CmdTap 复现（个人使用）</string>
</dict>
</plist>
EOF

codesign --force --sign "CmdTap2 Local Dev" "$APP"

# 冒烟（设计 §七.4：产物可运行性——能启动、能自查架构）
echo "构建产物: $APP"
file "$APP/Contents/MacOS/TabType" | grep -q "arm64" && echo "架构: arm64 原生 ✓"
plutil -lint "$APP/Contents/Info.plist" >/dev/null && echo "Info.plist 合法 ✓"
codesign --verify "$APP" && echo "签名 ✓"
