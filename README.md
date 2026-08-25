# AI Usage Pace

AI Usage Pace는 Cursor, Grok, ChatGPT(Codex)의 사용량을 macOS 메뉴 막대에서 확인할 수 있는 앱입니다. 사용 패턴을 분석하여 현재 사용 속도와 예상 소진 시점도 함께 보여 줍니다.

## 주요 기능

- Cursor, Grok Bot, Grok CLI, Codex의 사용량을 한 화면에 표시합니다.
- 월간 한도와 주간 한도를 각각의 주기에 맞게 분석합니다.
- 사용 속도와 예상 소진 시점의 신뢰도를 `낮음`, `중간`, `높음`으로 표시합니다.
- 사용 속도나 예상 소진 시점에 마우스 포인터를 올리면 계산 방법과 판단 근거를 확인할 수 있습니다.
- 한국어와 영어를 지원하며, 날짜와 숫자도 선택한 언어에 맞게 표시합니다.

## 요구 사항

- macOS 14 이상
- Xcode 16 이상

외부 Swift Package Manager 의존성은 없습니다.

## 실행 방법

1. Cursor 앱에 로그인하거나, 사용할 CLI에서 `grok login` 또는 `codex login`을 실행합니다. 사용할 서비스에만 로그인해도 됩니다.
2. Xcode에서 `AIUsagePace.xcodeproj`를 엽니다.
3. `AIUsagePace` 스킴을 선택한 뒤 앱을 실행합니다.

메뉴 막대의 `Settings…`에서 `Language`를 `System Default`, `English`, `한국어` 중 하나로 설정할 수 있습니다. 선택한 언어는 메뉴 막대, 사용량 지표, 오류 안내, 설정 화면, 날짜와 숫자에 즉시 적용됩니다. 설정값은 `appLanguage`에 저장됩니다.

`System Default`를 선택하면 시스템 언어가 한국어일 때는 한국어를 사용하고, 그 밖의 언어에서는 영어를 사용합니다.

## 지원하는 사용량

현재 버전에서는 테스트 픽스처(fixture)를 통해 응답 구조를 검증한 개인 계정만 지원합니다.

- 월간: Cursor Models, Other Models
- 주간: Grok Bot, Grok CLI, Codex Weekly
- 단기 세션: Codex Session

Cursor, Grok CLI, Codex 가운데 일부에만 로그인해도 해당 서비스의 사용량은 정상적으로 표시됩니다. Grok Bot의 사용량을 가져오지 못하더라도 Cursor Models와 Other Models는 계속 표시됩니다.

## 예측 방식

사용 속도는 초기화 시점까지 예상되는 사용량을 현재 남은 사용량으로 나눈 값입니다. `1.0×`라면 현재 패턴을 유지했을 때 초기화 시점과 비슷한 시기에 한도를 모두 사용할 것으로 예상한다는 뜻입니다.

앱을 처음 실행한 뒤 첫 24시간 동안에는 주기 시작 이후의 평균 사용량을 바탕으로 임시 예측값을 표시합니다. 관측 초기의 사용량을 전체 주기로 과도하게 확대하지 않도록, 측정한 사용 속도를 `1.0×`에 해당하는 중립적인 값과 혼합합니다. 이때 예측 신뢰도는 `낮음`으로 표시합니다.

충분한 기록이 쌓이면 패턴 기반 예측으로 자동 전환됩니다.

- Cursor Models와 Other Models는 현재 월의 요일·시간대별 사용 패턴을 분석합니다.
- Grok Bot, Grok CLI, Codex Weekly는 이전 기록이 있으면 최근 최대 8개 주간 주기를 현재 주의 패턴과 혼합합니다. 최근 기록에는 더 높은 가중치를 적용합니다.
- 예상 사용량은 15분 단위로 초기화 시점까지 누적합니다. 누적값이 남은 사용량에 처음 도달하는 시각을 예상 소진 시점으로 표시합니다.
- 긴 미관측 구간이나 주기별 사용량 차이가 크면 신뢰도를 낮춥니다.

사용 속도와 예상 소진 시점 옆의 정보 아이콘에 마우스 포인터를 올리거나 아이콘을 클릭하면 신뢰도, 계산 과정, 관측 기간, 반영한 과거 주기 수를 확인할 수 있습니다.

앱은 15분마다 사용량을 갱신합니다. Mac이 잠자기 상태에서 깨어나거나 사용자가 `Refresh`를 선택했을 때도 사용량을 갱신합니다. 새로 고침 간격이 불규칙하더라도 예측할 때는 경과 시간을 기준으로 사용량을 15분 구간에 정규화합니다.

메뉴 막대에는 권장 속도 대비 실제 사용 속도의 비율이 가장 높은 사용량 풀을 표시합니다. 이 비율을 계산할 수 없으면 현재 사용률이 가장 높은 풀을 표시합니다. 아이콘은 해당 사용량 풀을 제공하는 Cursor, Grok, Codex 가운데 하나를 나타냅니다.

## 지원하지 않는 범위

- 팀·기업용 요금제와 무제한 계정은 지원하지 않습니다.
- 응답 구조를 검증하지 않은 계정 유형이나 사용 주기는 표시하지 않을 수 있습니다.
- 선불 사용량, Management API, API 키 사용량, 크레디트 잔액과 지출 한도는 표시하지 않습니다.
- 서버가 초기화 시각을 제공하지 않으면 임의로 추정하지 않습니다.
- 사용 주기가 짧으면 패턴을 충분히 학습하기 어려우므로 낮은 신뢰도의 임시 예측을 계속 표시할 수 있습니다.
- 앱 내부의 로그인 화면과 Mac App Store 배포는 지원하지 않습니다.

## 개인정보 보호

### 로컬에서 읽는 인증 정보

앱은 사용량을 갱신할 때 다음 인증 정보만 로컬에서 읽습니다.

| 서비스 | 파일 | 읽는 값 |
| --- | --- | --- |
| Cursor·Grok Bot | Cursor의 `state.vscdb` | `cursorAuth/accessToken` |
| Grok CLI | `~/.grok/auth.json` | `key` 또는 `access_token` |
| Codex | `~/.codex/auth.json` | `tokens.access_token`, `tokens.account_id` |

Codex의 `tokens.account_id`가 없으면 액세스 토큰의 `chatgpt_account_id` 클레임을 사용합니다. `tokens.id_token`, `tokens.refresh_token`, `OPENAI_API_KEY`는 읽지 않습니다.

앱은 다음 정보도 읽지 않습니다.

- `refreshToken`과 `refresh_token`
- Stripe 멤버십 정보와 추적용 데이터베이스
- 채팅 및 프로젝트 파일
- 이메일과 이름

인증 토큰을 Keychain에 별도로 저장하지 않으며, Cursor 데이터베이스나 `auth.json`을 복사하거나 수정하지 않습니다. 앱은 인증 토큰을 직접 갱신하지 않습니다.

Grok CLI 세션이 만료되면 `grok login`을 다시 실행해야 합니다. Codex 액세스 토큰이 만료되면 Codex CLI가 토큰을 갱신할 때까지 `Session expired`가 표시됩니다.

### 네트워크 요청

네트워크 요청은 다음 주소로 제한합니다.

```text
GET  https://cursor.com/api/usage-summary
POST https://cursor.com/api/dashboard/get-sand-usage-status
GET  https://cli-chat-proxy.grok.com/v1/billing?format=credits
GET  https://chatgpt.com/backend-api/wham/usage
```

Grok Bot 요청에는 `Cookie: WorkosCursorSessionToken`과 `Origin: https://cursor.com`을 사용합니다. Codex 요청에는 `Authorization: Bearer`와 필요한 경우 `ChatGPT-Account-Id`를 사용합니다.

앱은 HTTPS 연결과 호스트 허용 목록을 강제합니다. 리디렉션이 발생하면 이동할 호스트도 다시 검사합니다. HTTP 요청 및 응답의 본문과 헤더는 로그에 기록하지 않습니다.

### 사용량 이력

사용량 이력은 다음 경로에 JSON Lines 형식으로 저장합니다.

```text
~/Library/Application Support/AIUsagePace/history/<fingerprint>.jsonl
```

`fingerprint`는 JWT의 `sub` 값을 SHA-256으로 해시하여 만든 문자열이므로 이메일이나 인증 토큰을 포함하지 않습니다. 같은 계정에 속한 사용량 풀은 동일한 `fingerprint`를 사용하며, 서로 다른 계정의 이력은 별도의 파일에 저장됩니다.

## 테스트

다음 명령어로 전체 테스트를 실행할 수 있습니다.

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -project AIUsagePace.xcodeproj -scheme AIUsagePace -destination 'platform=macOS' test
```

시스템의 활성 개발자 경로가 Command Line Tools로 지정되어 있다면 `DEVELOPER_DIR`을 위와 같이 설정해야 합니다.

## 배포

현재 프로젝트는 App Sandbox를 사용하지 않으며 Mac App Store 배포를 지원하지 않습니다. Debug 빌드는 로컬 임시 서명을 사용합니다.

Release 빌드는 `Developer ID Application` 인증서로 서명하고 공증한 뒤 GitHub Releases를 통해 직접 배포하도록 구성되어 있습니다. Release 빌드를 생성하려면 로컬 환경이나 CI에 배포 인증서를 설정해야 합니다.

## 문제 해결

Xcode 콘솔에 다음 메시지가 나타날 수 있습니다.

```text
com.apple.linkd.autoShortcut
Error registering app with intents framework
```

이 메시지는 macOS가 로컬 실행 환경에서 App Intents와 단축어를 자동으로 등록하는 과정에서 발생할 수 있습니다. AI Usage Pace는 App Intents를 사용하지 않습니다. 메뉴 막대 기능이 정상적으로 작동한다면 이 메시지를 무시해도 됩니다.

## 라이선스

이 프로젝트는 [MIT 라이선스](LICENSE)를 따릅니다.
