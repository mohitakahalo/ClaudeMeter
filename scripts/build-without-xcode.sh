#!/bin/bash
# Build ClaudeMeter.app + ClaudeMeter.dmg with Command Line Tools ONLY (no Xcode).
set -euo pipefail

SCRATCH="/private/tmp/claude-501/-Users-mohitsrivastava-Workspace/bf7a3614-1f52-4871-8441-2df7c527b5d0/scratchpad"
SRCROOT="$SCRATCH/cm"                 # upstream clone (read-only)
WORK="$SCRATCH/pacebuild"            # build workspace
STAGE="$WORK/stage"                   # SwiftPM package staging
APPVER="${APPVER:-1.4.2}"
BUILDVER="${BUILDVER:-1}"

rm -rf "$STAGE"
mkdir -p "$STAGE/Sources"

# ---------------------------------------------------------------- 1. sources
cp -R "$SRCROOT/ClaudeMeter" "$STAGE/Sources/ClaudeMeter"
# Assets.xcassets needs actool (Xcode-only) -> handled separately as .icns.
# Resources/{Info.plist,ClaudeMeter.entitlements} are vestigial in this project
# (no INFOPLIST_FILE / CODE_SIGN_ENTITLEMENTS build setting references them).
rm -rf "$STAGE/Sources/ClaudeMeter/Assets.xcassets" \
       "$STAGE/Sources/ClaudeMeter/Resources"

# Strip #Preview macros (PreviewsMacros plugin ships only inside Xcode.app).
python3 "$SCRATCH/buildprobe/strip_previews.py" "$STAGE/Sources/ClaudeMeter"

cat > "$STAGE/Package.swift" <<'EOF'
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClaudeMeter",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ClaudeMeter", targets: ["ClaudeMeter"])
    ],
    dependencies: [
        .package(url: "https://github.com/steipete/SweetCookieKit", exact: "0.4.1")
    ],
    targets: [
        .executableTarget(
            name: "ClaudeMeter",
            dependencies: [
                .product(name: "SweetCookieKit", package: "SweetCookieKit")
            ],
            path: "Sources/ClaudeMeter",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
EOF

# ---------------------------------------------------------------- 2. compile
cd "$STAGE"
swift build -c release
BIN="$(swift build -c release --show-bin-path)/ClaudeMeter"

# ---------------------------------------------------------------- 3. icon
ICONSET="$WORK/AppIcon.iconset"
ASRC="$SRCROOT/ClaudeMeter/Assets.xcassets/AppIcon.appiconset"
rm -rf "$ICONSET"; mkdir -p "$ICONSET"
cp "$ASRC/16-mac.png"   "$ICONSET/icon_16x16.png"
cp "$ASRC/32-mac.png"   "$ICONSET/icon_16x16@2x.png"
cp "$ASRC/32-mac.png"   "$ICONSET/icon_32x32.png"
cp "$ASRC/64-mac.png"   "$ICONSET/icon_32x32@2x.png"
cp "$ASRC/128-mac.png"  "$ICONSET/icon_128x128.png"
cp "$ASRC/256-mac.png"  "$ICONSET/icon_128x128@2x.png"
cp "$ASRC/256-mac.png"  "$ICONSET/icon_256x256.png"
cp "$ASRC/512-mac.png"  "$ICONSET/icon_256x256@2x.png"
cp "$ASRC/512-mac.png"  "$ICONSET/icon_512x512.png"
cp "$ASRC/1024-mac.png" "$ICONSET/icon_512x512@2x.png"
# The catalog's "*.png" files are actually WebP; iconutil rejects them.
for f in "$ICONSET"/*.png; do sips -s format png "$f" --out "$f" >/dev/null; done
iconutil --convert icns --output "$WORK/AppIcon.icns" "$ICONSET"

# ---------------------------------------------------------------- 4. bundle
APP="$WORK/out/ClaudeMeter.app"
rm -rf "$WORK/out"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/ClaudeMeter"
cp "$WORK/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>          <string>en</string>
	<key>CFBundleDisplayName</key>                <string>ClaudeMeter</string>
	<key>CFBundleExecutable</key>                 <string>ClaudeMeter</string>
	<key>CFBundleIconFile</key>                   <string>AppIcon</string>
	<key>CFBundleIdentifier</key>                 <string>com.eddmann.ClaudeMeter</string>
	<key>CFBundleInfoDictionaryVersion</key>      <string>6.0</string>
	<key>CFBundleName</key>                       <string>ClaudeMeter</string>
	<key>CFBundlePackageType</key>                <string>APPL</string>
	<key>CFBundleShortVersionString</key>         <string>$APPVER</string>
	<key>CFBundleVersion</key>                    <string>$BUILDVER</string>
	<key>CFBundleSupportedPlatforms</key>         <array><string>MacOSX</string></array>
	<key>LSApplicationCategoryType</key>          <string>public.app-category.utilities</string>
	<key>LSMinimumSystemVersion</key>             <string>14.0</string>
	<key>LSUIElement</key>                        <true/>
	<key>NSHumanReadableCopyright</key>           <string>Copyright © 2025. All rights reserved.</string>
	<key>NSSupportsAutomaticTermination</key>     <true/>
	<key>NSSupportsSuddenTermination</key>        <false/>
	<key>NSUserNotificationsUsageDescription</key><string>ClaudeMeter sends notifications to alert you when your Claude.ai usage approaches threshold limits (warning and critical levels) and when your usage session resets.</string>
</dict>
</plist>
EOF
plutil -lint "$APP/Contents/Info.plist"

# ---------------------------------------------------------------- 5. sign
cat > "$WORK/ClaudeMeter.entitlements" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.network.client</key>                    <true/>
	<key>com.apple.security.files.user-selected.read-only</key>     <true/>
</dict>
</plist>
EOF
codesign --force --sign - --options runtime --timestamp=none \
         --entitlements "$WORK/ClaudeMeter.entitlements" "$APP"
codesign --verify --strict --verbose=2 "$APP"

# ---------------------------------------------------------------- 6. dmg
DMGROOT="$WORK/dmgroot"
rm -rf "$DMGROOT"; mkdir -p "$DMGROOT"
cp -R "$APP" "$DMGROOT/"
ln -s /Applications "$DMGROOT/Applications"
rm -f "$WORK/out/ClaudeMeter-pace-$APPVER.dmg"
hdiutil create -volname "ClaudeMeter" -srcfolder "$DMGROOT" -ov \
               -fs HFS+ -format UDZO -imagekey zlib-level=9 \
               "$WORK/out/ClaudeMeter-pace-$APPVER.dmg"

echo "=== DONE ==="
echo "APP: $APP"
echo "DMG: $WORK/out/ClaudeMeter-pace-$APPVER.dmg"
