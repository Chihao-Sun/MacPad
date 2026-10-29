#!/bin/zsh
set -euo pipefail
root="${0:A:h:h}"
cd "$root"
version=$(cat VERSION)
destination="${MACPAD_DIST_DIR:-$root/.build/Release.noindex/$version}"
bundle="$destination/MacPad.app"
mkdir -p .build "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
export CLANG_MODULE_CACHE_PATH="$root/.build/ModuleCache"
build=$(( $(cat BUILD 2>/dev/null || echo 0) + 1 ))
echo "$build" > BUILD
xcrun clang -fobjc-arc -mmacosx-version-min=14.0 -c Sources/Bridge.m -o .build/Bridge.o
xcrun swiftc -O -module-cache-path "$CLANG_MODULE_CACHE_PATH" -swift-version 5 -parse-as-library -target arm64-apple-macosx14.0 -module-name MacPad -import-objc-header Sources/Bridge.h Sources/ConnectionPolicy.swift Sources/MacPad.swift .build/Bridge.o -framework AppKit -framework SwiftUI -framework Foundation -framework ServiceManagement -framework IOKit -framework CoreGraphics -o "$bundle/Contents/MacOS/MacPad"
for resource in MacPad.icns MacPadIcon.png MacPadMenuBar@1x.png MacPadMenuBar@2x.png MacPadMenuBar@3x.png; do
    cp "Resources/$resource" "$bundle/Contents/Resources/$resource"
done
cat > "$bundle/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.chihao.MacPad</string>
<key>CFBundleName</key><string>MacPad</string>
<key>CFBundleDisplayName</key><string>MacPad</string>
<key>CFBundleExecutable</key><string>MacPad</string>
<key>CFBundleShortVersionString</key><string>$version</string>
<key>CFBundleVersion</key><string>$build</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleIconFile</key><string>MacPad.icns</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
EOF
codesign --force --sign - "$bundle"
echo "Built MacPad $version ($build): $bundle"
