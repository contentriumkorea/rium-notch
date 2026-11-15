# 빌드 및 업데이트

## 요구 사항

- Apple silicon Mac, macOS 14 이상
- Xcode Command Line Tools, Rust와 Cargo, CMake
- Rust 의존성을 처음 내려받기 위한 네트워크 연결

`zsh build.sh`는 Rust 코어와 SwiftUI 앱, 포함된 BSD 라이선스 MediaRemote Adapter 소스를 빌드해 저장소 상위 폴더에 `Rium Notch.app`을 만듭니다. 기존 앱을 덮어쓸 때는 빌드 스크립트의 백업 보호 조건을 충족해야 합니다. 별도 위치에 빌드하려면 `RIUM_APP_DESTINATION`에 앱 번들 전체 경로를 지정하세요.

앱은 기본적으로 임시 서명(ad hoc)됩니다. Apple Developer ID 서명과 공증을 받지 않았으므로, 다른 Mac에서 바로 설치할 수 있는 검증된 배포 패키지는 아직 없습니다. 서명 ID가 있는 개발자는 `RIUM_SIGNING_IDENTITY`를 설정해 빌드할 수 있지만 이 설정만으로 공증이 완료되지는 않습니다.

## 업데이트

설정의 일반 화면에서 GitHub 릴리스를 수동 확인하고 릴리스 페이지를 열 수 있습니다. 자동 확인은 기본적으로 켜져 있으며 설정에서 끌 수 있습니다. 켜져 있을 때 앱은 시작 시 확인하고 성공한 확인 후 하루가 지나면 다시 GitHub 최신 릴리스 API를 조회합니다. 실패할 경우 한 시간 뒤 재시도합니다. 앱은 업데이트를 자동으로 내려받거나 설치하지 않습니다. 새 버전을 적용하려면 릴리스 내용을 확인하고 소스에서 직접 빌드하세요.

## 네트워크와 권한

업데이트 확인 시 GitHub에 요청하며, 날씨는 MET Norway, 가사 조회는 LRCLIB를 사용합니다. 해당 기능을 켜거나 사용할 때 서비스에 요청 정보가 전달됩니다. 일정, 위치, 마이크, 음성 인식, 손쉬운 사용, 다운로드 및 데스크톱 접근은 해당 기능과 macOS 권한 설정에 따라 필요할 수 있습니다. 에이전트 상태는 로컬 Codex·Claude 세션 정보를 관찰하며 대화 내용 전송을 목적으로 하지 않습니다.

## 검증

```sh
cargo test --locked --manifest-path core/Cargo.toml
'/path/to/Rium Notch.app/Contents/MacOS/RiumNotch' --self-test-updater
```

전체 기능, 모든 macOS 버전 및 모든 외부 기기에서의 동작은 아직 검증되지 않았습니다.
