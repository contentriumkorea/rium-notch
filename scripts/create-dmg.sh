#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
app_version="$(< VERSION)"
if [[ ! "$app_version" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]]; then
    print -u2 "VERSION 형식이 올바르지 않습니다."
    exit 1
fi
mkdir -p build
notary_profile="${RIUM_NOTARY_PROFILE:-}"
if [[ -n "$notary_profile" && "${RIUM_SIGNING_IDENTITY:--}" == "-" ]]; then
    print -u2 "공증하려면 Developer ID Application 서명 ID를 지정해 주세요."
    exit 1
fi
stage="$(mktemp -d "${TMPDIR:-/tmp}/rium-notch-package.XXXXXXXX")"
trap 'rm -rf "$stage"' EXIT
RIUM_INCLUDE_LOCAL_ARTWORK=0 RIUM_APP_DESTINATION="$stage/Rium Notch.app" zsh build.sh
if [[ -n "$notary_profile" ]]; then
    ditto -c -k --keepParent "$stage/Rium Notch.app" "$stage/notary.zip"
    xcrun notarytool submit "$stage/notary.zip" --keychain-profile "$notary_profile" --wait
    xcrun stapler staple "$stage/Rium Notch.app"
    /usr/bin/syspolicy_check distribution "$stage/Rium Notch.app"
fi
mkdir "$stage/dmg"
mv "$stage/Rium Notch.app" "$stage/dmg/Rium Notch.app"
ln -s /Applications "$stage/dmg/Applications"
cat > "$stage/dmg/설치 안내.txt" <<'NOTE'
Rium Notch 설치 안내

Apple silicon Mac과 macOS 14 이상이 필요합니다.
Rium Notch.app을 Applications 폴더로 드래그하여 복사합니다.

최신 안내: https://github.com/contentriumkorea/rium-notch/releases
NOTE
output="$PWD/build/Rium-Notch-macOS-arm64-unsigned.dmg"
if [[ -n "$notary_profile" ]]; then
    output="$PWD/build/Rium-Notch-macOS-arm64.dmg"
else
    cat >> "$stage/dmg/설치 안내.txt" <<'NOTE'

이 미리보기는 Apple 공증을 받지 않았습니다.
macOS 보안 정책에 따라 다운로드한 앱 실행이 차단될 수 있습니다.
NOTE
fi
hdiutil create -volname "Rium Notch" -srcfolder "$stage/dmg" -format UDZO -ov "$stage/installer.dmg"
if [[ -n "$notary_profile" ]]; then
    codesign --sign "$RIUM_SIGNING_IDENTITY" --timestamp "$stage/installer.dmg"
    xcrun notarytool submit "$stage/installer.dmg" --keychain-profile "$notary_profile" --wait
    xcrun stapler staple "$stage/installer.dmg"
    xcrun stapler validate "$stage/installer.dmg"
fi
mv -f "$stage/installer.dmg" "$output"
(cd "${output:h}" && shasum -a 256 "${output:t}" > "${output:t}.sha256")
print "완료: $output"
