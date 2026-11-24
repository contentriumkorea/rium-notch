#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
export MACOSX_DEPLOYMENT_TARGET=14.0
# CLT's macOS 27 SDK can omit SwiftUIMacros; keep an explicitly selected SDK.
if [[ -z "${SDKROOT:-}" ]]; then
    current_sdk="$(xcrun --show-sdk-path)"
    fallback_sdk=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
    if [[ "${current_sdk:A}" == /Library/Developer/CommandLineTools/SDKs/MacOSX27*.sdk && -d "$fallback_sdk" ]]; then
        export SDKROOT="$fallback_sdk"
    fi
fi
app_version="$(< VERSION)"
if [[ ! "$app_version" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]]; then
    print -u2 "VERSION 형식이 올바르지 않습니다."
    exit 1
fi
sparkle_sdk="$(zsh scripts/fetch-sparkle.sh)"
cargo build --release --locked --manifest-path core/Cargo.toml
cmake -S resources/vendor/mediaremote-adapter -B build/mediaremote -DCMAKE_BUILD_TYPE=Release
cmake --build build/mediaremote --target MediaRemoteAdapter
bundle="$PWD/build/.rium-stage-$$"
destination="${RIUM_APP_DESTINATION:-${PWD:h}/Rium Notch.app}"
previous="$PWD/build/.rium-previous-$$"
signing_identity="${RIUM_SIGNING_IDENTITY:--}"
signing_options=()
if [[ "$signing_identity" == "Developer ID Application:"* || -n "${RIUM_NOTARY_PROFILE:-}" ]]; then
    signing_options=(--options runtime --timestamp)
fi
cleanup() {
    if [[ ! -e "$destination" && -e "$previous" ]]; then mv "$previous" "$destination"; fi
    if [[ -d "$bundle" ]]; then rm -rf "$bundle"; fi
}
trap cleanup EXIT
if ps -axo comm= | rg -F -- "$destination/Contents/MacOS/" >/dev/null; then
    print -u2 "Rium Notch가 실행 중입니다. 종료한 다음 다시 빌드해 주세요."
    exit 1
fi
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources" "$bundle/Contents/Frameworks"
sparkle="$bundle/Contents/Frameworks/Sparkle.framework"
ditto "$sparkle_sdk/Sparkle.framework" "$sparkle"
cp "$sparkle_sdk/LICENSE" "$bundle/Contents/Resources/Sparkle-LICENSE"
if xcrun --find metal >/dev/null 2>&1 && xcrun --find metallib >/dev/null 2>&1; then
    xcrun -sdk macosx metal -c resources/LightSurface.metal -o "$bundle/Contents/Resources/LightSurface.air"
    xcrun -sdk macosx metallib "$bundle/Contents/Resources/LightSurface.air" -o "$bundle/Contents/Resources/LightSurface.metallib"
    rm "$bundle/Contents/Resources/LightSurface.air"
else
    print -u2 "Metal 컴파일러가 없어 밝은 표면 조명에 기본 색 보정을 사용합니다."
fi
swiftc -O -target arm64-apple-macosx14.0 -F "$sparkle_sdk" -framework Sparkle -Xlinker -rpath -Xlinker @executable_path/../Frameworks mac/main.swift mac/SKTUsage.swift mac/RiumCharacter.swift mac/AssistantConnection.swift mac/AssistantController.swift mac/AssistantPage.swift mac/AgentActivityWatcher.swift mac/MediaActivityWatcher.swift mac/SystemNotificationMonitor.swift mac/NotchLight.swift mac/NotchStyles.swift mac/EdgeWave.swift mac/EdgeWaveMetal.swift mac/MemoryPressure.swift mac/Agenda.swift mac/GoogleAgenda.swift mac/AirDropMonitor.swift mac/ScreenshotMonitor.swift mac/ScreenshotCord.swift mac/Dictation.swift mac/VoiceApproval.swift mac/Interview.swift mac/InterviewSystemAudio.swift mac/InterviewDeepgram.swift mac/InterviewCredentials.swift mac/InterviewSuggestions.swift mac/FeedbackSound.swift mac/Teleprompter.swift mac/Notes.swift mac/Power.swift mac/Settings.swift mac/HomeCustomization.swift mac/DashboardHome.swift mac/HomeAtmosphere.swift mac/Updater.swift mac/TimerNotifications.swift mac/WeatherLocation.swift mac/AudioOutput.swift mac/SystemAudioSpectrum.swift core/target/release/librium_notch_core.a -o "$bundle/Contents/MacOS/RiumNotch" -lsqlite3 -framework AppKit -framework SwiftUI -framework CoreText -framework Metal -framework MetalKit -framework Security -framework CoreLocation -framework UniformTypeIdentifiers -framework AVFoundation -framework Speech -framework ApplicationServices -framework IOKit -framework CoreAudio -framework ScreenCaptureKit -framework CoreMedia -framework AudioToolbox -framework ServiceManagement -framework CoreServices -framework UserNotifications -framework ImageIO
cp core/target/release/rium-notch-core "$bundle/Contents/MacOS/rium-notch-core"
cp resources/AppIcon.icns "$bundle/Contents/Resources/AppIcon.icns"
# Local reference artwork is outside the public distribution.
if [[ "${RIUM_INCLUDE_LOCAL_ARTWORK:-1}" == 1 ]]; then
    for artwork in resources/appearance/{weather-art-*.png,sky-*.jpg,hour-*.jpg}(N); do
        cp "$artwork" "$bundle/Contents/Resources/"
    done
fi
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
<key>CFBundleDevelopmentRegion</key><string>ko</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>SUFeedURL</key><string>https://raw.githubusercontent.com/contentriumkorea/rium-notch/main/appcast.xml</string>
<key>SUPublicEDKey</key><string>EDDSA_PUBLIC_KEY</string>
<key>SUEnableAutomaticChecks</key><true/>
<key>SUAllowsAutomaticUpdates</key><false/>
<key>SUVerifyUpdateBeforeExtraction</key><true/>
<key>SURequireSignedFeed</key><true/>
<key>NSDownloadsFolderUsageDescription</key><string>AirDrop으로 받은 파일을 보관함에 표시합니다.</string>
<key>NSDesktopFolderUsageDescription</key><string>스크린샷을 보관함에 표시합니다.</string>
<key>NSLocationUsageDescription</key><string>현재 위치의 날씨를 표시합니다.</string>
<key>NSLocationWhenInUseUsageDescription</key><string>현재 위치의 날씨를 표시합니다.</string>
<key>NSMicrophoneUsageDescription</key><string>받아쓰기, AI 음성 입력, 면접 전사와 사용자가 요청한 음성 답변을 위해 마이크를 사용합니다.</string>
<key>NSSpeechRecognitionUsageDescription</key><string>말씀한 내용을 기기 내 음성 인식으로 텍스트로 변환합니다.</string>
</dict></plist>
PLIST
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $app_version" "$bundle/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $app_version" "$bundle/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :SUPublicEDKey $(< resources/sparkle-public-key.txt)" "$bundle/Contents/Info.plist"
xcrun strip -x "$bundle/Contents/MacOS/RiumNotch"
for helper in "$sparkle/Versions/Current/Autoupdate" "$sparkle/Versions/Current/Updater.app" "$sparkle"/Versions/Current/XPCServices/*.xpc(N); do
    codesign --force "${signing_options[@]}" --sign "$signing_identity" "$helper"
done
codesign --force "${signing_options[@]}" --sign "$signing_identity" "$sparkle"
if [[ "$signing_identity" != "-" ]]; then
    codesign --force "${signing_options[@]}" --sign "$signing_identity" "$bundle/Contents/Resources/mediaremote-adapter/MediaRemoteAdapter.framework"
fi
codesign --force "${signing_options[@]}" --sign "$signing_identity" "$bundle/Contents/MacOS/rium-notch-core"
codesign --force "${signing_options[@]}" --sign "$signing_identity" "$bundle"
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
