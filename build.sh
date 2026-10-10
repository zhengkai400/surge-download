#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
export PATH=/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin
export LC_ALL=en_US.UTF-8
APP="$PWD/build/疾风下载.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/engine"
mkdir -p .build
/usr/bin/python3 - <<'PY_OVERLAY'
import pathlib, json
p=pathlib.Path('.build').resolve()
(p/'empty.modulemap').write_text('// Hide obsolete duplicate module map for this build only.\n')
(p/'overlay.json').write_text(json.dumps({'version':0,'roots':[{'type':'file','name':'/Library/Developer/CommandLineTools/usr/include/swift/module.modulemap','external-contents':str(p/'empty.modulemap')}]}))
PY_OVERLAY
xcrun swiftc -vfsoverlay "$PWD/.build/overlay.json" -Xcc -ivfsoverlay -Xcc "$PWD/.build/overlay.json" -swift-version 5 -O -parse-as-library -framework SwiftUI -framework AppKit Sources/DHTBootstrap.swift Sources/LinkInput.swift Sources/Engine.swift Sources/App.swift -o "$APP/Contents/MacOS/SurgeDownload"
/usr/bin/python3 bundle_engine.py "$APP"
./bundle_bt.sh
.venv/bin/python bundle_video_licenses.py
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>SurgeDownload</string><key>CFBundleIdentifier</key><string>local.kai.surgedownload</string><key>CFBundleName</key><string>疾风下载</string><key>CFBundleDisplayName</key><string>疾风下载</string><key>CFBundleVersion</key><string>10</string><key>CFBundleShortVersionString</key><string>0.4.0</string><key>CFBundlePackageType</key><string>APPL</string><key>LSMinimumSystemVersion</key><string>15.0</string><key>NSHighResolutionCapable</key><true/><key>NSPrincipalClass</key><string>NSApplication</string><key>NSAppTransportSecurity</key><dict><key>NSAllowsLocalNetworking</key><true/></dict>
<key>CFBundleDocumentTypes</key><array><dict><key>CFBundleTypeName</key><string>BitTorrent</string><key>CFBundleTypeExtensions</key><array><string>torrent</string></array><key>CFBundleTypeRole</key><string>Viewer</string><key>LSHandlerRank</key><string>Alternate</string></dict></array>
<key>CFBundleURLTypes</key><array><dict><key>CFBundleURLName</key><string>BitTorrent Magnet</string><key>CFBundleURLSchemes</key><array><string>magnet</string></array><key>CFBundleTypeRole</key><string>Viewer</string></dict></array>
</dict></plist>
PLIST
xcrun swift -vfsoverlay "$PWD/.build/overlay.json" -Xcc -ivfsoverlay -Xcc "$PWD/.build/overlay.json" make_icon.swift "$PWD/.build/icon.png"
mkdir -p .build/AppIcon.iconset
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" .build/icon.png --out ".build/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" .build/icon.png --out ".build/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns .build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP/Contents/Info.plist"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"
echo "Built: $APP"
