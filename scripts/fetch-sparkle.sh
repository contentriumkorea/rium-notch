#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
version=2.10.1
checksum=1a856d2a9edb8e628de88121d7be04cf0e2167f8641650b78fca00b14244cf27
archive="Sparkle-$version.tar.xz"
cache="$PWD/build/sparkle-$version"
if [[ ! -d "$cache/Sparkle.framework" ]]; then
    mkdir -p build
    stage="$(mktemp -d "$PWD/build/.sparkle.XXXXXXXX")"
    trap 'rm -rf "$stage"' EXIT
    curl --fail --silent --show-error --location --proto '=https' --retry 2 \
        "https://github.com/sparkle-project/Sparkle/releases/download/$version/$archive" -o "$stage/$archive"
    printf '%s  %s\n' "$checksum" "$stage/$archive" | shasum -a 256 --check --status
    mkdir "$stage/sdk"
    tar -xJf "$stage/$archive" -C "$stage/sdk"
    if [[ ! -d "$cache/Sparkle.framework" ]]; then
        mv "$stage/sdk" "$cache"
    fi
fi
print -r -- "$cache"
