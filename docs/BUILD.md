# 빌드 및 업데이트

## 요구 사항

- Apple silicon Mac, macOS 14 이상
- Xcode Command Line Tools, Rust와 Cargo, CMake
- Rust 의존성과 Sparkle을 처음 내려받기 위한 네트워크 연결

`zsh build.sh`는 Rust 코어와 SwiftUI 앱, 포함된 BSD 라이선스 MediaRemote Adapter 소스를 빌드해 저장소 상위 폴더에 `Rium Notch.app`을 만듭니다. 기존 앱을 덮어쓸 때는 빌드 스크립트의 백업 보호 조건을 충족해야 합니다. 별도 위치에 빌드하려면 `RIUM_APP_DESTINATION`에 앱 번들 전체 경로를 지정하세요.

앱은 기본적으로 릴리스 담당 Mac의 키체인에 보관된 자체 서명 인증서로 서명합니다. 업데이트에도 동일한 인증서의 개인키가 필요하며 개인키를 저장소, 설치 파일 또는 공유 폴더에 넣지 않습니다. 해당 키가 없는 개발자는 `RIUM_SIGNING_IDENTITY=- zsh build.sh`로 임시 서명 빌드를 만들 수 있지만, 이 빌드는 기존 자체 서명 버전과 macOS 권한을 공유하지 않습니다. 자체 서명은 Apple Developer ID 서명이나 공증이 아니므로 다른 Mac에서 바로 설치할 수 있는 검증된 배포 패키지는 아직 없습니다. 서명 ID를 `RIUM_SIGNING_IDENTITY`로 명시적으로 바꿀 수 있으며 이 설정만으로 공증이 완료되지는 않습니다.

## DMG 패키지

최신 릴리스의 Apple silicon용 DMG를 내려받아 마운트하고 `Rium Notch.app`을 `Applications`로 복사합니다. 이 미리보기는 Apple Developer ID 서명과 공증을 받지 않아 macOS가 다운로드한 앱 실행을 차단할 수 있습니다. 다른 Mac에서의 설치·실행 검증은 아직 완료되지 않았습니다. 제거하려면 앱을 종료하고 Applications의 앱 번들을 휴지통으로 옮기세요. 사용자 설정과 저장 데이터는 남습니다.

`zsh scripts/create-dmg.sh`는 현재 `VERSION`에 해당하는 미리보기 DMG와 SHA-256 체크섬을 `build` 폴더에 만듭니다.

서명·공증된 릴리스를 만들 때는 `RIUM_SIGNING_IDENTITY`에 Developer ID Application 서명 ID를, `RIUM_NOTARY_PROFILE`에 `notarytool`의 키체인 프로필 이름을 지정합니다. 두 값을 지정해 같은 스크립트를 실행하면 앱과 DMG를 공증하고 티켓을 첨부합니다. 생성된 `Rium-Notch-macOS-arm64.dmg`를 `VERSION`과 일치하는 안정 릴리스 태그(예를 들어 `v0.2.2`)에 그대로 업로드하세요.

## 업데이트

응용 프로그램 폴더에서 Sparkle이 포함된 버전을 실행하고 **설정 → 일반 → 업데이트**를 누릅니다. 더 높은 버전이 있으면 GitHub에서 다운로드해 서명을 검증한 뒤 앱을 교체하고 다시 엽니다. 자동 확인을 켜면 Sparkle이 새 버전을 찾아 사용자에게 설치 여부를 묻습니다.

v0.2.1 이하를 쓰고 있다면 Sparkle이 포함된 첫 버전을 DMG에서 한 번 설치합니다. 미공증 앱은 macOS 설정에 따라 첫 실행이나 업데이트 후 추가 확인이 필요할 수 있습니다.

업데이트 배포 시 같은 Mac의 키체인에서 `app.rium.notch.updates` 서명 키를 사용합니다. `zsh scripts/create-dmg.sh`로 DMG를 만들고, `zsh scripts/create-appcast.sh build/Rium-Notch-macOS-arm64-unsigned.dmg`로 업데이트 파일과 피드에 서명합니다. `VERSION`과 일치하는 GitHub 안정 릴리스 태그에 DMG를 업로드한 뒤 `build/appcast.xml`을 저장소 루트의 `appcast.xml`로 게시합니다. 피드 내용을 수정할 때는 다시 서명해야 합니다.

## 네트워크와 권한

업데이트 확인 시 GitHub에 요청하며, 날씨는 MET Norway, 가사 조회는 LRCLIB를 사용합니다. 해당 기능을 켜거나 사용할 때 서비스에 요청 정보가 전달됩니다. 일정, 위치, 마이크, 음성 인식, 손쉬운 사용, 다운로드 및 데스크톱 접근은 해당 기능과 macOS 권한 설정에 따라 필요할 수 있습니다. 에이전트 상태는 로컬 Codex·Claude 세션 정보를 관찰하며 대화 내용 전송을 목적으로 하지 않습니다.

## 검증

```sh
cargo test --locked --manifest-path core/Cargo.toml
'/path/to/Rium Notch.app/Contents/MacOS/RiumNotch' --self-test-updater
```

전체 기능, 모든 macOS 버전 및 모든 외부 기기에서의 동작은 아직 검증되지 않았습니다.
