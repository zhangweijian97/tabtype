#!/bin/bash
# 构建链：swift build release → 组装 .app → 签名（本地证书优先，缺失回退 ad-hoc）
set -euo pipefail
cd "$(dirname "$0")"
ROOT="$(pwd)"

swift build -c release

APP="TabType.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/release/TabType" "$APP/Contents/MacOS/TabType"

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
	<string>0.3.0</string>
	<key>LSMinimumSystemVersion</key>
	<string>13.0</string>
	<key>LSUIElement</key>
	<true/>
	<key>NSHumanReadableCopyright</key>
	<string>Copyright (c) 2026 zhangweijian97 (MIT License)</string>
</dict>
</plist>
EOF

# 本地开发证书（TCC 权限随重编译不丢）优先；外部环境无此证书时回退 ad-hoc 签名
if security find-identity -v -p codesigning 2>/dev/null | grep -q "CmdTap2 Local Dev"; then
	codesign --force --sign "CmdTap2 Local Dev" "$APP"
else
	codesign --force --sign - "$APP"
fi

echo "构建产物: $APP"
file "$APP/Contents/MacOS/TabType" | grep -q "arm64" && echo "架构: arm64 原生 ✓"
plutil -lint "$APP/Contents/Info.plist" >/dev/null && echo "Info.plist 合法 ✓"
codesign --verify "$APP" && echo "签名 ✓"
