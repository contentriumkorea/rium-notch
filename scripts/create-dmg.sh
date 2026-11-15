#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
app_version="$(< VERSION)"
if [[ ! "$app_version" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]]; then
    print -u2 "VERSION 형식이 올바르지 않습니다."
    exit 1
fi
mkdir -p build
stage="$(mktemp -d "${TMPDIR:-/tmp}/rium-notch-package.XXXXXXXX")"
trap 'rm -rf "$stage"' EXIT
RIUM_APP_DESTINATION="$stage/Rium Notch.app" zsh build.sh
mkdir "$stage/dmg"
mv "$stage/Rium Notch.app" "$stage/dmg/Rium Notch.app"
ln -s /Applications "$stage/dmg/Applications"
cat > "$stage/dmg/설치 안내.txt" <<'NOTE'
Rium Notch 설치 안내

Apple silicon Mac과 macOS 14 이상이 필요합니다.
Rium Notch.app을 Applications 폴더로 드래그하여 복사합니다.

이 미리보기는 Apple Developer ID 서명과 공증을 받지 않았습니다.
macOS 보안 정책에 따라 다운로드한 앱 실행이 차단될 수 있습니다.
다른 Mac에서 설치 및 실행은 아직 검증되지 않았습니다.

최신 안내: https://github.com/contentriumkorea/rium-notch/releases
NOTE
output="$PWD/build/Rium-Notch-macOS-arm64-unsigned.dmg"
hdiutil create -volname "Rium Notch" -srcfolder "$stage/dmg" -format UDZO -ov "$output"
(cd "${output:h}" && shasum -a 256 "${output:t}" > "${output:t}.sha256")
print "완료: $output"
