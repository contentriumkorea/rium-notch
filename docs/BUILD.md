# 빌드 및 업데이트

## 요구 사항

- Apple silicon Mac, macOS 14 이상
- Xcode Command Line Tools, Rust와 Cargo, CMake
- Rust 의존성을 처음 내려받기 위한 네트워크 연결

`zsh build.sh`는 Rust 코어와 SwiftUI 앱, 포함된 BSD 라이선스 MediaRemote Adapter 소스를 빌드해 저장소 상위 폴더에 `Rium Notch.app`을 만듭니다. 기존 앱을 덮어쓸 때는 빌드 스크립트의 백업 보호 조건을 충족해야 합니다. 별도 위치에 빌드하려면 `RIUM_APP_DESTINATION`에 앱 번들 전체 경로를 지정하세요.

앱은 기본적으로 임시 서명(ad hoc)됩니다. Apple Developer ID 서명과 공증을 받지 않았으므로, 다른 Mac에서 바로 설치할 수 있는 검증된 배포 패키지는 아직 없습니다. 서명 ID가 있는 개발자는 `RIUM_SIGNING_IDENTITY`를 설정해 빌드할 수 있지만 이 설정만으로 공증이 완료되지는 않습니다.

## DMG 패키지

최신 릴리스의 Apple silicon용 DMG를 내려받아 마운트하고 `Rium Notch.app`을 `Applications`로 복사합니다. 이 미리보기는 Apple Developer ID 서명과 공증을 받지 않아 macOS가 다운로드한 앱 실행을 차단할 수 있습니다. 다른 Mac에서의 설치·실행 검증은 아직 완료되지 않았습니다. 제거하려면 앱을 종료하고 Applications의 앱 번들을 휴지통으로 옮기세요. 사용자 설정과 저장 데이터는 남습니다.

`zsh scripts/create-dmg.sh`는 현재 `VERSION`에 해당하는 미리보기 DMG와 SHA-256 체크섬을 `build` 폴더에 만듭니다.

서명·공증된 릴리스를 만들 때는 `RIUM_SIGNING_IDENTITY`에 Developer ID Application 서명 ID를, `RIUM_NOTARY_PROFILE`에 `notarytool`의 키체인 프로필 이름을 지정합니다. 두 값을 지정해 같은 스크립트를 실행하면 앱과 DMG를 공증하고 티켓을 첨부합니다. 생성된 `Rium-Notch-macOS-arm64.dmg`를 `VERSION`과 일치하는 안정 릴리스 태그(예를 들어 `v0.2.2`)에 그대로 업로드하세요.

## 업데이트

서명·공증된 배포본을 응용 프로그램 폴더에서 실행한 뒤 **설정 → 일반 → 업데이트**를 누릅니다. GitHub 최신 릴리스에 더 높은 버전의 서명·공증된 DMG가 있으면 다운로드, 검증, 앱 교체, 재실행이 이어집니다. 앱 교체 전 GitHub의 SHA-256, 번들 ID, 버전, 설치본의 서명 요구 사항과 macOS 배포 정책을 확인합니다.

자동 확인은 기본으로 켜져 있으며 새 버전 유무를 확인합니다. 설치는 **업데이트**를 눌렀을 때 진행됩니다. v0.2.1 이하 또는 임시 서명된 미리보기에서 옮겨 올 때는 첫 서명·공증된 배포본을 DMG에서 한 번 설치해야 합니다.

## 네트워크와 권한

업데이트 확인 시 GitHub에 요청하며, 날씨는 MET Norway, 가사 조회는 LRCLIB를 사용합니다. 해당 기능을 켜거나 사용할 때 서비스에 요청 정보가 전달됩니다. 일정, 위치, 마이크, 음성 인식, 손쉬운 사용, 다운로드 및 데스크톱 접근은 해당 기능과 macOS 권한 설정에 따라 필요할 수 있습니다. 에이전트 상태는 로컬 Codex·Claude 세션 정보를 관찰하며 대화 내용 전송을 목적으로 하지 않습니다.

## 검증

```sh
cargo test --locked --manifest-path core/Cargo.toml
'/path/to/Rium Notch.app/Contents/MacOS/RiumNotch' --self-test-updater
```

전체 기능, 모든 macOS 버전 및 모든 외부 기기에서의 동작은 아직 검증되지 않았습니다.
