#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
export MACOSX_DEPLOYMENT_TARGET=14.0
app_version="$(< VERSION)"
if [[ ! "$app_version" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]]; then
    print -u2 "VERSION 형식이 올바르지 않습니다."
    exit 1
fi
cargo build --release --locked --manifest-path core/Cargo.toml
cmake -S resources/vendor/mediaremote-adapter -B build/mediaremote -DCMAKE_BUILD_TYPE=Release
cmake --build build/mediaremote --target MediaRemoteAdapter
bundle="$PWD/build/.rium-stage-$$"
destination="${RIUM_APP_DESTINATION:-${PWD:h}/Rium Notch.app}"
previous="$PWD/build/.rium-previous-$$"
signing_identity="${RIUM_SIGNING_IDENTITY:--}"
cleanup() {
    if [[ ! -e "$destination" && -e "$previous" ]]; then mv "$previous" "$destination"; fi
    if [[ -d "$bundle" ]]; then rm -rf "$bundle"; fi
}
trap cleanup EXIT
if ps -axo comm= | rg -F -- "$destination/Contents/MacOS/" >/dev/null; then
    print -u2 "Rium Notch가 실행 중입니다. 종료한 다음 다시 빌드해 주세요."
    exit 1
fi
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
swiftc -O -target arm64-apple-macosx14.0 mac/main.swift mac/NotchLight.swift mac/MemoryPressure.swift mac/Agenda.swift mac/AirDropMonitor.swift mac/ScreenshotMonitor.swift mac/Dictation.swift mac/Teleprompter.swift mac/Power.swift mac/Settings.swift mac/HomeCustomization.swift mac/Updater.swift mac/TimerNotifications.swift mac/WeatherLocation.swift mac/AudioOutput.swift core/target/release/librium_notch_core.a -o "$bundle/Contents/MacOS/RiumNotch" -framework AppKit -framework SwiftUI -framework Security -framework EventKit -framework CoreLocation -framework UniformTypeIdentifiers -framework AVFoundation -framework Speech -framework ApplicationServices -framework IOKit -framework CoreAudio -framework ServiceManagement -framework CoreServices -framework UserNotifications
cp core/target/release/rium-notch-core "$bundle/Contents/MacOS/rium-notch-core"
cp resources/AppIcon.icns "$bundle/Contents/Resources/AppIcon.icns"
cp LICENSE THIRD_PARTY_NOTICES.md "$bundle/Contents/Resources/"
mkdir -p "$bundle/Contents/Resources/mediaremote-adapter"
cp resources/vendor/mediaremote-adapter/bin/mediaremote-adapter.pl "$bundle/Contents/Resources/mediaremote-adapter/"
cp resources/vendor/mediaremote-adapter/LICENSE "$bundle/Contents/Resources/mediaremote-adapter/"
ditto build/mediaremote/MediaRemoteAdapter.framework "$bundle/Contents/Resources/mediaremote-adapter/MediaRemoteAdapter.framework"
cat > "$bundle/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>app.rium.notch</string>
<key>CFBundleName</key><string>Rium Notch</string>
<key>CFBundleDisplayName</key><string>Rium Notch</string>
<key>CFBundleExecutable</key><string>RiumNotch</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.0.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSCalendarsFullAccessUsageDescription</key><string>노치에서 예정된 일정을 표시합니다.</string>
<key>NSRemindersFullAccessUsageDescription</key><string>노치에서 미완료 미리 알림을 표시합니다.</string>
<key>NSDownloadsFolderUsageDescription</key><string>AirDrop으로 받은 파일을 보관함에 표시합니다.</string>
<key>NSDesktopFolderUsageDescription</key><string>스크린샷을 보관함에 표시합니다.</string>
<key>NSLocationUsageDescription</key><string>현재 위치의 날씨를 표시합니다.</string>
<key>NSLocationWhenInUseUsageDescription</key><string>현재 위치의 날씨를 표시합니다.</string>
<key>NSMicrophoneUsageDescription</key><string>설정한 단축키를 누르는 동안 음성을 받아쓰기 위해 마이크를 사용합니다.</string>
<key>NSSpeechRecognitionUsageDescription</key><string>말씀한 내용을 기기 내 음성 인식으로 텍스트로 변환합니다.</string>
</dict></plist>
PLIST
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $app_version" "$bundle/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $app_version" "$bundle/Contents/Info.plist"
codesign --force --sign "$signing_identity" "$bundle/Contents/MacOS/rium-notch-core"
codesign --force --sign "$signing_identity" "$bundle"
codesign --verify --deep --strict "$bundle"
if ps -axo comm= | rg -F -- "$destination/Contents/MacOS/" >/dev/null; then
    print -u2 "Rium Notch가 실행 중입니다. 종료한 다음 다시 빌드해 주세요."
    exit 1
fi
if [[ -e "$destination" ]]; then
    if [[ ! -f "${PWD:h}/Rium Notch 기존 동작 백업.zip" ]]; then
        print -u2 "기존 앱 백업을 확인할 수 없어 교체하지 않았습니다."
        exit 1
    fi
    mv "$destination" "$previous"
fi
if ! mv "$bundle" "$destination"; then
    [[ ! -e "$previous" ]] || mv "$previous" "$destination"
    exit 1
fi
if ! codesign --verify --deep --strict "$destination"; then
    rm -rf "$destination"
    [[ ! -e "$previous" ]] || mv "$previous" "$destination"
    exit 1
fi
[[ ! -e "$previous" ]] || rm -rf "$previous"
print "완료: $destination"
