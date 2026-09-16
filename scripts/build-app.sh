#!/bin/bash
# MiniME 构建脚本:swift build → 生成图标 → 组装 MiniME.app → ad-hoc 签名
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> swift build (release)"
swift build -c release

echo "==> 生成应用图标 (iconset → icns)"
swift scripts/generate-icon.swift
iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns

APP="build/MiniME.app"
echo "==> 组装 $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>MiniME</string>
    <key>CFBundleIdentifier</key>
    <string>com.minime.app</string>
    <key>CFBundleName</key>
    <string>MiniME</string>
    <key>CFBundleDisplayName</key>
    <string>MiniME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.2</string>
    <key>CFBundleVersion</key>
    <string>26w38a</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>NSHumanReadableCopyright</key>
    <string>铃一贰叁 制作</string>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleLocalizations</key>
    <array>
        <string>en</string>
        <string>zh-Hans</string>
    </array>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
PLIST

cp .build/release/MiniME "$APP/Contents/MacOS/MiniME"
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

echo "==> 拷贝本地化资源 (*.lproj)"
for lproj in Resources/*.lproj; do
    cp -R "$lproj" "$APP/Contents/Resources/"
    echo "    $(basename "$lproj")"
done

echo "==> 拷贝更新日志 (*.txt)"
for changelog in changelogen.txt changelogzh.txt; do
    if [ -f "$changelog" ]; then
        cp "$changelog" "$APP/Contents/Resources/"
        echo "    $changelog"
    fi
done

echo "==> ad-hoc 签名"
codesign --force --sign - "$APP"

echo "==> 完成:$(pwd)/$APP"
echo "    可执行: open $(pwd)/$APP"
