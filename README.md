# AI Usage Pace

AI Usage Pace는 Cursor와 Grok의 AI 사용량을 macOS 메뉴 막대에서 확인할 수 있는 앱입니다. 현재 사용 속도를 분석하여 각 사용량 한도가 언제 소진될지도 함께 보여 줍니다.

## 지원 범위

현재 MVP는 테스트 픽스처(fixture)로 응답 구조를 검증한 개인 계정만 지원합니다.

- Cursor에서는 두 가지 월간 사용량 풀이 포함된 `usage-summary` 응답을 지원합니다. 검증을 마친 계정 유형은 Cursor Pro Plus(`membershipType: pro_plus`, `limitType: user`)입니다.
- 같은 Cursor 계정에서 Grok Bot 주간 사용량은 `POST /api/dashboard/get-sand-usage-status` 응답의 `usagePercent`를 사용합니다. `hasNonZeroIncludedLimit`가 `true`이고 `usagePercent`가 있는 계정만 표시합니다.
- Grok CLI는 `GET /v1/billing?format=credits` 응답의 주간 `creditUsagePercent` 풀만 지원합니다. `productUsage`는 같은 주간 한도의 세부 내역이므로 별도의 사용량 풀로 처리하지 않습니다.

Cursor의 `plan.used`와 `plan.limit`은 전체 사용량 한도로 간주하지 않습니다. 메뉴 막대 표시와 소진 시점 예측에는 `autoPercentUsed`(Cursor Models)와 `apiPercentUsed`(Other Models)를 사용합니다. Grok Bot에는 `usagePercent`를 사용합니다. Grok CLI에는 `config.creditUsagePercent`를 사용합니다.

Grok Bot과 Grok CLI는 서로 다른 사용량 풀입니다. Grok Bot은 Cursor 계정에 연결된 별도 주간 사용량이고, Grok CLI는 `~/.grok/auth.json` 계정에 연결된 주간 사용량입니다. Cursor에서 쓰는 Grok 모델 호출은 Cursor Models 또는 Other Models에 포함되며 Grok Bot 사용량이 아닙니다.

Cursor와 Grok CLI 중 한쪽에 로그인하지 않았더라도, 로그인된 서비스의 사용량은 정상적으로 표시합니다. Grok Bot 조회가 실패해도 Cursor Models와 Other Models는 계속 표시합니다.

### 지원하지 않는 범위

- Cursor의 Team, Enterprise, Business 요금제와 `limitType: team` 또는 `unlimited`인 계정은 지원하지 않습니다.
- Cursor Start처럼 Cursor Models 풀만 제공하는 응답은 검증용 픽스처를 확보하기 전까지 지원하지 않습니다.
- Grok Bot에서 `hasNonZeroIncludedLimit`가 `true`가 아닌 계정, `includedLimitZero`가 `true`인 응답, `usesPooledEnterpriseAllowance`가 `true`인 응답은 표시하지 않습니다. `nextResetTimestampUtc`가 있으면 그 시각을 주간 종료로 사용하고, 없으면 Reset을 표시하지 않습니다. 시작 시각으로부터 7일을 추정하지 않습니다.
- 주간 단위가 아닌 Grok CLI 사용 기간과 xAI Console의 선불(prepaid) 사용량 및 Management API는 지원하지 않습니다.
- 앱 내 로그인 화면과 Mac App Store 배포는 지원하지 않습니다.

## 개인정보

앱은 사용량을 갱신할 때마다 다음 인증 정보만 로컬에서 읽습니다.

- Cursor의 `state.vscdb`에서는 `cursorAuth/accessToken`을 읽습니다. Grok Bot도 이 Cursor 세션을 사용하며 별도 인증 파일을 읽지 않습니다.
- Grok CLI의 `~/.grok/auth.json`에서는 액세스 토큰(access token)인 `key` 또는 `access_token`을 읽습니다.

앱은 `refreshToken`과 `refresh_token`, Stripe 멤버십 정보, 추적용 데이터베이스(tracking DB), 채팅 및 프로젝트 파일, 이메일과 이름을 읽지 않습니다. 인증 토큰을 Keychain에 저장하거나, Cursor DB 또는 `auth.json`을 복사하거나 수정하지도 않습니다. Grok CLI 세션이 만료되면 사용자가 `grok login`을 다시 실행해야 합니다.

네트워크 요청은 다음 주소로 보내는 요청으로 제한합니다.

- `GET https://cursor.com/api/usage-summary`
- `POST https://cursor.com/api/dashboard/get-sand-usage-status` (`Cookie: WorkosCursorSessionToken`, `Origin: https://cursor.com`)
- `GET https://cli-chat-proxy.grok.com/v1/billing?format=credits`

앱은 HTTPS 연결과 호스트 허용 목록을 강제하며, 리디렉션이 발생하면 이동할 호스트도 다시 검사합니다. HTTP 요청 및 응답의 본문과 헤더는 로그에 기록하지 않습니다.

사용량 이력은 `~/Library/Application Support/AIUsagePace/history/<fingerprint>.jsonl`에 저장합니다. `fingerprint`는 JWT의 `sub` 값을 SHA-256으로 해시한 문자열이므로 이메일이나 인증 토큰을 포함하지 않습니다. Cursor Models, Other Models, Grok Bot은 Cursor fingerprint를 공유하고, Grok CLI는 Grok CLI fingerprint를 사용합니다.

## 배포

현재 프로젝트에서는 App Sandbox를 사용하지 않으며, Mac App Store 배포를 지원하지 않습니다. Debug 빌드에는 로컬 임시 서명을 사용합니다. Release 빌드는 `Developer ID Application` 인증서로 서명하고 공증한 뒤 GitHub Releases를 통해 직접 배포하는 방식을 전제로 합니다. 따라서 Release 빌드를 생성하려면 로컬 환경이나 CI에 배포 인증서를 설정해야 합니다.

이 프로젝트는 [MIT 라이선스](LICENSE)를 따릅니다.

## 실행

macOS 14 이상과 Xcode 16 이상이 필요합니다. 외부 Swift Package Manager 의존성은 없습니다.

1. Cursor 앱에서 로그인하거나 `grok login`을 실행하여 사용할 서비스에 로그인합니다. 두 서비스를 모두 사용할 수도 있습니다.
2. Xcode에서 `AIUsagePace.xcodeproj`를 열고 `AIUsagePace` 스킴을 선택한 뒤 앱을 실행합니다.

메뉴 막대의 `Settings…`에서 `Language`를 `System Default`, `English`, `한국어` 중에서 선택할 수 있습니다. 선택한 언어는 메뉴 막대, 사용량 지표, 오류 및 복구 안내, 설정 화면, 날짜와 숫자 표시에 즉시 적용되며 `appLanguage` 설정으로 저장됩니다. `System Default`에서는 시스템 언어가 한국어일 때 한국어를 사용하고, 그 외에는 영어를 사용합니다.

다음 명령어로 테스트를 실행할 수 있습니다.

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -project AIUsagePace.xcodeproj -scheme AIUsagePace -destination 'platform=macOS' test
```

시스템의 활성 개발자 경로가 Command Line Tools로 지정되어 있다면 위와 같이 `DEVELOPER_DIR`을 설정해야 합니다.

## 알아둘 점

Xcode 콘솔에 나타나는 `com.apple.linkd.autoShortcut`과 `Error registering app with intents framework` 메시지는 사용량 조회 오류가 아닙니다. 이 메시지는 로컬 실행 환경에서 macOS가 App Intents 및 단축어를 자동으로 등록하는 과정에서 나타날 수 있습니다. AI Usage Pace는 App Intents를 사용하지 않으므로 메뉴 막대 기능이 정상적으로 작동한다면 이 메시지를 무시해도 됩니다.

앱을 처음 실행한 뒤 몇 시간 동안은 분석할 이력이 충분하지 않아서 `Used today`, `Usage pace`, `Runs out` 항목에 `Collecting data…`가 표시될 수 있습니다. 앱은 15분마다 사용량을 갱신하며, Mac이 잠자기 상태에서 깨어나거나 사용자가 `Refresh`를 선택했을 때도 사용량을 갱신합니다.

메뉴 막대에는 권장 속도 대비 실제 사용 속도의 비율이 가장 높은 사용량 풀이 표시됩니다. 이 비율을 계산할 수 없는 경우에는 현재 사용률이 가장 높은 풀을 표시합니다. `C`, `O`, `B`, `G`는 각각 Cursor Models, Other Models, Grok Bot, Grok CLI를 의미합니다.
