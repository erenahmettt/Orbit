#!/bin/zsh
# Orbit.app paketini oluşturur.
#   ./build.sh           → build.noindex/Orbit.app
#   ./build.sh install   → derler, açık Orbit'i kapatır, /Applications'a kurar ve açar
# Çıktı ".noindex" klasörüne gider; böylece Spotlight/Launchpad'de ikinci bir Orbit görünmez.
set -e
cd "$(dirname "$0")"

swift build -c release
OUT=build.noindex
APP=$OUT/Orbit.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Orbit "$APP/Contents/MacOS/Orbit"

# İkon
if [ ! -f $OUT/AppIcon.icns ]; then
  swift scripts/make_icon.swift $OUT/AppIcon.iconset
  iconutil -c icns $OUT/AppIcon.iconset -o $OUT/AppIcon.icns
  rm -rf $OUT/AppIcon.iconset
fi
cp $OUT/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Orbit</string>
  <key>CFBundleDisplayName</key><string>Orbit</string>
  <key>CFBundleIdentifier</key><string>local.orbit.workspace</string>
  <key>CFBundleExecutable</key><string>Orbit</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSCalendarsFullAccessUsageDescription</key><string>Orbit, Mac takvimindeki etkinlikleri kendi takviminde göstermek için erişim ister.</string>
  <key>CFBundleURLTypes</key>
  <array><dict>
    <key>CFBundleURLName</key><string>local.orbit.workspace</string>
    <key>CFBundleURLSchemes</key><array><string>orbit</string></array>
  </dict></array>
  <key>NSCalendarsUsageDescription</key><string>Orbit, Mac takvimindeki etkinlikleri kendi takviminde göstermek için erişim ister.</string>
</dict>
</plist>
PLIST

# Masaüstü widget uzantısı
WX="$APP/Contents/PlugIns/OrbitWidget.appex"
mkdir -p "$WX/Contents/MacOS"
xcrun swiftc -O -parse-as-library -application-extension \
  -target "$(uname -m)-apple-macos15.0" -sdk "$(xcrun --show-sdk-path --sdk macosx)" \
  -module-name OrbitWidget \
  Widget/OrbitWidget.swift Sources/Orbit/Shared/WidgetSnapshot.swift \
  -framework WidgetKit -framework SwiftUI \
  -o "$WX/Contents/MacOS/OrbitWidget"
cat > "$WX/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>OrbitWidget</string>
  <key>CFBundleDisplayName</key><string>Orbit</string>
  <key>CFBundleIdentifier</key><string>local.orbit.workspace.widget</string>
  <key>CFBundleExecutable</key><string>OrbitWidget</string>
  <key>CFBundlePackageType</key><string>XPC!</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>NSExtension</key>
  <dict>
    <key>NSExtensionPointIdentifier</key><string>com.apple.widgetkit-extension</string>
  </dict>
</dict>
</plist>
PLIST

# Önce uzantı (sandbox yetkileriyle), sonra uygulama imzalanır; --deep uzantının yetkilerini silerdi
codesign --force --sign - --entitlements Widget/OrbitWidget.entitlements "$WX"
codesign --force --sign - "$APP"

if [ "$1" = "install" ]; then
  osascript -e 'quit app "Orbit"' 2>/dev/null || true
  sleep 1
  rm -rf /Applications/Orbit.app
  cp -R "$APP" /Applications/
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/Orbit.app
  pluginkit -a /Applications/Orbit.app/Contents/PlugIns/OrbitWidget.appex 2>/dev/null || true
  open /Applications/Orbit.app
  echo "✅ Orbit /Applications'a kuruldu ve açıldı."
else
  echo "✅ $APP hazır. Kurmak için: ./build.sh install"
fi
