# AI Usage Pace

macOS 메뉴바 앱입니다. Cursor AI 사용량을 두 개의 독립 풀로 보여 주고, 지금 속도로 가면 언제 소진되는지를 같이 표시합니다.

## 지원 범위

MVP는 fixture로 검증된 **개인 계정 two-pool** `usage-summary` 형태만 지원합니다. 확인된 예는 Cursor Pro Plus (`membershipType: pro_plus`, `limitType: user`)입니다.

지원하지 않습니다.

- Team / Enterprise / Business, `limitType: team`, unlimited
- Start 등 Cursor Models만 있는 형태 (해당 fixture가 생기기 전)
- Grok 등 다른 provider, 로그인 UI, Mac App Store

`plan.used` / `plan.limit`은 전체 quota로 쓰지 않습니다. 메뉴바와 예측 입력은 `autoPercentUsed`(Cursor Models)와 `apiPercentUsed`(Other Models)입니다.

## 개인정보

- 읽는 값: Cursor `state.vscdb`의 `cursorAuth/accessToken`만. 매 refresh마다 다시 읽습니다.
- 읽지 않는 값: `refreshToken`, Stripe membership, tracking DB, 채팅/프로젝트 파일.
- 이 앱은 토큰을 Keychain에 저장하지 않고, Cursor DB를 복사하지 않으며, Cursor에 토큰을 다시 쓰지 않습니다.
- 네트워크: `GET https://cursor.com/api/usage-summary`만. HTTPS와 호스트 allowlist를 강제하고, redirect 호스트도 다시 검사합니다. 요청/응답 body와 헤더는 로그에 남기지 않습니다.
- 로컬 이력: `~/Library/Application Support/AIUsagePace/history/<fingerprint>.jsonl`. fingerprint는 JWT `sub`의 SHA-256이며 이메일·토큰이 아닙니다.

## 배포

App Sandbox는 꺼져 있습니다. Mac App Store용이 아닙니다. Debug는 로컬 임시 서명을 사용하고, Release는 `Developer ID Application` 인증서로 서명한 뒤 notarization하여 GitHub Releases로 직접 배포하는 것을 전제로 합니다. Release 빌드에는 로컬 또는 CI에서 배포 인증서 설정이 필요합니다.

라이선스는 [MIT](LICENSE)입니다.

## 실행

macOS 14+, Xcode 16+. 외부 SPM 의존성 없음.

1. Cursor에 로그인한 뒤 이 앱을 실행합니다.
2. Xcode에서 `AIUsagePace.xcodeproj`의 scheme `AIUsagePace`로 Run 합니다.

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -project AIUsagePace.xcodeproj -scheme AIUsagePace -destination 'platform=macOS' test
```

Command Line Tools만 선택된 환경에서는 위 `DEVELOPER_DIR`이 필요합니다.

Xcode 콘솔의 `com.apple.linkd.autoShortcut` / `Error registering app with intents framework`는 Cursor 사용량 오류가 아닙니다. 로컬 실행 환경에서 macOS의 App Intents/Shortcuts 자동 등록 과정과 관련된 경고가 출력될 수 있습니다. 이 앱은 App Intents를 사용하지 않으므로 메뉴바 기능이 정상이라면 무시해도 됩니다.

처음 몇 시간은 이력이 부족하면 Today / Pace / Exhaustion이 `Not enough data`로 나옵니다. 15분마다, 맥이 깨어날 때, 그리고 Refresh로 갱신합니다.
