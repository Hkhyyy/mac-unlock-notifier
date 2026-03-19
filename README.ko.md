# UnlockNotifier

[English](README.md)

Mac 잠금 해제 시 내장 카메라로 사진을 촬영하고, [ntfy.sh](https://ntfy.sh)를 통해 iPhone으로 푸시 알림을 보내는 macOS 메뉴바 앱입니다.

## 기능

- Mac 화면 잠금 해제 이벤트 실시간 감지
- 내장 카메라로 사진 촬영 (AVFoundation)
- ntfy.sh를 통한 사진 첨부 푸시 알림 전송
- macOS 메뉴바 앱 (SF Symbols 상태 아이콘)
- GUI 설정: ntfy 토픽, 알림 제목/내용 (`{hostname}`, `{timestamp}` 변수 지원)
- 메뉴바에서 카메라 권한 관리
- 테스트 알림 버튼
- 로그인 시 자동 시작 (LaunchAgent, 첫 실행 시 자동 설치)
- 외부 의존성 없음 (Homebrew 패키지 불필요)

## 요구사항

- macOS 13.0 이상
- Xcode Command Line Tools (`xcode-select --install`)
- iPhone [ntfy](https://ntfy.sh) 앱 (무료)

## 설치

### 방법 1: DMG 다운로드 (권장)

1. [Releases](../../releases) 페이지에서 `UnlockNotifier.dmg` 다운로드
2. DMG를 열고 `UnlockNotifier.app`을 `Applications`으로 드래그
3. Applications에서 `UnlockNotifier` 실행
4. 카메라 권한 허용
5. 메뉴바의 자물쇠 아이콘 클릭 → ntfy 토픽 설정
6. iPhone ntfy 앱에서 동일한 토픽 구독

### 방법 2: 소스에서 빌드

```bash
git clone https://github.com/Hkhyyy/mac-unlock-notifier.git
cd mac-unlock-notifier
./build.sh
cp -R build/UnlockNotifier.app /Applications/
open /Applications/UnlockNotifier.app
```

## 메뉴바

| 아이콘 | 상태 |
|--------|------|
| 🛡️ (lock.shield) | 모니터링 중 — 정상 |
| ⚠️ (lock.trianglebadge) | 설정 필요 — 카메라 또는 토픽 미설정 |
| 🔓 (lock.open) | 처리 중 — 촬영 및 전송 중 |

아이콘 클릭 시:
- 상태 및 마지막 이벤트 시각
- 카메라 권한 관리
- ntfy 토픽 설정
- 알림 메시지 커스터마이징
- 테스트 알림
- 웹 대시보드 열기

## 동작 원리

1. `DistributedNotificationCenter`로 `com.apple.screenIsUnlocked` 이벤트 감지
2. `AVFoundation`으로 내장 카메라 사진 촬영
3. ntfy.sh에 사진 업로드 후, JSON API로 알림 전송
4. iPhone에 사진 첨부 푸시 알림 수신

## 제거

메뉴바 → **Uninstall...** 클릭 (LaunchAgent, 설정, 앱 모두 자동 삭제)

또는 수동 제거:
```bash
launchctl unload ~/Library/LaunchAgents/com.user.unlock-notifier.plist
rm ~/Library/LaunchAgents/com.user.unlock-notifier.plist
rm -rf /Applications/UnlockNotifier.app
```

## 라이선스

[MIT](LICENSE)
