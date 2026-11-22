#!/bin/zsh
set -euo pipefail
if (( $# != 1 )) || [[ ! -f "$1" || "$1" != *.dmg ]]; then
    print -u2 "사용법: zsh scripts/create-appcast.sh <배포할 DMG>"
    exit 1
fi
dmg="${1:A}"
cd "${0:A:h:h}"
version="$(< VERSION)"
if [[ ! "$version" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]]; then
    print -u2 "VERSION 형식이 올바르지 않습니다."
    exit 1
fi
sdk="$(zsh scripts/fetch-sparkle.sh)"
account=app.rium.notch.updates
if [[ "$("$sdk/bin/generate_keys" --account "$account" -p)" != "$(< resources/sparkle-public-key.txt)" ]]; then
    print -u2 "이 Mac의 업데이트 서명 키가 앱의 공개 키와 일치하지 않습니다."
    exit 1
fi
stage="$(mktemp -d "$PWD/build/.appcast.XXXXXXXX")"
trap 'rm -rf "$stage"' EXIT
cp "$dmg" "$stage/"
"$sdk/bin/generate_appcast" --account "$account" --versions "$version" --maximum-deltas 0 \
    --download-url-prefix "https://github.com/contentriumkorea/rium-notch/releases/download/v$version/" "$stage"
if ! rg -q 'sparkle-signatures:' "$stage/appcast.xml"; then
    print -u2 "서명된 업데이트 목록을 만들지 못했습니다."
    exit 1
fi
mv -f "$stage/appcast.xml" "$PWD/build/appcast.xml"
print -r -- "$PWD/build/appcast.xml"
